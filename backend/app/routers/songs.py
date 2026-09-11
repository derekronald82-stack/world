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
    if row:
        return _utc(row.release_at)
    song = db.get(Song, song_id)
    return _utc(song.release_at) if song else None


def is_released(song_id: int, db: Session) -> bool:
    release_at = release_for(song_id, db)
    return release_at is None or release_at <= datetime.now(timezone.utc)


def release_map(songs: list[Song], db: Session) -> dict[int, datetime | None]:
    """Load release metadata in one query for a catalog page.

    ``scheduled_releases`` predates ``songs.release_at`` in some installations,
    so the compatibility table remains authoritative when it has a row.
    """
    if not songs:
        return {}
    song_ids = [song.id for song in songs]
    releases: dict[int, datetime | None] = {
        song.id: _utc(song.release_at) for song in songs
    }
    rows = db.scalars(
        select(ScheduledRelease).where(ScheduledRelease.song_id.in_(song_ids))
    ).all()
    releases.update({row.song_id: _utc(row.release_at) for row in rows})
    return releases


def song_out(
    song: Song,
    db: Session,
    *,
    favorite: bool = False,
    release_at: datetime | None = None,
    release_loaded: bool = False,
) -> SongOut:
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
        cover_url=(
            get_public_url(song.cover_public_id, kind="image", size=400)
            if song.cover_public_id
            else song.cover_url or get_public_url(cover_path, kind="image", size=400)
        ),
        duration=song.duration_seconds or song.duration,
        duration_seconds=song.duration_seconds or song.duration,
        song_type=song.song_type or "normal",
        is_active=song.is_active,
        is_featured=song.is_featured,
        is_published=song.is_published,
        created_at=song.created_at,
        release_at=release_at if release_loaded else release_for(song.id, db),
        is_favorite=favorite,
    )


@router.get("", response_model=list[SongOut])
def list_songs(
    q: str | None = Query(default=None, max_length=80),
    category: str | None = Query(default=None, max_length=60),
    featured: bool | None = None,
    song_type: str | None = Query(default=None, pattern="^(normal|8d|eightd)$"),
    type_filter: str | None = Query(default=None, alias="type", pattern="^(normal|8d|eightd)$"),
    limit: int = Query(default=60, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
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
    stmt = select(Song).order_by(Song.created_at.desc(), Song.id.desc()).limit(limit).offset(offset)
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
    releases = release_map(songs, db)
    now = datetime.now(timezone.utc)
    return [
        song_out(song, db, release_at=release_at, release_loaded=True)
        for song in songs
        if (release_at := releases.get(song.id)) is None or release_at <= now
    ]


@router.get("/normal", response_model=list[SongOut])
def list_normal_songs(q: str | None = None, limit: int = Query(default=60, ge=1, le=100), offset: int = Query(default=0, ge=0), db: Session = Depends(get_db)):
    return list_songs(q=q, song_type="normal", limit=limit, offset=offset, db=db)


@router.get("/8d", response_model=list[SongOut])
def list_eightd_songs(q: str | None = None, limit: int = Query(default=60, ge=1, le=100), offset: int = Query(default=0, ge=0), db: Session = Depends(get_db)):
    return list_songs(q=q, song_type="8d", limit=limit, offset=offset, db=db)


@router.get("/featured", response_model=list[SongOut])
def list_featured_songs(limit: int = Query(default=60, ge=1, le=100), offset: int = Query(default=0, ge=0), db: Session = Depends(get_db)):
    return list_songs(featured=True, limit=limit, offset=offset, db=db)


@router.get("/latest", response_model=list[SongOut])
def list_latest_songs(limit: int = Query(default=60, ge=1, le=100), offset: int = Query(default=0, ge=0), db: Session = Depends(get_db)):
    return list_songs(limit=limit, offset=offset, db=db)


@router.get("/categories", response_model=list[str])
def list_categories(db: Session = Depends(get_db)):
    # Build categories from the same public visibility rules as the catalog.
    # In particular, a future scheduled song must not reveal its category.
    now = datetime.now(timezone.utc)
    rows = db.execute(
        select(Song.category, ScheduledRelease.release_at, Song.release_at)
        .outerjoin(ScheduledRelease, ScheduledRelease.song_id == Song.id)
        .where(Song.is_published.is_(True), Song.is_active.is_(True))
    ).all()
    return sorted({
        category
        for category, scheduled_at, song_release_at in rows
        for release_at in [scheduled_at or song_release_at]
        if category and (release_at is None or _utc(release_at) <= now)
    })


@router.get("/search", response_model=list[SongOut])
def search_songs(q: str = Query(..., min_length=1, max_length=80), limit: int = Query(default=20, ge=1, le=50), offset: int = Query(default=0, ge=0), db: Session = Depends(get_db)):
    return list_songs(q=q, limit=limit, offset=offset, db=db)


@search_router.get("/search", response_model=list[SongOut])
def search_songs_alias(q: str = Query(..., min_length=1, max_length=80), limit: int = Query(default=20, ge=1, le=50), offset: int = Query(default=0, ge=0), db: Session = Depends(get_db)):
    """Stable top-level search route used by both Flutter apps."""
    return list_songs(q=q, limit=limit, offset=offset, db=db)


@router.get("/{song_id}", response_model=SongOut)
def get_song(song_id: int, db: Session = Depends(get_db)):
    song = db.get(Song, song_id)
    if not song or not song.is_published or not song.is_active or not is_released(song_id, db):
        raise HTTPException(404, "Song not found")
    return song_out(song, db)
