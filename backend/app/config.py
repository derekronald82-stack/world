import os
from pathlib import Path
from urllib.parse import urlparse
from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        populate_by_name=True,
    )

    app_name: str = "Catws Music API"
    environment: str = Field(default="development", validation_alias=AliasChoices("ENVIRONMENT", "APP_ENV"))
    secret_key: str = Field(
        default="dev-only-change-me",
        validation_alias=AliasChoices("JWT_SECRET", "SECRET_KEY"),
    )
    access_token_minutes: int = 1440
    # SQLite remains a development-only default so the project can boot before
    # cloud credentials are entered. Production validation below rejects it.
    database_url: str = "sqlite:///./8d_music.db"

    # local = development only; cloudinary = production media storage.
    # s3/supabase are retained as compatibility adapters for existing installs.
    storage_backend: str = "local"
    media_root: str = "media"
    public_base_url: str = "http://127.0.0.1:8000"
    supabase_url: str = ""
    supabase_storage_bucket: str = "catws-media"
    # SUPABASE_SECRET_KEY is the production name. Keep the old alias so
    # existing Render environments can be rotated without a code change.
    supabase_service_role_key: str = Field(
        default="",
        validation_alias=AliasChoices("SUPABASE_SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY"),
    )
    s3_bucket: str = ""
    s3_region: str = "auto"
    s3_endpoint_url: str = ""
    s3_access_key_id: str = ""
    s3_secret_access_key: str = ""
    s3_public_base_url: str = ""

    cloudinary_cloud_name: str = ""
    cloudinary_api_key: str = ""
    cloudinary_api_secret: str = ""

    cors_origins: str = "*"
    admin_username: str = ""
    admin_password: str = ""
    admin_sync_password: bool = False
    max_audio_mb: int = 50
    max_image_mb: int = 8

    @property
    def media_path(self) -> Path:
        return Path(self.media_root)

    @property
    def cors_list(self) -> list[str]:
        items = [x.strip() for x in self.cors_origins.split(",") if x.strip()]
        return items or ["*"]

    @property
    def uses_s3(self) -> bool:
        return self.storage_backend.strip().lower() == "s3"

    @property
    def uses_supabase(self) -> bool:
        return self.storage_backend.strip().lower() == "supabase"

    @property
    def uses_cloudinary(self) -> bool:
        return self.storage_backend.strip().lower() == "cloudinary"

    @property
    def is_production(self) -> bool:
        # Render sets RENDER=true automatically. ENVIRONMENT=production also
        # makes this explicit for other deployment platforms and CI.
        return self.environment.strip().lower() in {"production", "prod"} or os.environ.get("RENDER", "").lower() == "true"

    def validate_startup(self) -> None:
        """Fail clearly before serving requests when production is misconfigured."""
        if not self.is_production:
            return

        missing: list[str] = []
        database_url = (self.database_url or "").strip()
        parsed_database = urlparse(database_url.replace("postgresql+psycopg", "postgresql", 1))
        database_host = (parsed_database.hostname or "").lower()
        is_postgres = parsed_database.scheme in {"postgresql", "postgresql+psycopg"} and bool(database_host)
        if not database_url or database_url.lower().startswith("sqlite") or database_url.startswith("YOUR_") or not is_postgres:
            missing.append("DATABASE_URL (PostgreSQL; SQLite is not allowed in production)")
        if not self.uses_cloudinary:
            missing.append("STORAGE_BACKEND=cloudinary")
        if not self.secret_key or self.secret_key.startswith(("dev-", "CHANGE_ME", "YOUR_", "GENERATE_")):
            missing.append("SECRET_KEY")
        if not self.cloudinary_cloud_name:
            missing.append("CLOUDINARY_CLOUD_NAME")
        if not self.cloudinary_api_key:
            missing.append("CLOUDINARY_API_KEY")
        if not self.cloudinary_api_secret or self.cloudinary_api_secret.startswith("YOUR_"):
            missing.append("CLOUDINARY_API_SECRET")
        if not self.admin_username:
            missing.append("ADMIN_USERNAME")
        if not self.admin_password or self.admin_password.startswith(("CHANGE_ME", "YOUR_")):
            missing.append("ADMIN_PASSWORD")
        if missing:
            raise RuntimeError(
                "Production configuration is incomplete. Set: " + ", ".join(missing)
            )


settings = Settings()
