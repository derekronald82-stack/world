"""Add safe PostgreSQL indexes for catalog pagination and search."""

from alembic import op

revision = "20260911_v7"
down_revision = "20260909_v6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # SQLite/local development does not provide pg_trgm. Production is
    # PostgreSQL, and these statements are intentionally additive-only.
    bind = op.get_bind()
    if bind.dialect.name != "postgresql":
        return
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_songs_public_catalog "
        "ON songs (is_published, is_active, song_type, created_at DESC, id DESC)"
    )
    op.execute("CREATE INDEX IF NOT EXISTS ix_songs_title_trgm ON songs USING gin (lower(title) gin_trgm_ops)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_songs_artist_trgm ON songs USING gin (lower(artist) gin_trgm_ops)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_songs_album_trgm ON songs USING gin (lower(album) gin_trgm_ops)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_scheduled_releases_song_release ON scheduled_releases (song_id, release_at)")


def downgrade() -> None:
    # Keep production data safe; this migration is additive and can remain in
    # place if an older application is rolled back.
    pass
