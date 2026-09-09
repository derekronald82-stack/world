from datetime import datetime
from pydantic import BaseModel, Field


class RegisterIn(BaseModel):
    username: str = Field(min_length=3, max_length=40, pattern=r"^[A-Za-z0-9_.-]+$")
    email: str | None = Field(default=None, max_length=255)
    password: str = Field(min_length=8, max_length=128)


class LoginIn(BaseModel):
    username: str
    password: str


class UserOut(BaseModel):
    id: int
    username: str
    email: str | None = None
    role: str
    profile_picture_url: str | None = None

    model_config = {"from_attributes": True}


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


class SongOut(BaseModel):
    id: int
    title: str
    artist: str
    album: str | None = None
    category: str
    genre: str | None = None
    description: str | None = None
    mood: str | None = None
    audio_url: str
    cover_url: str
    duration: float | None = None
    duration_seconds: float | None = None
    song_type: str = "normal"
    is_active: bool = True
    is_featured: bool
    is_published: bool = True
    created_at: datetime
    release_at: datetime | None = None
    is_favorite: bool = False


class ConvertIn(BaseModel):
    pan_speed: float = Field(default=0.5, ge=0.3, le=0.7)
    intensity: float = Field(default=1.0, ge=0.0, le=1.5)
    reverb: float = Field(default=0.35, ge=0.30, le=0.40)


class ConversionOut(BaseModel):
    id: int
    output_url: str


class PlaylistCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    description: str = Field(default="", max_length=240)


class PlaylistUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=80)
    description: str | None = Field(default=None, max_length=240)


class PlaylistOut(BaseModel):
    id: int
    name: str
    description: str
    cover_url: str | None = None
    created_at: datetime
    song_count: int = 0


class PlaylistDetail(PlaylistOut):
    songs: list[SongOut] = []


class MessageOut(BaseModel):
    ok: bool = True


class AdminStatsOut(BaseModel):
    users: int
    songs: int
    playlists: int
    favorites: int
    conversions: int


class User8DCreationOut(BaseModel):
    id: int
    title: str
    source_filename: str
    output_url: str
    saved_to_catws: bool
    created_at: datetime


class DownloadLinkOut(BaseModel):
    url: str
    expires_in: int = 900


class User8DPlaylistCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    description: str = Field(default="", max_length=240)


class User8DPlaylistOut(BaseModel):
    id: int
    name: str
    description: str
    created_at: datetime
    song_count: int = 0


class User8DPlaylistDetail(User8DPlaylistOut):
    songs: list[User8DCreationOut] = []
