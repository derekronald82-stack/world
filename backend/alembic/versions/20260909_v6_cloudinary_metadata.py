"""Add durable asset IDs, playlist covers, and user profile metadata."""
from alembic import op
from sqlalchemy import inspect

revision = "20260909_v6"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    # Create any missing tables without touching existing tables or rows. This
    # keeps partially initialized local/PostgreSQL databases migratable.
    from app.db import Base
    from app import models  # noqa: F401
    Base.metadata.create_all(bind=bind)
    inspector = inspect(bind)
    if not inspector.get_table_names():
        return

    additions = {
        "users": {"email": "VARCHAR(255)", "profile_picture_url": "TEXT", "updated_at": "TIMESTAMP"},
        "songs": {
            "album": "VARCHAR(120)", "mood": "VARCHAR(60)", "genre": "VARCHAR(60)", "description": "TEXT",
            "duration": "FLOAT", "duration_seconds": "FLOAT", "song_type": "VARCHAR(20) DEFAULT 'normal'",
            "is_active": "BOOLEAN DEFAULT TRUE", "is_featured": "BOOLEAN DEFAULT FALSE", "is_published": "BOOLEAN DEFAULT TRUE",
            "audio_object_path": "TEXT", "cover_object_path": "TEXT",
            "audio_url": "TEXT", "audio_public_id": "TEXT", "cover_url": "TEXT",
            "cover_public_id": "TEXT", "release_at": "TIMESTAMP", "updated_at": "TIMESTAMP",
        },
        "playlists": {"cover_url": "TEXT", "cover_public_id": "TEXT", "updated_at": "TIMESTAMP"},
        "playlist_songs": {"position": "INTEGER DEFAULT 0"},
        "user_8d_creations": {"output_url": "TEXT", "output_public_id": "TEXT"},
    }
    for table, columns in additions.items():
        if table not in inspector.get_table_names():
            continue
        existing = {column["name"] for column in inspector.get_columns(table)}
        for name, definition in columns.items():
            if name not in existing:
                op.execute(f"ALTER TABLE {table} ADD COLUMN {name} {definition}")


def downgrade() -> None:
    # Additive-only migration: a downgrade must not risk deleting user data.
    pass
