from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from .config import settings
from .db import Base, engine, migrate_song_columns, repair_storage_paths
from .routers import admin, audio, auth, library, songs
from .seed import seed_admin
from .services.storage import ensure_media_dirs, ensure_supabase_bucket


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings.validate_startup()
    ensure_media_dirs()
    ensure_supabase_bucket()
    Base.metadata.create_all(bind=engine)
    migrate_song_columns()
    repair_storage_paths()
    seed_admin()
    yield


app = FastAPI(title=settings.app_name, version="5.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_list,
    allow_credentials=settings.cors_list != ["*"],
    allow_methods=["GET", "POST", "DELETE", "PATCH", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

ensure_media_dirs()
if not settings.uses_s3 and not settings.uses_supabase:
    app.mount("/media", StaticFiles(directory=settings.media_root), name="media")
app.include_router(auth.router)
app.include_router(songs.router)
app.include_router(songs.search_router)
app.include_router(library.router)
app.include_router(library.compat_router)
app.include_router(admin.router)
app.include_router(audio.router)


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
