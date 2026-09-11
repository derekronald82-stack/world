from datetime import datetime, timezone
from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text, UniqueConstraint, Float
from sqlalchemy.orm import Mapped, mapped_column, relationship
from .db import Base


def utcnow():
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    email: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(20), default="user", index=True)
    profile_picture_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)


class AppRelease(Base):
    __tablename__ = "app_releases"

    id: Mapped[int] = mapped_column(primary_key=True)
    platform: Mapped[str] = mapped_column(String(20), default="android", index=True)
    version_name: Mapped[str] = mapped_column(String(40))
    version_code: Mapped[int] = mapped_column(index=True)
    minimum_supported_version_code: Mapped[int] = mapped_column(default=1)
    force_update: Mapped[bool] = mapped_column(Boolean, default=False)
    title: Mapped[str] = mapped_column(String(120), default="New CATWS Songs Update")
    message: Mapped[str] = mapped_column(String(500), default="Performance improvements and bug fixes.")
    download_url: Mapped[str] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    released_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)


class Song(Base):
    __tablename__ = "songs"

    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(120), index=True)
    artist: Mapped[str] = mapped_column(String(120), default="Unknown Artist")
    album: Mapped[str | None] = mapped_column(String(120), nullable=True)
    category: Mapped[str] = mapped_column(String(60), default="Other", index=True)
    genre: Mapped[str | None] = mapped_column(String(60), nullable=True, index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    mood: Mapped[str | None] = mapped_column(String(60), nullable=True, index=True)
    # Canonical permanent-storage fields. audio_path/cover_path are retained
    # as compatibility columns for databases created before the migration.
    audio_object_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    cover_object_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    audio_path: Mapped[str] = mapped_column(Text)
    cover_path: Mapped[str] = mapped_column(Text)
    # Cloudinary URL/public ID pairs are the canonical production references.
    # The *_path columns remain for old local/Supabase databases.
    audio_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    audio_public_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    cover_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    cover_public_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    duration: Mapped[float | None] = mapped_column(Float, nullable=True)
    duration_seconds: Mapped[float | None] = mapped_column(Float, nullable=True)
    song_type: Mapped[str] = mapped_column(String(20), default="normal", index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    is_featured: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    is_published: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    created_by: Mapped[int] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
    release_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)

    owner: Mapped[User] = relationship()


class Conversion(Base):
    __tablename__ = "conversions"

    id: Mapped[int] = mapped_column(primary_key=True)
    song_id: Mapped[int] = mapped_column(ForeignKey("songs.id"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    output_path: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class Favorite(Base):
    __tablename__ = "favorites"
    __table_args__ = (UniqueConstraint("user_id", "song_id", name="uq_favorite_user_song"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    song_id: Mapped[int] = mapped_column(ForeignKey("songs.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class ListeningHistory(Base):
    __tablename__ = "listening_history"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    song_id: Mapped[int] = mapped_column(ForeignKey("songs.id"), index=True)
    played_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)


class Playlist(Base):
    __tablename__ = "playlists"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    name: Mapped[str] = mapped_column(String(80))
    description: Mapped[str] = mapped_column(String(240), default="")
    cover_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    cover_public_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)


class PlaylistSong(Base):
    __tablename__ = "playlist_songs"
    __table_args__ = (UniqueConstraint("playlist_id", "song_id", name="uq_playlist_song"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    playlist_id: Mapped[int] = mapped_column(ForeignKey("playlists.id"), index=True)
    song_id: Mapped[int] = mapped_column(ForeignKey("songs.id"), index=True)
    position: Mapped[int] = mapped_column(default=0)
    added_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class ScheduledRelease(Base):
    __tablename__ = "scheduled_releases"
    __table_args__ = (UniqueConstraint("song_id", name="uq_scheduled_song"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    song_id: Mapped[int] = mapped_column(ForeignKey("songs.id"), index=True)
    release_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)


class User8DCreation(Base):
    __tablename__ = "user_8d_creations"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    title: Mapped[str] = mapped_column(String(160))
    source_filename: Mapped[str] = mapped_column(String(255), default="audio")
    output_path: Mapped[str] = mapped_column(Text)
    output_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    output_public_id: Mapped[str | None] = mapped_column(Text, nullable=True)
    saved_to_catws: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)

    owner: Mapped[User] = relationship()


class User8DPlaylist(Base):
    __tablename__ = "user_8d_playlists"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    name: Mapped[str] = mapped_column(String(80))
    description: Mapped[str] = mapped_column(String(240), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class User8DPlaylistItem(Base):
    __tablename__ = "user_8d_playlist_items"
    __table_args__ = (UniqueConstraint("playlist_id", "creation_id", name="uq_8d_playlist_creation"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    playlist_id: Mapped[int] = mapped_column(ForeignKey("user_8d_playlists.id"), index=True)
    creation_id: Mapped[int] = mapped_column(ForeignKey("user_8d_creations.id"), index=True)
    added_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
