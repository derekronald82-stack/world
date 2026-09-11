from datetime import datetime, timezone
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from ..db import get_db
from ..deps import admin_user
from ..models import AppRelease, User
from ..schemas import AppReleaseCreate, AppReleaseOut, AppReleaseUpdate, AppVersionOut

public_router = APIRouter(prefix="/api/app", tags=["app updates"])
admin_router = APIRouter(prefix="/api/admin", tags=["app updates"])


def _https_url(value: str) -> str:
    value = value.strip()
    parsed = urlparse(value)
    if parsed.scheme.lower() != "https" or not parsed.netloc:
        raise HTTPException(422, "download_url must use HTTPS")
    return value


def _deactivate_android_releases(db: Session, except_id: int | None = None) -> None:
    stmt = update(AppRelease).where(AppRelease.platform == "android")
    if except_id is not None:
        stmt = stmt.where(AppRelease.id != except_id)
    db.execute(stmt.values(is_active=False))


@public_router.get("/version", response_model=AppVersionOut)
def app_version(db: Session = Depends(get_db)):
    release = db.scalars(
        select(AppRelease)
        .where(AppRelease.platform == "android", AppRelease.is_active.is_(True))
        .order_by(AppRelease.version_code.desc(), AppRelease.id.desc())
    ).first()
    if release is None:
        return AppVersionOut(
            latest_version_name="0.0.0",
            latest_version_code=0,
            minimum_supported_version_code=0,
            force_update=False,
            title="CATWS Songs",
            message="No application update is currently published.",
            download_url="https://github.com/",
        )
    return AppVersionOut(
        latest_version_name=release.version_name,
        latest_version_code=release.version_code,
        minimum_supported_version_code=release.minimum_supported_version_code,
        force_update=release.force_update,
        title=release.title,
        message=release.message,
        download_url=release.download_url,
        released_at=release.released_at,
    )


@admin_router.get("/app-releases", response_model=list[AppReleaseOut])
def list_app_releases(_: User = Depends(admin_user), db: Session = Depends(get_db)):
    return db.scalars(
        select(AppRelease).where(AppRelease.platform == "android")
        .order_by(AppRelease.version_code.desc(), AppRelease.id.desc())
    ).all()


@admin_router.post("/app-releases", response_model=AppReleaseOut, status_code=201)
def create_app_release(payload: AppReleaseCreate, _: User = Depends(admin_user), db: Session = Depends(get_db)):
    if payload.minimum_supported_version_code > payload.version_code:
        raise HTTPException(422, "minimum_supported_version_code cannot exceed version_code")
    if payload.is_active:
        _deactivate_android_releases(db)
    release = AppRelease(
        **payload.model_dump(exclude={"released_at", "download_url"}),
        download_url=_https_url(payload.download_url),
        released_at=payload.released_at or datetime.now(timezone.utc),
    )
    db.add(release)
    db.commit()
    db.refresh(release)
    return release


@admin_router.patch("/app-releases/{release_id}", response_model=AppReleaseOut)
def update_app_release(release_id: int, payload: AppReleaseUpdate, _: User = Depends(admin_user), db: Session = Depends(get_db)):
    release = db.get(AppRelease, release_id)
    if not release or release.platform != "android":
        raise HTTPException(404, "App release not found")
    values = payload.model_dump(exclude_unset=True)
    if "download_url" in values:
        values["download_url"] = _https_url(values["download_url"])
    for key, value in values.items():
        setattr(release, key, value)
    if release.minimum_supported_version_code > release.version_code:
        raise HTTPException(422, "minimum_supported_version_code cannot exceed version_code")
    if release.is_active:
        _deactivate_android_releases(db, except_id=release.id)
    db.commit()
    db.refresh(release)
    return release


@admin_router.delete("/app-releases/{release_id}", status_code=204)
def delete_app_release(release_id: int, _: User = Depends(admin_user), db: Session = Depends(get_db)):
    release = db.get(AppRelease, release_id)
    if not release:
        raise HTTPException(404, "App release not found")
    db.delete(release)
    db.commit()
