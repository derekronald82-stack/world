"""Server-side Cloudinary adapter.

Cloudinary credentials are intentionally read only by FastAPI. Flutter sees
the resulting HTTPS URLs and never receives the API secret.
"""

from __future__ import annotations

from dataclasses import dataclass
from io import BytesIO
from uuid import uuid4

from ..config import settings


@dataclass(frozen=True)
class CloudinaryAsset:
    public_id: str
    secure_url: str
    resource_type: str


def _client():
    if not all((settings.cloudinary_cloud_name, settings.cloudinary_api_key, settings.cloudinary_api_secret)):
        raise RuntimeError("Cloudinary is not configured")
    try:
        import cloudinary
        import cloudinary.uploader  # noqa: F401
    except ImportError as exc:  # pragma: no cover - only reached in bad deploys
        raise RuntimeError("The cloudinary package is required") from exc
    cloudinary.config(
        cloud_name=settings.cloudinary_cloud_name,
        api_key=settings.cloudinary_api_key,
        api_secret=settings.cloudinary_api_secret,
        secure=True,
    )
    return cloudinary


def _upload(data: bytes, *, folder: str, content_type: str, resource_type: str) -> CloudinaryAsset:
    cloudinary = _client()
    format_by_type = {
        "audio/mpeg": "mp3",
        "audio/mp3": "mp3",
        "audio/wav": "wav",
        "audio/x-wav": "wav",
        "audio/flac": "flac",
        "audio/mp4": "m4a",
        "audio/aac": "aac",
        "audio/ogg": "ogg",
        "image/jpeg": "jpg",
        "image/png": "png",
        "image/webp": "webp",
    }
    options = {
        "resource_type": resource_type,
        "folder": folder.strip("/"),
        "public_id": uuid4().hex,
        "use_filename": False,
        "unique_filename": False,
        "overwrite": False,
    }
    if format_by_type.get(content_type):
        options["format"] = format_by_type[content_type]
    result = cloudinary.uploader.upload(
        BytesIO(data),
        **options,
    )
    secure_url = str(result.get("secure_url") or result["url"])
    if secure_url.startswith("http://"):
        secure_url = "https://" + secure_url[len("http://"):]
    if not secure_url.startswith("https://"):
        raise RuntimeError("Cloudinary did not return a secure HTTPS URL")
    return CloudinaryAsset(
        public_id=str(result["public_id"]),
        secure_url=secure_url,
        resource_type=resource_type,
    )


def upload_audio(data: bytes, *, folder: str, content_type: str = "audio/mpeg") -> CloudinaryAsset:
    # Cloudinary delivers audio through its video resource type. This is the
    # provider-supported resource type for MP3/WAV/etc.; it is not a local
    # Render file or a generic raw upload.
    return _upload(data, folder=folder, content_type=content_type, resource_type="video")


def upload_image(data: bytes, *, folder: str, content_type: str = "image/jpeg") -> CloudinaryAsset:
    return _upload(data, folder=folder, content_type=content_type, resource_type="image")


def replace_image(
    data: bytes,
    *,
    folder: str,
    old_public_id: str | None = None,
    content_type: str = "image/jpeg",
    delete_old: bool = False,
) -> CloudinaryAsset:
    """Upload a replacement first; optionally remove the old exact ID.

    Catalog routes leave ``delete_old`` false and remove the old ID only after
    their PostgreSQL commit succeeds.
    """
    asset = upload_image(data, folder=folder, content_type=content_type)
    if delete_old and old_public_id and old_public_id != asset.public_id:
        delete_asset(old_public_id, resource_type="image")
    return asset


def delete_asset(public_id: str | None, *, resource_type: str | None = None) -> None:
    """Delete exactly one public ID; never delete by folder or wildcard."""
    if not public_id:
        return
    cloudinary = _client()
    resource_types = [resource_type] if resource_type else ["video", "image", "raw"]
    last_error: Exception | None = None
    for kind in resource_types:
        try:
            result = cloudinary.uploader.destroy(
                public_id,
                resource_type=kind,
                invalidate=True,
            )
            outcome = result.get("result")
            if outcome == "ok":
                return
            if outcome == "not found" and resource_type is not None:
                return
        except Exception as exc:  # pragma: no cover - provider-specific errors
            last_error = exc
    if last_error:
        raise last_error


def public_url(public_id: str, *, kind: str = "audio") -> str:
    cloudinary = _client()
    from cloudinary.utils import cloudinary_url

    resource_type = "image" if kind == "image" else "video"
    url, _ = cloudinary_url(public_id, resource_type=resource_type, secure=True)
    return url
