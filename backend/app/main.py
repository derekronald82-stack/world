from contextlib import asynccontextmanager
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from .config import settings
from .db import Base, engine, migrate_song_columns, repair_storage_paths
from .routers import admin, app_updates, audio, auth, library, recommendations, songs
from .seed import seed_admin
from .services.storage import ensure_media_dirs, ensure_supabase_bucket

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_: FastAPI):
    logger.info("Starting CATWS API startup checks")
    settings.validate_startup()
    ensure_media_dirs()
    ensure_supabase_bucket()
    # Production schema changes are applied by the release pipeline with
    # Alembic. Avoid a full metadata inspection/migration pass on every
    # Render cold start; local/test mode keeps the compatibility bootstrap.
    if settings.is_production:
        repair_storage_paths()
    else:
        Base.metadata.create_all(bind=engine)
        migrate_song_columns()
        repair_storage_paths()
    seed_admin()
    logger.info("CATWS API startup complete")
    yield


app = FastAPI(title=settings.app_name, version="5.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_list,
    allow_credentials=settings.cors_list != ["*"],
    allow_methods=["GET", "POST", "DELETE", "PATCH", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

def _mount_local_media(application: FastAPI) -> None:
    """Expose media only for the local filesystem backend.

    Cloudinary/S3/Supabase assets are served by their providers. Render's
    filesystem is ephemeral and must not be required for a cloud deployment.
    """
    if settings.storage_backend.strip().lower() != "local":
        return
    ensure_media_dirs()
    application.mount("/media", StaticFiles(directory=settings.media_root), name="media")


_mount_local_media(app)
app.include_router(auth.router)
app.include_router(songs.router)
app.include_router(songs.search_router)
app.include_router(library.router)
app.include_router(library.compat_router)
app.include_router(admin.router)
app.include_router(audio.router)
app.include_router(recommendations.router)
app.include_router(app_updates.public_router)
app.include_router(app_updates.admin_router)


@app.get("/")
def root():
    return {
        "app": settings.app_name,
        "status": "ok",
        "health": "/api/health",
        "docs": "/docs",
    }


@app.get("/api/health")
def health():
        return {
            "ok": True,
            "status": "ok",
            "app": settings.app_name,
            "version": "5.0.0",
            "storage": settings.storage_backend,
        }
