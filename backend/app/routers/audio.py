from pathlib import Path
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import time
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse, RedirectResponse
from sqlalchemy import delete, select
from sqlalchemy.orm import Session
from ..config import settings
from ..db import get_db
from ..deps import current_user
from ..models import Conversion, Song, User, User8DCreation, User8DPlaylistItem
from ..routers.songs import is_released
from ..schemas import ConversionOut, ConvertIn, DownloadLinkOut, User8DCreationOut
from ..services.audio_processor import convert_to_8d
from ..services.storage import (
    delete_relative,
    get_signed_url,
    get_public_url,
    presigned_download_url,
    save_upload,
)

router = APIRouter(prefix="/api/audio", tags=["audio"])
DOWNLOAD_TTL_SECONDS = 15 * 60


def _creation_out(row: User8DCreation) -> User8DCreationOut:
    return User8DCreationOut(
        id=row.id,
        title=row.title,
        source_filename=row.source_filename,
        output_url=get_signed_url(row.output_path),
        saved_to_catws=row.saved_to_catws,
        created_at=row.created_at,
    )


def _safe_download_name(title: str) -> str:
    clean = "".join(c if c.isalnum() or c in " ._-" else "_" for c in title).strip()
    return f"{clean or 'Catws_8D'}_8D.mp3"


def _cleanup_unsaved(db: Session, user_id: int) -> None:
    """Remove temporary, unsaved 8D outputs older than 24 hours."""
    cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
    rows = db.scalars(
        select(User8DCreation).where(
            User8DCreation.user_id == user_id,
            User8DCreation.saved_to_catws.is_(False),
        )
    ).all()
    changed = False
    for row in rows:
        created = row.created_at
        if created.tzinfo is None:
            created = created.replace(tzinfo=timezone.utc)
        if created < cutoff:
            delete_relative(row.output_path)
            db.delete(row)
            changed = True
    if changed:
        db.commit()


def _make_download_token(creation_id: int, user_id: int, expires_at: int) -> str:
    message = f"{creation_id}:{user_id}:{expires_at}".encode()
    signature = hmac.new(settings.secret_key.encode(), message, hashlib.sha256).hexdigest()
    return f"{user_id}.{expires_at}.{signature}"


def _verify_download_token(creation_id: int, token: str) -> int:
    try:
        user_part, expiry_part, signature = token.split(".", 2)
        user_id = int(user_part)
        expires_at = int(expiry_part)
    except (ValueError, AttributeError):
        raise HTTPException(403, "Invalid download link")
    if expires_at < int(time.time()):
        raise HTTPException(403, "Download link expired")
    expected = _make_download_token(creation_id, user_id, expires_at).split(".", 2)[2]
    if not hmac.compare_digest(signature, expected):
        raise HTTPException(403, "Invalid download link")
    return user_id


@router.post("/convert/{song_id}", response_model=ConversionOut)
def convert_song(
    song_id: int,
    payload: ConvertIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    song = db.get(Song, song_id)
    if not song or not is_released(song_id, db):
        raise HTTPException(404, "Song not found")
    try:
        output = convert_to_8d(
            song.audio_object_path or song.audio_path,
            payload.pan_speed,
            payload.intensity,
            payload.reverb,
            output_prefix=f"users/{user.id}/eightd",
        )
    except FileNotFoundError:
        raise HTTPException(500, "Audio file missing on server")
    except Exception as exc:
        raise HTTPException(422, f"Audio conversion failed. Check FFmpeg and file validity. {type(exc).__name__}")
    record = Conversion(song_id=song.id, user_id=user.id, output_path=output)
    db.add(record)
    db.commit()
    db.refresh(record)
    return ConversionOut(id=record.id, output_url=get_signed_url(record.output_path))


@router.post("/create", response_model=User8DCreationOut, status_code=201)
async def create_personal_8d(
    title: str = Form(..., min_length=1, max_length=160),
    pan_speed: float = Form(0.5, ge=0.3, le=0.7),
    intensity: float = Form(1.0, ge=0.0, le=1.5),
    reverb: float = Form(0.35, ge=0.30, le=0.40),
    decay: float = Form(2.5, ge=2.0, le=3.0),
    audio: UploadFile = File(...),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    """Upload a user's own/permitted audio and create a private 8D version.

    The original upload is deleted after processing. Only the generated 8D
    file remains. It is private to the account until the user deletes it.
    """
    _cleanup_unsaved(db, user.id)
    input_path = None
    output_path = None
    try:
        input_path = await save_upload(audio, "audio")
        output_path = convert_to_8d(
            input_path,
            pan_speed,
            intensity,
            reverb,
            decay,
            output_prefix=f"users/{user.id}/eightd",
        )
        row = User8DCreation(
            user_id=user.id,
            title=title.strip(),
            source_filename=(audio.filename or "audio")[:255],
            output_path=output_path,
            output_url=get_public_url(output_path, kind="audio"),
            output_public_id=output_path if settings.uses_cloudinary else None,
            saved_to_catws=False,
        )
        db.add(row)
        db.commit()
        db.refresh(row)
        return _creation_out(row)
    except HTTPException:
        db.rollback()
        if output_path:
            delete_relative(output_path)
        raise
    except Exception as exc:
        db.rollback()
        if output_path:
            delete_relative(output_path)
        raise HTTPException(422, f"8D creation failed. Check the audio file and FFmpeg. {type(exc).__name__}")
    finally:
        # Do not retain the user's original source upload.
        if input_path:
            delete_relative(input_path)


@router.get("/creations", response_model=list[User8DCreationOut])
def my_8d_creations(
    saved_only: bool = Query(True),
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    _cleanup_unsaved(db, user.id)
    stmt = select(User8DCreation).where(User8DCreation.user_id == user.id)
    if saved_only:
        stmt = stmt.where(User8DCreation.saved_to_catws.is_(True))
    rows = db.scalars(stmt.order_by(User8DCreation.created_at.desc())).all()
    return [_creation_out(row) for row in rows]


@router.post("/creations/{creation_id}/save", response_model=User8DCreationOut)
def save_creation_to_catws(
    creation_id: int,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    row = db.get(User8DCreation, creation_id)
    if not row or row.user_id != user.id:
        raise HTTPException(404, "8D song not found")
    row.saved_to_catws = True
    db.commit()
    db.refresh(row)
    return _creation_out(row)


@router.delete("/creations/{creation_id}", status_code=204)
def delete_creation(
    creation_id: int,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    row = db.get(User8DCreation, creation_id)
    if not row or row.user_id != user.id:
        raise HTTPException(404, "8D song not found")
    delete_relative(row.output_path)
    db.execute(delete(User8DPlaylistItem).where(User8DPlaylistItem.creation_id == row.id))
    db.delete(row)
    db.commit()


@router.post("/creations/{creation_id}/download-link", response_model=DownloadLinkOut)
def creation_download_link(
    creation_id: int,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
):
    row = db.get(User8DCreation, creation_id)
    if not row or row.user_id != user.id:
        raise HTTPException(404, "8D song not found")
    expires_at = int(time.time()) + DOWNLOAD_TTL_SECONDS
    token = _make_download_token(row.id, user.id, expires_at)
    base = settings.public_base_url.rstrip("/")
    return DownloadLinkOut(
        url=f"{base}/api/audio/download/{row.id}?token={token}",
        expires_in=DOWNLOAD_TTL_SECONDS,
    )


@router.get("/download/{creation_id}", include_in_schema=False)
def download_creation(
    creation_id: int,
    token: str,
    db: Session = Depends(get_db),
):
    user_id = _verify_download_token(creation_id, token)
    row = db.get(User8DCreation, creation_id)
    if not row or row.user_id != user_id:
        raise HTTPException(404, "8D song not found")
    filename = _safe_download_name(row.title)
    if settings.uses_s3:
        return RedirectResponse(presigned_download_url(row.output_path, filename, DOWNLOAD_TTL_SECONDS), status_code=307)
    if settings.uses_supabase:
        return RedirectResponse(get_signed_url(row.output_path, DOWNLOAD_TTL_SECONDS), status_code=307)
    if settings.uses_cloudinary:
        return RedirectResponse(get_signed_url(row.output_path, DOWNLOAD_TTL_SECONDS), status_code=307)
    path = (settings.media_path / row.output_path).resolve()
    root = settings.media_path.resolve()
    if root not in path.parents or not path.exists():
        raise HTTPException(404, "Generated file not found")
    return FileResponse(path, media_type="audio/mpeg", filename=filename)
