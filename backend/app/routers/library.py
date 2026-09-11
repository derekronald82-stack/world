from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session
from ..db import get_db
from ..deps import current_user
from ..models import Favorite, ListeningHistory, Playlist, PlaylistSong, Song, User, User8DCreation, User8DPlaylist, User8DPlaylistItem
from ..routers.songs import is_released, song_out
from ..schemas import MessageOut, PlaylistCreate, PlaylistDetail, PlaylistOut, PlaylistUpdate, SongOut, User8DCreationOut, User8DPlaylistCreate, User8DPlaylistDetail, User8DPlaylistOut
from ..services.storage import delete_relative, get_signed_url, save_upload_asset

router = APIRouter(prefix="/api/library", tags=["library"])
compat_router = APIRouter(tags=["library"])


def _owned_playlist(playlist_id: int, user: User, db: Session) -> Playlist:
    playlist = db.get(Playlist, playlist_id)
    if not playlist or playlist.user_id != user.id:
        raise HTTPException(404, "Playlist not found")
    return playlist


@router.get("/favorites", response_model=list[SongOut])
def favorites(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = db.execute(
        select(Song)
        .join(Favorite, Favorite.song_id == Song.id)
        .where(Favorite.user_id == user.id)
        .order_by(Favorite.created_at.desc())
    ).scalars().all()
    return [song_out(s, db, favorite=True) for s in rows if is_released(s.id, db)]


@router.post("/favorites/{song_id}", response_model=MessageOut)
def add_favorite(song_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    song = db.get(Song, song_id)
    if not song or not is_released(song_id, db):
        raise HTTPException(404, "Song not found")
    exists = db.scalar(select(Favorite).where(Favorite.user_id == user.id, Favorite.song_id == song_id))
    if not exists:
        db.add(Favorite(user_id=user.id, song_id=song_id))
        db.commit()
    return MessageOut()


@router.delete("/favorites/{song_id}", status_code=204)
def remove_favorite(song_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    db.execute(delete(Favorite).where(Favorite.user_id == user.id, Favorite.song_id == song_id))
    db.commit()


@router.post("/history/{song_id}", response_model=MessageOut)
def record_play(song_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    song = db.get(Song, song_id)
    if not song or not is_released(song_id, db):
        raise HTTPException(404, "Song not found")
    db.add(ListeningHistory(user_id=user.id, song_id=song_id))
    db.commit()
    return MessageOut()


@router.get("/history", response_model=list[SongOut])
def history(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = db.execute(
        select(ListeningHistory.song_id)
        .where(ListeningHistory.user_id == user.id)
        .order_by(ListeningHistory.played_at.desc())
        .limit(100)
    ).scalars().all()
    seen: set[int] = set()
    result = []
    for song_id in rows:
        if song_id in seen:
            continue
        seen.add(song_id)
        song = db.get(Song, song_id)
        if song and is_released(song.id, db):
            result.append(song_out(song, db))
        if len(result) >= 30:
            break
    return result


@router.delete("/history", status_code=204)
def clear_history(user: User = Depends(current_user), db: Session = Depends(get_db)):
    db.execute(delete(ListeningHistory).where(ListeningHistory.user_id == user.id))
    db.commit()


@router.get("/playlists", response_model=list[PlaylistOut])
def playlists(user: User = Depends(current_user), db: Session = Depends(get_db)):
    items = db.scalars(select(Playlist).where(Playlist.user_id == user.id).order_by(Playlist.created_at.desc())).all()
    out = []
    for p in items:
        count = db.scalar(select(func.count(PlaylistSong.id)).where(PlaylistSong.playlist_id == p.id)) or 0
        out.append(PlaylistOut(id=p.id, name=p.name, description=p.description, cover_url=p.cover_url, created_at=p.created_at, song_count=count))
    return out


@router.post("/playlists", response_model=PlaylistOut, status_code=201)
def create_playlist(payload: PlaylistCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    p = Playlist(user_id=user.id, name=payload.name.strip(), description=payload.description.strip())
    db.add(p)
    db.commit()
    db.refresh(p)
    return PlaylistOut(id=p.id, name=p.name, description=p.description, cover_url=p.cover_url, created_at=p.created_at, song_count=0)


@router.patch("/playlists/{playlist_id}", response_model=PlaylistOut)
async def update_playlist(
    playlist_id: int,
    name: str | None = Form(None, max_length=80),
    description: str | None = Form(None, max_length=240),
    cover: UploadFile | None = File(None),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    playlist = _owned_playlist(playlist_id, user, db)
    old_cover = playlist.cover_public_id
    new_cover = None
    try:
        if name is not None:
            cleaned = name.strip()
            if not cleaned:
                raise HTTPException(400, "Playlist name cannot be empty")
            playlist.name = cleaned
        if description is not None:
            playlist.description = description.strip()
        if cover is not None:
            asset = await save_upload_asset(cover, "image", folder_override="playlists/covers")
            new_cover = asset.public_id
            playlist.cover_url = asset.url
            playlist.cover_public_id = asset.public_id
        db.commit()
        db.refresh(playlist)
    except Exception:
        db.rollback()
        if new_cover:
            delete_relative(new_cover)
        raise
    if new_cover and old_cover and new_cover != old_cover:
        delete_relative(old_cover)
    count = db.scalar(select(func.count(PlaylistSong.id)).where(PlaylistSong.playlist_id == playlist.id)) or 0
    return PlaylistOut(id=playlist.id, name=playlist.name, description=playlist.description, cover_url=playlist.cover_url, created_at=playlist.created_at, song_count=count)


@router.get("/playlists/{playlist_id}", response_model=PlaylistDetail)
def playlist_detail(playlist_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    p = _owned_playlist(playlist_id, user, db)
    songs = db.execute(
        select(Song)
        .join(PlaylistSong, PlaylistSong.song_id == Song.id)
        .where(PlaylistSong.playlist_id == p.id)
        # position is the user's playlist order; added_at.desc() made the
        # queue play newest additions first and ignored the intended sequence.
        .order_by(PlaylistSong.position.asc(), PlaylistSong.added_at.asc())
    ).scalars().all()
    available = [song_out(s, db) for s in songs if is_released(s.id, db)]
    return PlaylistDetail(id=p.id, name=p.name, description=p.description, cover_url=p.cover_url, created_at=p.created_at, song_count=len(available), songs=available)


@router.post("/playlists/{playlist_id}/songs/{song_id}", response_model=MessageOut)
def add_to_playlist(playlist_id: int, song_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    p = _owned_playlist(playlist_id, user, db)
    song = db.get(Song, song_id)
    if not song or not is_released(song_id, db):
        raise HTTPException(404, "Song not found")
    exists = db.scalar(select(PlaylistSong).where(PlaylistSong.playlist_id == p.id, PlaylistSong.song_id == song_id))
    if not exists:
        last_position = db.scalar(select(func.max(PlaylistSong.position)).where(PlaylistSong.playlist_id == p.id))
        db.add(PlaylistSong(playlist_id=p.id, song_id=song_id, position=(last_position or -1) + 1))
        db.commit()
    return MessageOut()


@router.delete("/playlists/{playlist_id}/songs/{song_id}", status_code=204)
def remove_from_playlist(playlist_id: int, song_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    p = _owned_playlist(playlist_id, user, db)
    db.execute(delete(PlaylistSong).where(PlaylistSong.playlist_id == p.id, PlaylistSong.song_id == song_id))
    db.commit()


@router.delete("/playlists/{playlist_id}", status_code=204)
def delete_playlist(playlist_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    p = _owned_playlist(playlist_id, user, db)
    cover_public_id = p.cover_public_id
    db.execute(delete(PlaylistSong).where(PlaylistSong.playlist_id == p.id))
    db.delete(p)
    db.commit()
    if cover_public_id:
        delete_relative(cover_public_id)


# ---------------- Separate 8D playlists ----------------
# Normal catalog playlists continue to use /api/library/playlists.
# User-created 8D tracks use this separate playlist collection so the two
# libraries can never be mixed accidentally.

def _owned_8d_playlist(playlist_id: int, user: User, db: Session) -> User8DPlaylist:
    playlist = db.get(User8DPlaylist, playlist_id)
    if not playlist or playlist.user_id != user.id:
        raise HTTPException(404, "8D playlist not found")
    return playlist


def _8d_creation_out(row: User8DCreation) -> User8DCreationOut:
    return User8DCreationOut(
        id=row.id,
        title=row.title,
        source_filename=row.source_filename,
        output_url=get_signed_url(row.output_path),
        saved_to_catws=row.saved_to_catws,
        created_at=row.created_at,
    )


@router.get("/8d-playlists", response_model=list[User8DPlaylistOut])
def eightd_playlists(user: User = Depends(current_user), db: Session = Depends(get_db)):
    items = db.scalars(
        select(User8DPlaylist)
        .where(User8DPlaylist.user_id == user.id)
        .order_by(User8DPlaylist.created_at.desc())
    ).all()
    out = []
    for p in items:
        count = db.scalar(
            select(func.count(User8DPlaylistItem.id)).where(User8DPlaylistItem.playlist_id == p.id)
        ) or 0
        out.append(User8DPlaylistOut(
            id=p.id, name=p.name, description=p.description, created_at=p.created_at, song_count=count
        ))
    return out


@router.post("/8d-playlists", response_model=User8DPlaylistOut, status_code=201)
def create_eightd_playlist(
    payload: User8DPlaylistCreate,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    p = User8DPlaylist(user_id=user.id, name=payload.name.strip(), description=payload.description.strip())
    db.add(p)
    db.commit()
    db.refresh(p)
    return User8DPlaylistOut(
        id=p.id, name=p.name, description=p.description, created_at=p.created_at, song_count=0
    )


@router.get("/8d-playlists/{playlist_id}", response_model=User8DPlaylistDetail)
def eightd_playlist_detail(
    playlist_id: int,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    p = _owned_8d_playlist(playlist_id, user, db)
    creations = db.execute(
        select(User8DCreation)
        .join(User8DPlaylistItem, User8DPlaylistItem.creation_id == User8DCreation.id)
        .where(
            User8DPlaylistItem.playlist_id == p.id,
            User8DCreation.user_id == user.id,
            User8DCreation.saved_to_catws.is_(True),
        )
        .order_by(User8DPlaylistItem.added_at.asc())
    ).scalars().all()
    songs = [_8d_creation_out(row) for row in creations]
    return User8DPlaylistDetail(
        id=p.id, name=p.name, description=p.description, created_at=p.created_at,
        song_count=len(songs), songs=songs
    )


@router.post("/8d-playlists/{playlist_id}/songs/{creation_id}", response_model=MessageOut)
def add_to_eightd_playlist(
    playlist_id: int,
    creation_id: int,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    p = _owned_8d_playlist(playlist_id, user, db)
    creation = db.get(User8DCreation, creation_id)
    if not creation or creation.user_id != user.id or not creation.saved_to_catws:
        raise HTTPException(404, "Saved 8D song not found")
    exists = db.scalar(
        select(User8DPlaylistItem).where(
            User8DPlaylistItem.playlist_id == p.id,
            User8DPlaylistItem.creation_id == creation_id,
        )
    )
    if not exists:
        db.add(User8DPlaylistItem(playlist_id=p.id, creation_id=creation_id))
        db.commit()
    return MessageOut()


@router.delete("/8d-playlists/{playlist_id}/songs/{creation_id}", status_code=204)
def remove_from_eightd_playlist(
    playlist_id: int,
    creation_id: int,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    p = _owned_8d_playlist(playlist_id, user, db)
    db.execute(
        delete(User8DPlaylistItem).where(
            User8DPlaylistItem.playlist_id == p.id,
            User8DPlaylistItem.creation_id == creation_id,
        )
    )
    db.commit()


@router.delete("/8d-playlists/{playlist_id}", status_code=204)
def delete_eightd_playlist(
    playlist_id: int,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    p = _owned_8d_playlist(playlist_id, user, db)
    db.execute(delete(User8DPlaylistItem).where(User8DPlaylistItem.playlist_id == p.id))
    db.delete(p)
    db.commit()


# Short, version-stable aliases used by the mobile clients. The older
# /api/library/* routes remain supported for existing installations.
@compat_router.get("/api/me/likes", response_model=list[SongOut])
def me_likes(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return favorites(user, db)


@compat_router.post("/api/me/likes/{song_id}", response_model=MessageOut)
@compat_router.post("/api/songs/{song_id}/like", response_model=MessageOut)
def like_song_alias(song_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return add_favorite(song_id, user, db)


@compat_router.delete("/api/me/likes/{song_id}", status_code=204)
@compat_router.delete("/api/songs/{song_id}/like", status_code=204)
def unlike_song_alias(song_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    remove_favorite(song_id, user, db)


@compat_router.get("/api/me/history", response_model=list[SongOut])
def me_history(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return history(user, db)


@compat_router.post("/api/history/{song_id}", response_model=MessageOut)
def record_history_alias(song_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return record_play(song_id, user, db)


@compat_router.get("/api/playlists", response_model=list[PlaylistOut])
def playlists_alias(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return playlists(user, db)


@compat_router.post("/api/playlists", response_model=PlaylistOut, status_code=201)
def create_playlist_alias(payload: PlaylistCreate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return create_playlist(payload, user, db)


@compat_router.get("/api/playlists/{playlist_id}", response_model=PlaylistDetail)
def playlist_detail_alias(playlist_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return playlist_detail(playlist_id, user, db)


@compat_router.patch("/api/playlists/{playlist_id}", response_model=PlaylistOut)
def rename_playlist_alias(playlist_id: int, payload: PlaylistUpdate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    playlist = _owned_playlist(playlist_id, user, db)
    if payload.name is not None:
        playlist.name = payload.name.strip()
    if payload.description is not None:
        playlist.description = payload.description.strip()
    if not playlist.name:
        raise HTTPException(400, "Playlist name cannot be empty")
    db.commit()
    count = db.scalar(select(func.count(PlaylistSong.id)).where(PlaylistSong.playlist_id == playlist.id)) or 0
    return PlaylistOut(id=playlist.id, name=playlist.name, description=playlist.description, cover_url=playlist.cover_url, created_at=playlist.created_at, song_count=count)


@compat_router.delete("/api/playlists/{playlist_id}", status_code=204)
def delete_playlist_alias(playlist_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    delete_playlist(playlist_id, user, db)


@compat_router.post("/api/playlists/{playlist_id}/songs/{song_id}", response_model=MessageOut)
def add_playlist_song_alias(playlist_id: int, song_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    return add_to_playlist(playlist_id, song_id, user, db)


@compat_router.delete("/api/playlists/{playlist_id}/songs/{song_id}", status_code=204)
def remove_playlist_song_alias(playlist_id: int, song_id: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    remove_from_playlist(playlist_id, song_id, user, db)
