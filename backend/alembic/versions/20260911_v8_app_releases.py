"""Add persistent Android release metadata for the free update flow."""

from alembic import op
import sqlalchemy as sa

revision = "20260911_v8"
down_revision = "20260911_v7"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "app_releases",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("platform", sa.String(length=20), nullable=False, server_default="android"),
        sa.Column("version_name", sa.String(length=40), nullable=False),
        sa.Column("version_code", sa.Integer(), nullable=False),
        sa.Column("minimum_supported_version_code", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("force_update", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("title", sa.String(length=120), nullable=False, server_default="New CATWS Songs Update"),
        sa.Column("message", sa.String(length=500), nullable=False, server_default="Performance improvements and bug fixes."),
        sa.Column("download_url", sa.Text(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("released_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_app_releases_platform", "app_releases", ["platform"])
    op.create_index("ix_app_releases_version_code", "app_releases", ["version_code"])
    op.create_index("ix_app_releases_is_active", "app_releases", ["is_active"])
    op.create_index("ix_app_releases_platform_active_code", "app_releases", ["platform", "is_active", "version_code"])


def downgrade() -> None:
    op.drop_index("ix_app_releases_platform_active_code", table_name="app_releases")
    op.drop_index("ix_app_releases_is_active", table_name="app_releases")
    op.drop_index("ix_app_releases_version_code", table_name="app_releases")
    op.drop_index("ix_app_releases_platform", table_name="app_releases")
    op.drop_table("app_releases")
