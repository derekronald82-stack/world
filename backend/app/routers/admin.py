from datetime import datetime, timezone
import json
import re
from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session
from ..db import get_db
from ..deps import admin_user
from ..models import Conversion, Favorite, ListeningHistory, Playlist, PlaylistSong, ScheduledRelease, Song, User
from ..routers.songs import song_out
from ..schemas import AdminStatsOut, SongOut
from ..services.storage import delete_relative, save_upload_asset

router = APIRouter(prefix="/api/admin", tags=["admin"])


def _bulk_stem(filename: str | None) -> str:
    """Normalize a filename for deterministic audio/cover pairing."""
    stem = (filename or "").rsplit("/", 1)[-1].rsplit("\\", 1)[-1]
    stem = stem.rsplit(".", 1)[0]
    return re.sub(r"[^a-z0-9]+", "", stem.lower())


def _parse_release(value: str | None) -> datetime | None:
    if not value or not value.strip():
        return None
    try:
        dt = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        raise HTTPException(400, "release_at must be an ISO date/time")
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _set_release(db: Session, song_id: int, action: str, release_at: str | None) -> None:
    action = (action or "keep").strip().lower()
    if action not in {"keep", "set", "clear"}:
        raise HTTPException(400, "release_action must be keep, set or clear")
    existing = db.scalar(select(ScheduledRelease).where(ScheduledRelease.song_id == song_id))
    song = db.get(Song, song_id)
    if action == "keep":
        return
    if action == "clear":
        if existing:
            db.delete(existing)
        if song:
            song.release_at = None
        return
    parsed = _parse_release(release_at)
    if parsed is None:
        raise HTTPException(400, "release_at is required when release_action=set")
    if existing:
        existing.release_at = parsed
    else:
        db.add(ScheduledRelease(song_id=song_id, release_at=parsed))
    if song:
        song.release_at = parsed


@router.post("/songs", response_model=SongOut, status_code=201)
@router.post("/songs/normal", response_model=SongOut, status_code=201)
@router.post("/songs/8d", response_model=SongOut, status_code=201)
async def add_song(
    request: Request,
    title: str = Form(..., min_length=1, max_length=120),
    artist: str = Form("Unknown Artist", max_length=120),
    album: str | None = Form(None, max_length=120),
    category: str = Form("Other", max_length=60),
    genre: str | None = Form(None, max_length=60),
    description: str | None = Form(None, max_length=500),
    mood: str | None = Form(None, max_length=60),
    is_featured: bool = Form(False),
    is_published: bool = Form(True),
    song_type: str | None = Form(None),
    release_at: str | None = Form(None),
    audio: UploadFile = File(...),
    cover: UploadFile = File(...),
    admin: User = Depends(admin_user),
    db: Session = Depends(get_db),
):
    song_type = song_type or ("8d" if request.url.path.endswith("/8d") else "normal")
    if song_type not in {"normal", "8d"}:
        raise HTTPException(400, "song_type must be normal or 8d")
    audio_asset = None
    cover_asset = None
    try:
        audio_asset = await save_upload_asset(audio, "audio", song_type)
        cover_asset = await save_upload_asset(cover, "image", song_type)
        song = Song(
            title=title.strip(),
            artist=artist.strip() or "Unknown Artist",
            album=album.strip() if album and album.strip() else None,
            category=category.strip() or "Other",
            genre=genre.strip() if genre and genre.strip() else None,
            description=description.strip() if description and description.strip() else None,
            mood=mood.strip() if mood and mood.strip() else None,
            audio_object_path=audio_asset.object_path,
            cover_object_path=cover_asset.object_path,
            audio_path=audio_asset.object_path,
            cover_path=cover_asset.object_path,
            audio_url=audio_asset.url,
            audio_public_id=audio_asset.public_id,
            cover_url=cover_asset.url,
            cover_public_id=cover_asset.public_id,
            song_type=song_type,
            is_featured=is_featured,
            is_published=is_published,
            created_by=admin.id,
        )
        db.add(song)
        db.flush()
        release = _parse_release(release_at)
        if release is not None:
            db.add(ScheduledRelease(song_id=song.id, release_at=release))
            song.release_at = release
        db.commit()
        db.refresh(song)
        return song_out(song, db)
    except Exception:
        db.rollback()
        if audio_asset:
            delete_relative(audio_asset.public_id)
        if cover_asset:
            delete_relative(cover_asset.public_id)
        raise


@router.post("/songs/bulk", response_model=list[SongOut], status_code=201)
async def add_songs_bulk(
    manifest: str = Form(...),
    artist: str = Form("Unknown Artist", max_length=120),
    category: str = Form("Other", max_length=60),
    genre: str | None = Form(None, max_length=60),
    song_type: str = Form("normal"),
    is_featured: bool = Form(False),
    is_published: bool = Form(True),
    audio: list[UploadFile] = File(...),
    cover: list[UploadFile] = File(...),
    admin: User = Depends(admin_user),
    db: Session = Depends(get_db),
):
    """Create up to ten catalog songs in one admin operation.

    The client sends a manifest containing the selected filenames. Covers are
    paired by normalized filename stem, with positional pairing as a safe
    fallback for file pickers that rename files during selection. All assets
    are uploaded before the database transaction is committed; a failure
    rolls back the transaction and removes every asset created by this batch.
    """
    if song_type not in {"normal", "8d"}:
        raise HTTPException(400, "song_type must be normal or 8d")
    if not 1 <= len(audio) <= 10:
        raise HTTPException(400, "Select between 1 and 10 audio files")
    if len(cover) != len(audio):
        raise HTTPException(400, "Select exactly one cover image for each song")
    try:
        entries = json.loads(manifest)
    except (TypeError, ValueError) as exc:
        raise HTTPException(422, "Invalid bulk upload manifest") from exc
    if not isinstance(entries, list) or len(entries) != len(audio):
        raise HTTPException(422, "Bulk upload manifest does not match the files")

    covers_by_stem: dict[str, list[UploadFile]] = {}
    for item in cover:
        covers_by_stem.setdefault(_bulk_stem(item.filename), []).append(item)
    used_cover_ids: set[int] = set()
    uploaded_objects: list[str] = []
    songs: list[Song] = []
    try:
        for index, audio_file in enumerate(audio):
            item = entries[index]
            if not isinstance(item, dict):
                raise HTTPException(422, "Invalid bulk upload manifest entry")
            expected_cover_name = str(item.get("cover_name") or "")
            expected_stem = _bulk_stem(expected_cover_name)
            selected_cover = next(
                (candidate for candidate in covers_by_stem.get(expected_stem, [])
                 if id(candidate) not in used_cover_ids),
                None,
            )
            if selected_cover is None:
                selected_cover = next(
                    (candidate for candidate in cover if id(candidate) not in used_cover_ids),
                    None,
                )
            if selected_cover is None:
                raise HTTPException(400, "Each audio file needs one cover image")
            used_cover_ids.add(id(selected_cover))

            title = str(item.get("title") or "").strip()
            if not title:
                title = re.sub(r"[_-]+", " ", (audio_file.filename or "Song").rsplit(".", 1)[0]).strip()
            if not title:
                title = f"Song {index + 1}"
            audio_asset = await save_upload_asset(audio_file, "audio", song_type)
            uploaded_objects.append(audio_asset.public_id)
            cover_asset = await save_upload_asset(selected_cover, "image", song_type)
            uploaded_objects.append(cover_asset.public_id)
            songs.append(Song(
                title=title[:120],
                artist=artist.strip() or "Unknown Artist",
                category=category.strip() or "Other",
                genre=genre.strip() if genre and genre.strip() else None,
                audio_object_path=audio_asset.object_path,
                cover_object_path=cover_asset.object_path,
                audio_path=audio_asset.object_path,
                cover_path=cover_asset.object_path,
                audio_url=audio_asset.url,
                audio_public_id=audio_asset.public_id,
                cover_url=cover_asset.url,
                cover_public_id=cover_asset.public_id,
                song_type=song_type,
                is_featured=is_featured,
                is_published=is_published,
                created_by=admin.id,
            ))
        db.add_all(songs)
        db.commit()
        for song in songs:
            db.refresh(song)
        return [song_out(song, db) for song in songs]
    except Exception:
        db.rollback()
        for object_path in uploaded_objects:
            delete_relative(object_path)
        raise


@router.patch("/songs/{song_id}", response_model=SongOut)
async def update_song(
    song_id: int,
    title: str | None = Form(None, max_length=120),
    artist: str | None = Form(None, max_length=120),
    album: str | None = Form(None, max_length=120),
    category: str | None = Form(None, max_length=60),
    genre: str | None = Form(None, max_length=60),
    description: str | None = Form(None, max_length=500),
    mood: str | None = Form(None, max_length=60),
    is_featured: bool | None = Form(None),
    is_published: bool | None = Form(None),
    release_action: str = Form("keep"),
    release_at: str | None = Form(None),
    audio: UploadFile | None = File(None),
    cover: UploadFile | None = File(None),
    _: User = Depends(admin_user),
    db: Session = Depends(get_db),
):
    song = db.get(Song, song_id)
    if not song:
        raise HTTPException(404, "Song not found")

    new_audio = None
    new_cover = None
    old_audio = song.audio_public_id or song.audio_object_path or song.audio_path
    old_cover = song.cover_public_id or song.cover_object_path or song.cover_path
    try:
        if title is not None:
            cleaned = title.strip()
            if not cleaned:
                raise HTTPException(400, "Title cannot be empty")
            song.title = cleaned
        if artist is not None:
            song.artist = artist.strip() or "Unknown Artist"
        if category is not None:
            song.category = category.strip() or "Other"
        if genre is not None:
            song.genre = genre.strip() or None
        if description is not None:
            song.description = description.strip() or None
        if album is not None:
            song.album = album.strip() or None
        if mood is not None:
            song.mood = mood.strip() or None
        if is_featured is not None:
            song.is_featured = is_featured
        if is_published is not None:
            song.is_published = is_published

        if audio is not None:
            asset = await save_upload_asset(audio, "audio", song.song_type)
            new_audio = asset.public_id
            song.audio_object_path = asset.object_path
            song.audio_path = asset.object_path
            song.audio_url = asset.url
            song.audio_public_id = asset.public_id
        if cover is not None:
            asset = await save_upload_asset(cover, "image", song.song_type)
            new_cover = asset.public_id
            song.cover_object_path = asset.object_path
            song.cover_path = asset.object_path
            song.cover_url = asset.url
            song.cover_public_id = asset.public_id

        _set_release(db, song_id, release_action, release_at)
        db.commit()
        db.refresh(song)
    except Exception:
        db.rollback()
        if new_audio:
            delete_relative(new_audio)
        if new_cover:
            delete_relative(new_cover)
        raise

    # Only remove old files after the database commit succeeds.
    if new_audio and new_audio != old_audio:
        delete_relative(old_audio)
    if new_cover and new_cover != old_cover:
        delete_relative(old_cover)
    return song_out(song, db)


@router.get("/songs", response_model=list[SongOut])
def list_admin_songs(
    _: User = Depends(admin_user),
    db: Session = Depends(get_db),
):
    return [song_out(s, db) for s in db.scalars(select(Song).order_by(Song.created_at.desc())).all()]


@router.get("/songs/normal", response_model=list[SongOut])
def list_admin_normal_songs(_: User = Depends(admin_user), db: Session = Depends(get_db)):
    songs = db.scalars(select(Song).where(Song.song_type == "normal").order_by(Song.created_at.desc())).all()
    return [song_out(s, db) for s in songs]


@router.get("/songs/8d", response_model=list[SongOut])
def list_admin_eightd_songs(_: User = Depends(admin_user), db: Session = Depends(get_db)):
    songs = db.scalars(select(Song).where(Song.song_type == "8d").order_by(Song.created_at.desc())).all()
    return [song_out(s, db) for s in songs]


@router.get("/stats", response_model=AdminStatsOut)
def admin_stats(
    _: User = Depends(admin_user),
    db: Session = Depends(get_db),
):
    return AdminStatsOut(
        users=db.scalar(select(func.count(User.id))) or 0,
        songs=db.scalar(select(func.count(Song.id))) or 0,
        playlists=db.scalar(select(func.count(Playlist.id))) or 0,
        favorites=db.scalar(select(func.count(Favorite.id))) or 0,
        conversions=db.scalar(select(func.count(Conversion.id))) or 0,
    )


@router.delete("/songs/{song_id}", status_code=204)
def delete_song(
    song_id: int,
    _: User = Depends(admin_user),
    db: Session = Depends(get_db),
):
    song = db.get(Song, song_id)
    if not song:
        raise HTTPException(404, "Song not found")

    # Read all object paths before changing the database. Storage deletion is
    # intentionally performed only after the DB commit succeeds.
    conversions = db.scalars(select(Conversion).where(Conversion.song_id == song_id)).all()
    objects = {
        song.audio_public_id,
        song.cover_public_id,
        song.audio_object_path,
        song.audio_path,
        song.cover_object_path,
        song.cover_path,
        *(conversion.output_path for conversion in conversions),
    }
    db.execute(delete(Favorite).where(Favorite.song_id == song_id))
    db.execute(delete(ListeningHistory).where(ListeningHistory.song_id == song_id))
    db.execute(delete(PlaylistSong).where(PlaylistSong.song_id == song_id))
    db.execute(delete(ScheduledRelease).where(ScheduledRelease.song_id == song_id))
    db.execute(delete(Conversion).where(Conversion.song_id == song_id))
    db.delete(song)
    db.commit()

    # Delete only objects referenced by this song/conversion set. If a storage
    # provider is temporarily unavailable, the catalog row is still gone and
    # no unrelated object is touched.
    for object_path in objects:
        delete_relative(object_path)
