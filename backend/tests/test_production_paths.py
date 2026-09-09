from fastapi import FastAPI

from app import main
from app.config import Settings
from app.services import cloudinary_service


def test_cloudinary_startup_does_not_require_local_media(monkeypatch, tmp_path):
    """Regression test for Render startup with no media/ directory."""
    monkeypatch.setattr(main.settings, "storage_backend", "cloudinary")
    monkeypatch.setattr(main.settings, "media_root", str(tmp_path / "missing-media"))

    application = FastAPI()
    main._mount_local_media(application)

    assert not any(route.path.startswith("/media") for route in application.routes)


def test_secret_key_prefers_authoritative_name_over_legacy_alias(monkeypatch):
    monkeypatch.setenv("SECRET_KEY", "authoritative-secret")
    monkeypatch.setenv("JWT_SECRET", "legacy-secret")
    configured = Settings(_env_file=None)
    assert configured.secret_key == "authoritative-secret"


def test_cloudinary_generic_delete_checks_image_after_video_not_found(monkeypatch):
    class Uploader:
        def __init__(self):
            self.calls = []

        def destroy(self, public_id, **kwargs):
            self.calls.append((public_id, kwargs["resource_type"]))
            return {"result": "not found" if kwargs["resource_type"] == "video" else "ok"}

    class Client:
        def __init__(self):
            self.uploader = Uploader()

    client = Client()
    monkeypatch.setattr(cloudinary_service, "_client", lambda: client)
    cloudinary_service.delete_asset("catws/normal/covers/example")

    assert client.uploader.calls == [
        ("catws/normal/covers/example", "video"),
        ("catws/normal/covers/example", "image"),
    ]
