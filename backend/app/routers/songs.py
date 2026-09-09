from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import or_, select
from sqlalchemy.orm import Session
from ..db import get_db
from ..models import ScheduledRelease, Song
from ..schemas import SongOut
from ..services.storage import get_public_url

router = APIRouter(prefix="/api/songs", tags=["songs"])
search_router = APIRouter(prefix="/api", tags=["songs"])


def _utc(dt: datetime | None) -> datetime | None:
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def release_for(song_id: int, db: Session) -> datetime | None:
    row = db.scalar(select(ScheduledRelease).where(ScheduledRelease.song_id == song_id))
    return _utc(row.release_at) if row else None


def is_released(song_id: int, db: Session) -> bool:
    release_at = release_for(song_id, db)
    return release_at is None or release_at <= datetime.now(timezone.utc)


def song_out(song: Song, db: Session, *, favorite: bool = False) -> SongOut:
    audio_path = song.audio_public_id or song.audio_object_path or song.audio_path
    cover_path = song.cover_public_id or song.cover_object_path or song.cover_path
    return SongOut(
        id=song.id,
        title=song.title,
        artist=song.artist,
        album=song.album,
        category=song.category,
        mood=song.mood,
        audio_url=song.audio_url or get_public_url(audio_path, kind="audio"),
        cover_url=song.cover_url or get_public_url(cover_path, kind="image"),
        duration=song.duration_seconds or song.duration,
        duration_seconds=song.duration_seconds or song.duration,
        song_type=song.song_type or "normal",
        is_active=song.is_active,
        is_featured=song.is_featured,
        is_published=song.is_published,
        created_at=song.created_at,
        release_at=release_for(song.id, db),
        is_favorite=favorite,
    )


@router.get("", response_model=list[SongOut])
def list_songs(
    q: str | None = Query(default=None, max_length=80),
    category: str | None = Query(default=None, max_length=60),
    featured: bool | None = None,
    song_type: str | None = Query(default=None, pattern="^(normal|8d|eightd)$"),
    type_filter: str | None = Query(default=None, alias="type", pattern="^(normal|8d|eightd)$"),
    db: Session = Depends(get_db),
):
    if not isinstance(q, str):
        q = None
    if not isinstance(category, str):
        category = None
    if not isinstance(song_type, str):
        song_type = None
    if not isinstance(type_filter, str):
        type_filter = None
    song_type = (song_type or type_filter)
    if song_type == "eightd":
        song_type = "8d"
    stmt = select(Song).order_by(Song.created_at.desc())
    if q:
        term = f"%{q.strip()}%"
        stmt = stmt.where(or_(
            Song.title.ilike(term),
            Song.artist.ilike(term),
            Song.album.ilike(term),
            Song.genre.ilike(term),
            Song.category.ilike(term),
        ))
    if category:
        stmt = stmt.where(Song.category == category)
    if featured is not None:
        stmt = stmt.where(Song.is_featured == featured)
    if song_type:
        stmt = stmt.where(Song.song_type == song_type)
    stmt = stmt.where(Song.is_published.is_(True), Song.is_active.is_(True))
    songs = db.scalars(stmt).all()
    return [song_out(s, db) for s in songs if is_released(s.id, db)]


@router.get("/normal", response_model=list[SongOut])
def list_normal_songs(q: str | None = None, db: Session = Depends(get_db)):
    return list_songs(q=q, song_type="normal", db=db)


@router.get("/8d", response_model=list[SongOut])
def list_eightd_songs(q: str | None = None, db: Session = Depends(get_db)):
    return list_songs(q=q, song_type="8d", db=db)


@router.get("/featured", response_model=list[SongOut])
def list_featured_songs(db: Session = Depends(get_db)):
    return list_songs(featured=True, db=db)


@router.get("/latest", response_model=list[SongOut])
def list_latest_songs(db: Session = Depends(get_db)):
    return list_songs(db=db)


@router.get("/categories", response_model=list[str])
def list_categories(db: Session = Depends(get_db)):
    # Build categories from the same public visibility rules as the catalog.
    # In particular, a future scheduled song must not reveal its category.
    rows = db.scalars(select(Song).where(Song.is_published.is_(True), Song.is_active.is_(True))).all()
    return sorted({song.category for song in rows if song.category and is_released(song.id, db)})


@router.get("/search", response_model=list[SongOut])
def search_songs(q: str = Query(..., min_length=1, max_length=80), db: Session = Depends(get_db)):
    return list_songs(q=q, db=db)


@search_router.get("/search", response_model=list[SongOut])
def search_songs_alias(q: str = Query(..., min_length=1, max_length=80), db: Session = Depends(get_db)):
    """Stable top-level search route used by both Flutter apps."""
    return list_songs(q=q, db=db)


@router.get("/{song_id}", response_model=SongOut)
def get_song(song_id: int, db: Session = Depends(get_db)):
    song = db.get(Song, song_id)
    if not song or not song.is_published or not song.is_active or not is_released(song_id, db):
        raise HTTPException(404, "Song not found")
    return song_out(song, db)
