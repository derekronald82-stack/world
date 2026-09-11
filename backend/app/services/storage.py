from contextlib import contextmanager
from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import uuid4
import re
import logging
from dataclasses import dataclass
from urllib.parse import unquote, urlparse
from fastapi import HTTPException, UploadFile
from ..config import settings

logger = logging.getLogger(__name__)

AUDIO_EXTS = {".mp3", ".wav", ".flac", ".m4a", ".aac", ".ogg"}
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
AUDIO_TYPES = {
    "audio/mpeg", "audio/mp3", "audio/wav", "audio/x-wav", "audio/wave",
    "audio/flac", "audio/x-flac", "audio/mp4", "audio/x-m4a",
    "audio/aac", "audio/ogg", "application/ogg",
    "application/octet-stream",
}
IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}


@dataclass(frozen=True)
class StorageAsset:
    """Provider-neutral media reference stored alongside catalog metadata."""

    object_path: str
    url: str
    public_id: str


def _supabase_object_url(relative: str) -> str:
    base = settings.supabase_url.rstrip("/")
    bucket = settings.supabase_storage_bucket.strip("/")
    return f"{base}/storage/v1/object/{bucket}/{relative.lstrip('/')}"


def _supabase_public_url(relative: str) -> str:
    base = settings.supabase_url.rstrip("/")
    bucket = settings.supabase_storage_bucket.strip("/")
    return f"{base}/storage/v1/object/public/{bucket}/{relative.lstrip('/')}"


def normalize_object_path(value: str | None) -> str:
    """Convert legacy local or public storage URLs back to an object path."""
    value = (value or "").strip()
    if not value:
        return value
    parsed = urlparse(value)
    path = unquote(parsed.path if parsed.scheme else value)
    marker = "/media/"
    if marker in path:
        return path.split(marker, 1)[1].lstrip("/")
    public_marker = "/storage/v1/object/public/"
    if public_marker in path:
        object_path = path.split(public_marker, 1)[1].lstrip("/")
        bucket_prefix = settings.supabase_storage_bucket.strip("/") + "/"
        if object_path.startswith(bucket_prefix):
            return object_path[len(bucket_prefix):]
    return value


def _supabase_headers() -> dict[str, str]:
    if (
        not settings.supabase_url
        or not settings.supabase_storage_bucket
        or not settings.supabase_service_role_key
        or settings.supabase_service_role_key.startswith("YOUR_")
    ):
        raise HTTPException(503, "Cloud storage is not configured")
    return {
        "Authorization": f"Bearer {settings.supabase_service_role_key}",
        "apikey": settings.supabase_service_role_key,
    }


def _supabase_error_message(status_code: int, body: str) -> str:
    lowered = body.lower()
    if status_code == 401:
        return "Storage authentication failed"
    if status_code == 403:
        return "Storage permission denied"
    if status_code == 404 or "bucket not found" in lowered or "nosuchbucket" in lowered:
        return "Storage bucket not found"
    if status_code == 409:
        return "Storage object conflict"
    if status_code == 413:
        return "Storage upload too large"
    if status_code == 400:
        return "Storage upload rejected"
    return "Storage service unavailable"


def _raise_supabase_error(response, operation: str, relative: str | None = None):
    body = response.text[:500].replace(settings.supabase_service_role_key, "[REDACTED]")
    endpoint_path = response.request.url.path
    logger.error(
        "Supabase Storage %s failed: status=%s bucket=%s endpoint=%s object=%s body=%s",
        operation,
        response.status_code,
        settings.supabase_storage_bucket,
        endpoint_path,
        relative or "-",
        body,
    )
    raise HTTPException(502, _supabase_error_message(response.status_code, body))


def ensure_supabase_bucket() -> None:
    if not settings.uses_supabase:
        return
    import httpx

    headers = _supabase_headers()
    base = settings.supabase_url.rstrip("/")
    bucket = settings.supabase_storage_bucket
    try:
        response = httpx.get(f"{base}/storage/v1/bucket/{bucket}", headers=headers, timeout=30)
        if response.is_success:
            return
        if response.status_code == 404 or "bucket not found" in response.text.lower() or "nosuchbucket" in response.text.lower():
            created = httpx.post(
                f"{base}/storage/v1/bucket",
                headers=headers | {"Content-Type": "application/json"},
                json={"id": bucket, "name": bucket, "public": True},
                timeout=30,
            )
            if created.is_success or created.status_code == 409:
                logger.info("Supabase Storage bucket verified: bucket=%s", bucket)
                return
            _raise_supabase_error(created, "bucket creation")
        _raise_supabase_error(response, "bucket check")
    except httpx.RequestError as exc:
        logger.error("Supabase Storage bucket check unavailable: bucket=%s error=%s", bucket, str(exc)[:200])
        raise RuntimeError("Supabase Storage is unavailable") from exc


def _s3():
    if not settings.uses_s3:
        return None
    try:
        import boto3
    except ImportError as exc:
        raise RuntimeError("boto3 is required when STORAGE_BACKEND=s3") from exc
    return boto3.client(
        "s3",
        region_name=settings.s3_region or None,
        endpoint_url=settings.s3_endpoint_url or None,
        aws_access_key_id=settings.s3_access_key_id or None,
        aws_secret_access_key=settings.s3_secret_access_key or None,
    )


def ensure_media_dirs():
    if settings.uses_s3 or settings.uses_supabase or settings.uses_cloudinary:
        return
    for sub in (
        "normal/audio",
        "normal/covers",
        "eightd/audio",
        "eightd/covers",
        "user-generated/eightd",
        # Legacy locations remain available so existing local libraries keep working.
        "audio",
        "covers",
        "outputs",
    ):
        (settings.media_path / sub).mkdir(parents=True, exist_ok=True)


def _safe_ext(filename: str) -> str:
    clean = re.sub(r"[^A-Za-z0-9._-]", "_", filename or "file")
    return Path(clean).suffix.lower()


def _safe_object_path(relative: str) -> str:
    normalized = normalize_object_path(relative).replace("\\", "/").lstrip("/")
    path = Path(normalized)
    if not normalized or path.is_absolute() or ".." in path.parts:
        raise ValueError("Invalid storage object path")
    return path.as_posix()


def _has_audio_signature(data: bytes, ext: str) -> bool:
    if ext == ".wav":
        return len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WAVE"
    if ext == ".flac":
        return data.startswith(b"fLaC")
    if ext == ".m4a":
        return len(data) >= 12 and data[4:8] == b"ftyp"
    if ext == ".mp3":
        return data.startswith(b"ID3") or (
            len(data) >= 2 and data[0] == 0xFF and (data[1] & 0xE0) == 0xE0
        )
    if ext in {".aac", ".ogg"}:
        return len(data) > 2
    return False


async def _validated_upload(upload: UploadFile, kind: str, song_type: str | None, folder_override: str | None = None) -> tuple[bytes, str, str]:
    if kind == "audio":
        allowed_exts, allowed_types, max_bytes, folder = AUDIO_EXTS, AUDIO_TYPES, settings.max_audio_mb * 1024 * 1024, "audio"
    else:
        allowed_exts, allowed_types, max_bytes, folder = IMAGE_EXTS, IMAGE_TYPES, settings.max_image_mb * 1024 * 1024, "covers"

    if song_type in {"normal", "8d", "eightd"}:
        normalized = "eightd" if song_type in {"8d", "eightd"} else "normal"
        folder = f"{normalized}/{'audio' if kind == 'audio' else 'covers'}"
    if folder_override:
        folder = folder_override.strip("/")

    ext = _safe_ext(upload.filename or "")
    if ext not in allowed_exts:
        raise HTTPException(400, "Unsupported audio format" if kind == "audio" else f"Unsupported {kind} file type")
    content_type = (upload.content_type or "").split(";", 1)[0].strip().lower()
    if kind == "audio" and content_type and content_type not in allowed_types:
        raise HTTPException(400, "Invalid audio file")

    data = await upload.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise HTTPException(413, "Audio file too large" if kind == "audio" else f"{kind.capitalize()} file is too large")
    if not data:
        raise HTTPException(400, "Invalid audio file" if kind == "audio" else "Empty upload")
    if kind == "audio" and not _has_audio_signature(data, ext):
        raise HTTPException(400, "Invalid audio file")
    if kind == "image":
        valid_magic = data.startswith(b"\xFF\xD8\xFF") or data.startswith(b"\x89PNG\r\n\x1a\n") or (data.startswith(b"RIFF") and b"WEBP" in data[:16])
        if not valid_magic:
            raise HTTPException(400, "Invalid image data")
    return data, (Path(folder) / f"{uuid4().hex}{ext}").as_posix(), content_type or "application/octet-stream"


def upload_asset(data: bytes, object_path: str, content_type: str, *, kind: str) -> StorageAsset:
    relative = _safe_object_path(object_path)
    if settings.uses_cloudinary:
        from .cloudinary_service import upload_audio, upload_image

        folder = f"catws/{Path(relative).parent.as_posix()}"
        asset = (upload_audio if kind == "audio" else upload_image)(data, folder=folder, content_type=content_type)
        return StorageAsset(asset.public_id, asset.secure_url, asset.public_id)
    stored = upload_file(data, relative, content_type)
    return StorageAsset(stored, get_public_url(stored, kind=kind), stored)


async def save_upload_asset(upload: UploadFile, kind: str, song_type: str | None = None, folder_override: str | None = None) -> StorageAsset:
    data, relative, content_type = await _validated_upload(upload, kind, song_type, folder_override)
    return upload_asset(data, relative, content_type, kind=kind)


async def save_upload(upload: UploadFile, kind: str, song_type: str | None = None) -> str:
    return (await save_upload_asset(upload, kind, song_type)).object_path


def upload_file(data: bytes, object_path: str, content_type: str = "application/octet-stream") -> str:
    """Upload bytes to the configured durable storage backend.

    Routes use save_upload for validation and UUID naming; migrations and
    generated-file workflows use this lower-level method with an explicit
    already-safe object path.
    """
    relative = _safe_object_path(object_path)
    if settings.uses_cloudinary:
        from .cloudinary_service import upload_audio, upload_image

        kind = "image" if content_type.startswith("image/") else "audio"
        folder = f"catws/{Path(relative).parent.as_posix()}"
        asset = (upload_image if kind == "image" else upload_audio)(data, folder=folder, content_type=content_type)
        return asset.public_id
    if settings.uses_supabase:
        import httpx

        headers = _supabase_headers() | {
            "Content-Type": content_type,
            "x-upsert": "false",
        }
        try:
            response = httpx.post(
                _supabase_object_url(relative),
                content=data,
                headers=headers,
                timeout=120,
            )
        except httpx.RequestError as exc:
            logger.error(
                "Supabase Storage upload unavailable: bucket=%s object=%s error=%s",
                settings.supabase_storage_bucket,
                relative,
                str(exc)[:200],
            )
            raise HTTPException(502, "Storage service unavailable") from exc
        if response.is_error:
            _raise_supabase_error(response, "upload", relative)
    elif settings.uses_s3:
        _s3().put_object(
            Bucket=settings.s3_bucket,
            Key=relative,
            Body=data,
            ContentType=content_type,
        )
    else:
        target = settings.media_path / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    return relative


def delete_relative(relative: str | None):
    relative = normalize_object_path(relative)
    if not relative:
        return
    try:
        if settings.uses_cloudinary:
            from .cloudinary_service import delete_asset
            delete_asset(relative)
            return
        if settings.uses_supabase:
            import httpx
            response = httpx.post(
                f"{settings.supabase_url.rstrip('/')}/storage/v1/object/remove/{settings.supabase_storage_bucket}",
                json={"prefixes": [relative]},
                headers=_supabase_headers(),
                timeout=60,
            )
            response.raise_for_status()
            return
        if settings.uses_s3:
            _s3().delete_object(Bucket=settings.s3_bucket, Key=relative)
            return
        path = (settings.media_path / relative).resolve()
        root = settings.media_path.resolve()
        if root in path.parents and path.exists():
            path.unlink()
    except Exception:
        pass


def delete_file(object_path: str) -> None:
    """Public storage-service name used by migration and route workflows."""
    delete_relative(object_path)


def exists(relative: str) -> bool:
    """Return whether an object exists without exposing provider errors."""
    relative = normalize_object_path(relative)
    if not relative:
        return False
    try:
        if settings.uses_supabase:
            import httpx

            response = httpx.head(
                _supabase_object_url(relative),
                headers=_supabase_headers(),
                timeout=30,
            )
            if response.status_code == 405:
                # Some Storage deployments do not expose HEAD for objects.
                response = httpx.get(
                    _supabase_object_url(relative),
                    headers=_supabase_headers() | {"Range": "bytes=0-0"},
                    timeout=30,
                )
            return response.is_success
        if settings.uses_s3:
            _s3().head_object(Bucket=settings.s3_bucket, Key=relative)
            return True
        path = (settings.media_path / relative).resolve()
        root = settings.media_path.resolve()
        return root in path.parents and path.is_file()
    except Exception:
        return False


def get_public_url(relative: str, *, kind: str = "audio", size: int | None = None) -> str:
    relative = normalize_object_path(relative)
    if settings.uses_cloudinary:
        from .cloudinary_service import public_url
        return public_url(relative, kind=kind, size=size)
    if settings.uses_supabase:
        return _supabase_public_url(relative)
    if settings.uses_s3:
        base = settings.s3_public_base_url.rstrip("/")
        return f"{base}/{relative.lstrip('/')}"
    return f"{settings.public_base_url.rstrip('/')}/media/{relative.lstrip('/')}"


def public_url(relative: str) -> str:
    """Backward-compatible alias for existing route code."""
    return get_public_url(relative)


def get_signed_url(relative: str, expires_in: int = 3600) -> str:
    """Return a short-lived URL for owner-only generated media."""
    relative = normalize_object_path(relative)
    if settings.uses_cloudinary:
        # Catalog and private 8D assets are both owned by the API. Cloudinary
        # delivery URLs are durable; the DB controls whether they are exposed.
        from .cloudinary_service import public_url
        return public_url(relative, kind="audio")
    if settings.uses_supabase:
        import httpx

        try:
            response = httpx.post(
                f"{settings.supabase_url.rstrip('/')}/storage/v1/object/sign/{settings.supabase_storage_bucket}",
                json={"paths": [relative], "expiresIn": expires_in},
                headers=_supabase_headers() | {"Content-Type": "application/json"},
                timeout=30,
            )
        except httpx.RequestError as exc:
            raise HTTPException(502, "Storage service unavailable") from exc
        if response.is_error:
            _raise_supabase_error(response, "signed URL", relative)
        payload = response.json()
        signed = payload[0].get("signedURL") if isinstance(payload, list) else payload.get("signedURL")
        if not signed:
            raise HTTPException(502, "Storage service unavailable")
        if signed.startswith("http"):
            return signed
        return f"{settings.supabase_url.rstrip('/')}/storage/v1{signed}"
    if settings.uses_s3:
        return _s3().generate_presigned_url(
            "get_object",
            Params={"Bucket": settings.s3_bucket, "Key": relative},
            ExpiresIn=expires_in,
        )
    return get_public_url(relative)


@contextmanager
def materialize_for_processing(relative: str):
    if settings.uses_cloudinary:
        with TemporaryDirectory(prefix="catws-download-") as temp_dir:
            path = Path(temp_dir) / ("source" + (Path(relative).suffix or ".mp3"))
            import httpx
            response = httpx.get(get_public_url(relative), timeout=120)
            response.raise_for_status()
            path.write_bytes(response.content)
            yield path
        return
    if settings.uses_supabase:
        with TemporaryDirectory(prefix="catws-download-") as temp_dir:
            path = Path(temp_dir) / ("source" + Path(relative).suffix)
            import httpx
            response = httpx.get(_supabase_object_url(relative), headers=_supabase_headers(), timeout=120)
            response.raise_for_status()
            path.write_bytes(response.content)
            yield path
        return
    if not settings.uses_s3:
        yield settings.media_path / relative
        return
    suffix = Path(relative).suffix
    with TemporaryDirectory(prefix="catws-download-") as temp_dir:
        path = Path(temp_dir) / ("source" + suffix)
        _s3().download_file(settings.s3_bucket, relative, str(path))
        yield path


def store_generated_file(local_path: Path, relative: str, content_type: str = "audio/mpeg") -> str:
    return upload_file(local_path.read_bytes(), relative, content_type)


def presigned_download_url(relative: str, filename: str, expires_in: int = 900) -> str:
    """Create an attachment URL for an S3-compatible object.

    Used only after the API has verified that the requesting user owns the file.
    """
    if not settings.uses_s3:
        raise RuntimeError("Presigned URLs are only used with S3 storage")
    safe_name = re.sub(r"[^A-Za-z0-9._ -]", "_", filename or "catws_8d.mp3").strip() or "catws_8d.mp3"
    return _s3().generate_presigned_url(
        "get_object",
        Params={
            "Bucket": settings.s3_bucket,
            "Key": relative,
            "ResponseContentDisposition": f'attachment; filename="{safe_name}"',
            "ResponseContentType": "audio/mpeg",
        },
        ExpiresIn=expires_in,
    )
