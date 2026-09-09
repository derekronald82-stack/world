"""Copy legacy local Catws media into Supabase Storage without deleting anything.

Run from the backend directory with the production environment variables set:

    python scripts/migrate_media_to_supabase.py

The script updates only song object-path metadata. Local media and the old
database are deliberately retained as rollback backups until playback has
been verified after a Render redeploy.
"""

from __future__ import annotations

import logging
import mimetypes
import sys
from pathlib import Path
from uuid import uuid4

from sqlalchemy import select

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.config import settings
from app.db import Base, SessionLocal, engine, migrate_song_columns
from app.models import Song
from app.services.storage import exists, get_public_url, normalize_object_path, upload_file, delete_relative


logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
logger = logging.getLogger("catws-media-migration")


def _project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _candidate_roots() -> list[Path]:
    backend_root = Path(__file__).resolve().parents[1]
    project_root = _project_root()
    configured = Path(settings.media_root)
    if not configured.is_absolute():
        configured = Path.cwd() / configured
    return list(dict.fromkeys([
        configured,
        backend_root / "media",
        project_root / "media",
        project_root,
    ]))


def _local_file(value: str | None) -> Path | None:
    if not value:
        return None
    normalized = normalize_object_path(value).replace("/", "\\")
    raw = Path(value)
    if raw.is_absolute() and raw.is_file():
        return raw
    relative = Path(normalized)
    if relative.is_absolute() or ".." in relative.parts:
        return None
    for root in _candidate_roots():
        candidate = (root / relative).resolve()
        root_resolved = root.resolve()
        if root_resolved in candidate.parents and candidate.is_file():
            return candidate
    return None


def _content_type(path: Path, fallback: str) -> str:
    return mimetypes.guess_type(path.name)[0] or fallback


def _destination(song: Song, kind: str, path: Path) -> str:
    family = "eightd" if (song.song_type or "normal").lower() == "8d" else "normal"
    folder = "audio" if kind == "audio" else "covers"
    extension = path.suffix.lower() or (".mp3" if kind == "audio" else ".jpg")
    return f"{family}/{folder}/{uuid4().hex}{extension}"


def _existing_cloud_path(value: str | None) -> str | None:
    path = normalize_object_path(value or "")
    return path if path and exists(path) else None


def migrate() -> tuple[int, int]:
    settings.validate_startup()
    if not settings.uses_supabase:
        raise RuntimeError("Set STORAGE_BACKEND=supabase before running this migration")

    # Add the new metadata columns if this is an older database. This does not
    # drop, rewrite, or delete any existing rows.
    Base.metadata.create_all(bind=engine)
    migrate_song_columns()

    success = 0
    failures = 0
    with SessionLocal() as db:
        songs = db.scalars(select(Song).order_by(Song.id)).all()
        for song in songs:
            uploaded: list[str] = []
            try:
                audio_path = _existing_cloud_path(song.audio_object_path or song.audio_path)
                if not audio_path:
                    local_audio = _local_file(song.audio_path)
                    if not local_audio:
                        raise FileNotFoundError(f"audio not found: {song.audio_path}")
                    audio_path = _destination(song, "audio", local_audio)
                    upload_file(local_audio.read_bytes(), audio_path, _content_type(local_audio, "audio/mpeg"))
                    uploaded.append(audio_path)

                cover_path = _existing_cloud_path(song.cover_object_path or song.cover_path)
                if not cover_path:
                    local_cover = _local_file(song.cover_path)
                    if not local_cover:
                        raise FileNotFoundError(f"cover not found: {song.cover_path}")
                    cover_path = _destination(song, "cover", local_cover)
                    upload_file(local_cover.read_bytes(), cover_path, _content_type(local_cover, "image/jpeg"))
                    uploaded.append(cover_path)

                if not exists(audio_path) or not exists(cover_path):
                    raise RuntimeError("uploaded object verification failed")

                # Keep both canonical and legacy columns populated so older
                # local tooling can still inspect the migrated database.
                song.audio_object_path = audio_path
                song.cover_object_path = cover_path
                song.audio_path = audio_path
                song.cover_path = cover_path
                db.commit()
                logger.info(
                    "migrated song id=%s title=%r audio=%s cover=%s audio_url=%s cover_url=%s",
                    song.id,
                    song.title,
                    audio_path,
                    cover_path,
                    get_public_url(audio_path),
                    get_public_url(cover_path),
                )
                success += 1
            except Exception as exc:
                db.rollback()
                for path in uploaded:
                    delete_relative(path)
                failures += 1
                logger.error("failed song id=%s title=%r: %s", song.id, song.title, str(exc))

    logger.info("Migration complete: %s succeeded, %s failed.", success, failures)
    logger.info("Local media and the old database were not deleted. Verify playback before removing any backup.")
    return success, failures


if __name__ == "__main__":
    try:
        _, failed = migrate()
    except Exception as exc:
        logger.error("Migration stopped: %s", str(exc))
        raise SystemExit(1) from exc
    raise SystemExit(1 if failed else 0)
