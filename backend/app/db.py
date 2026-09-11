from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from .config import settings


class Base(DeclarativeBase):
    pass


connect_args = (
    {"check_same_thread": False}
    if settings.database_url.startswith("sqlite")
    else {"connect_timeout": 15}
)
engine = create_engine(
    settings.database_url,
    connect_args=connect_args,
    pool_pre_ping=True,
    pool_timeout=15,
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def migrate_song_columns() -> None:
    """Add v6 fields without dropping data from pre-v5 databases.

    Alembic is the deployment migration path. This idempotent compatibility
    bridge keeps existing user databases bootable while they are upgraded.
    It never drops tables, rows, or media references.
    """
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())
    additions_by_table = {
        "users": {
            "email": "VARCHAR(255)",
            "profile_picture_url": "TEXT",
            "updated_at": "TIMESTAMP",
        },
        "songs": {
            "album": "VARCHAR(120)",
            "mood": "VARCHAR(60)",
            "genre": "VARCHAR(60)",
            "description": "TEXT",
            "duration": "FLOAT",
            "duration_seconds": "FLOAT",
            "song_type": "VARCHAR(20) DEFAULT 'normal'",
            "is_active": "BOOLEAN DEFAULT TRUE",
            "is_published": "BOOLEAN DEFAULT TRUE",
            "audio_object_path": "TEXT",
            "cover_object_path": "TEXT",
            "audio_url": "TEXT",
            "audio_public_id": "TEXT",
            "cover_url": "TEXT",
            "cover_public_id": "TEXT",
            "release_at": "TIMESTAMP",
            "updated_at": "TIMESTAMP",
        },
        "playlists": {
            "cover_url": "TEXT",
            "cover_public_id": "TEXT",
            "updated_at": "TIMESTAMP",
        },
        "playlist_songs": {"position": "INTEGER DEFAULT 0"},
        "user_8d_creations": {
            "output_url": "TEXT",
            "output_public_id": "TEXT",
        },
    }
    with engine.begin() as connection:
        for table, additions in additions_by_table.items():
            if table not in tables:
                continue
            existing = {column["name"] for column in inspector.get_columns(table)}
            for name, definition in additions.items():
                if name not in existing:
                    connection.execute(text(f"ALTER TABLE {table} ADD COLUMN {name} {definition}"))
        if "songs" not in tables:
            return
        if "song_type" in additions_by_table["songs"]:
            connection.execute(text("UPDATE songs SET song_type = 'normal' WHERE song_type IS NULL"))
        if "is_published" in additions_by_table["songs"]:
            connection.execute(text("UPDATE songs SET is_published = TRUE WHERE is_published IS NULL"))
        if "is_active" in additions_by_table["songs"]:
            connection.execute(text("UPDATE songs SET is_active = TRUE WHERE is_active IS NULL"))
        if "audio_object_path" in additions_by_table["songs"]:
            connection.execute(text("UPDATE songs SET audio_object_path = audio_path WHERE audio_object_path IS NULL"))
        if "cover_object_path" in additions_by_table["songs"]:
            connection.execute(text("UPDATE songs SET cover_object_path = cover_path WHERE cover_object_path IS NULL"))
        if "duration_seconds" in additions_by_table["songs"]:
            connection.execute(text("UPDATE songs SET duration_seconds = duration WHERE duration_seconds IS NULL"))
        if "release_at" in additions_by_table["songs"]:
            connection.execute(text("UPDATE songs SET release_at = (SELECT release_at FROM scheduled_releases WHERE scheduled_releases.song_id = songs.id) WHERE release_at IS NULL AND EXISTS (SELECT 1 FROM scheduled_releases WHERE scheduled_releases.song_id = songs.id)"))
        if "updated_at" in additions_by_table["songs"]:
            connection.execute(text("UPDATE songs SET updated_at = CURRENT_TIMESTAMP WHERE updated_at IS NULL"))
        if "users" in tables and "updated_at" in additions_by_table["users"]:
            connection.execute(text("UPDATE users SET updated_at = CURRENT_TIMESTAMP WHERE updated_at IS NULL"))
        if "playlists" in tables and "updated_at" in additions_by_table["playlists"]:
            connection.execute(text("UPDATE playlists SET updated_at = CURRENT_TIMESTAMP WHERE updated_at IS NULL"))


def repair_storage_paths() -> None:
    """Persist object paths instead of legacy localhost or public URLs."""
    if not settings.uses_supabase:
        return
    from .models import Conversion, Song, User8DCreation
    from .services.storage import normalize_object_path

    with SessionLocal() as db:
        changed = 0
        for row in db.query(Song).all():
            legacy_audio = normalize_object_path(row.audio_path)
            legacy_cover = normalize_object_path(row.cover_path)
            object_audio = normalize_object_path(row.audio_object_path or legacy_audio)
            object_cover = normalize_object_path(row.cover_object_path or legacy_cover)
            if row.audio_path != legacy_audio:
                row.audio_path = legacy_audio
                changed += 1
            if row.cover_path != legacy_cover:
                row.cover_path = legacy_cover
                changed += 1
            if row.audio_object_path != object_audio:
                row.audio_object_path = object_audio
                changed += 1
            if row.cover_object_path != object_cover:
                row.cover_object_path = object_cover
                changed += 1
        for model, field_name in ((Conversion, "output_path"), (User8DCreation, "output_path")):
            for row in db.query(model).all():
                current = getattr(row, field_name)
                normalized = normalize_object_path(current)
                if normalized != current:
                    setattr(row, field_name, normalized)
                    changed += 1
        if changed:
            db.commit()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
