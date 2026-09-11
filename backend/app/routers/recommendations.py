from fastapi import APIRouter, Depends, Query
from sqlalchemy import desc, select
from sqlalchemy.orm import Session

from ..db import get_db
from ..deps import current_user
from ..models import Favorite, ListeningHistory, Song, User
from ..schemas import SongOut
from ..services.recommendations import rank_recommendations
from .songs import is_released, song_out

router = APIRouter(prefix="/api/recommendations", tags=["recommendations"])


def _metadata(song: Song) -> dict:
    return {
        "id": song.id,
        "title": song.title,
        "artist": song.artist,
        "album": song.album or "",
        "category": song.category,
        "genre": song.genre or "",
        "mood": song.mood or "",
        "is_featured": song.is_featured,
    }


@router.get("", response_model=list[SongOut])
async def recommendations(
    seed_id: int | None = Query(default=None),
    limit: int = Query(default=12, ge=1, le=30),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    seed = db.get(Song, seed_id) if seed_id is not None else None
    history_ids = db.scalars(
        select(ListeningHistory.song_id)
        .where(ListeningHistory.user_id == user.id)
        .order_by(desc(ListeningHistory.played_at))
        .limit(20)
    ).all()
    favorite_ids = db.scalars(
        select(Favorite.song_id)
        .where(Favorite.user_id == user.id)
        .limit(20)
    ).all()
    profile_ids = list(dict.fromkeys(([seed.id] if seed else []) + history_ids + favorite_ids))
    profile_songs = [db.get(Song, song_id) for song_id in profile_ids]
    profile = [_metadata(song) for song in profile_songs if song is not None]

    song_type = seed.song_type if seed and seed.song_type else "normal"
    rows = db.scalars(
        select(Song)
        .where(
            Song.song_type == song_type,
            Song.is_published.is_(True),
            Song.is_active.is_(True),
        )
        .order_by(desc(Song.is_featured), desc(Song.created_at))
        .limit(120)
    ).all()
    excluded = {seed_id} if seed_id is not None else set()
    candidates = [
        song for song in rows
        if song.id not in excluded and is_released(song.id, db)
    ]
    ranked_ids = await rank_recommendations(
        [_metadata(song) for song in candidates],
        profile,
        limit,
    )
    by_id = {song.id: song for song in candidates}
    return [song_out(by_id[song_id], db) for song_id in ranked_ids if song_id in by_id]
