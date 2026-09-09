"""Safely migrate legacy local/Supabase media to Cloudinary.

Usage from backend/:
    python scripts/migrate_media_to_cloudinary.py --dry-run
    python scripts/migrate_media_to_cloudinary.py

Rows and original media are preserved until each Cloudinary upload is
verified. The script never deletes a source file or database row.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app.config import settings
from app.db import SessionLocal
from app.models import Song
from app.services.cloudinary_service import upload_audio, upload_image
from app.services.storage import materialize_for_processing


def migrate(*, dry_run: bool) -> int:
    if not settings.uses_cloudinary:
        raise RuntimeError("Set STORAGE_BACKEND=cloudinary before migrating")
    changed = 0
    with SessionLocal() as db:
        songs = db.query(Song).order_by(Song.id).all()
        for song in songs:
            if song.audio_public_id and song.cover_public_id:
                continue
            print(f"song {song.id}: {song.title}")
            if dry_run:
                continue
            audio_source = song.audio_object_path or song.audio_path
            cover_source = song.cover_object_path or song.cover_path
            with materialize_for_processing(audio_source) as audio_path:
                audio_asset = upload_audio(
                    audio_path.read_bytes(),
                    folder=f"catws/{song.song_type or 'normal'}/audio",
                )
            with materialize_for_processing(cover_source) as cover_path:
                cover_asset = upload_image(
                    cover_path.read_bytes(),
                    folder=f"catws/{song.song_type or 'normal'}/covers",
                )
            if not audio_asset.public_id or not cover_asset.public_id:
                raise RuntimeError(f"Cloudinary verification failed for song {song.id}")
            song.audio_public_id = audio_asset.public_id
            song.audio_url = audio_asset.secure_url
            song.cover_public_id = cover_asset.public_id
            song.cover_url = cover_asset.secure_url
            db.commit()
            changed += 1
    return changed


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    print(f"Migrated {migrate(dry_run=args.dry_run)} song(s).")
