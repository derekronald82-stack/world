import os
import json
from datetime import datetime, timedelta, timezone

os.environ.setdefault("DATABASE_URL", "sqlite:///./test_8d_music.db")
os.environ.setdefault("SECRET_KEY", "test-secret-key-at-least-32-bytes-long-12345")

from fastapi.testclient import TestClient
from sqlalchemy import select
from app.main import app
from app.db import SessionLocal
from app.models import ScheduledRelease, Song, User, User8DCreation
from app.security import hash_password


def _login(client: TestClient, username: str = "testuser_8d") -> dict[str, str]:
    password = "StrongPass123"
    r = client.post("/api/auth/register", json={"username": username, "password": password})
    assert r.status_code in (201, 409)
    r = client.post("/api/auth/login", json={"username": username, "password": password})
    assert r.status_code == 200
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _song(username: str = "testuser_8d", title: str = "Library Test Song") -> int:
    with SessionLocal() as db:
        user = db.scalar(select(User).where(User.username == username))
        existing = db.scalar(select(Song).where(Song.title == title, Song.created_by == user.id))
        if existing:
            return existing.id
        song = Song(
            title=title,
            artist="Catws Test",
            category="Relax",
            audio_path="audio/test.mp3",
            cover_path="covers/test.jpg",
            is_featured=True,
            created_by=user.id,
        )
        db.add(song)
        db.commit()
        db.refresh(song)
        return song.id


def test_health():
    with TestClient(app) as client:
        r = client.get("/api/health")
        assert r.status_code == 200
        assert r.json()["ok"] is True
        assert r.json()["version"] == "5.0.0"

def test_public_catalog_aliases_require_no_login():
    with TestClient(app) as client:
        for path in ("/api/songs/featured", "/api/songs/latest", "/api/songs/categories"):
            response = client.get(path)
            assert response.status_code == 200, response.text
            assert isinstance(response.json(), list)


def test_admin_write_routes_require_authentication():
    with TestClient(app) as client:
        response = client.post("/api/admin/songs/normal", data={"title": "Nope"})
        assert response.status_code == 401


def test_scheduled_song_is_hidden_from_categories():
    username = "category_schedule_user_v5"
    with TestClient(app) as client:
        _login(client, username)
        song_id = _song(username, "Future Category Catws Song")
        with SessionLocal() as db:
            db.get(Song, song_id).category = "FutureOnlyCategory"
            release = db.scalar(select(ScheduledRelease).where(ScheduledRelease.song_id == song_id))
            if release:
                release.release_at = datetime.now(timezone.utc) + timedelta(days=1)
            else:
                db.add(ScheduledRelease(
                    song_id=song_id,
                    release_at=datetime.now(timezone.utc) + timedelta(days=1),
                ))
            db.commit()
        categories = client.get("/api/songs/categories")
        assert categories.status_code == 200
        assert "FutureOnlyCategory" not in categories.json()


def test_register_login_me():
    with TestClient(app) as client:
        headers = _login(client)
        me = client.get("/api/auth/me", headers=headers)
        assert me.status_code == 200
        assert me.json()["username"] == "testuser_8d"


def test_favorites_playlists_and_history():
    with TestClient(app) as client:
        headers = _login(client)
        song_id = _song()

        assert client.post(f"/api/library/favorites/{song_id}", headers=headers).status_code == 200
        liked = client.get("/api/library/favorites", headers=headers)
        assert liked.status_code == 200
        assert any(s["id"] == song_id for s in liked.json())

        p = client.post("/api/library/playlists", headers={**headers, "Content-Type": "application/json"}, json={"name": "Study Mix", "description": "Focus"})
        assert p.status_code == 201
        pid = p.json()["id"]
        assert client.post(f"/api/library/playlists/{pid}/songs/{song_id}", headers=headers).status_code == 200
        detail = client.get(f"/api/library/playlists/{pid}", headers=headers)
        assert detail.status_code == 200
        assert detail.json()["song_count"] == 1

        assert client.post(f"/api/library/history/{song_id}", headers=headers).status_code == 200
        history = client.get("/api/library/history", headers=headers)
        assert history.status_code == 200
        assert any(s["id"] == song_id for s in history.json())


def test_future_song_is_hidden():
    username = "schedule_user_8d"
    with TestClient(app) as client:
        _login(client, username)
        song_id = _song(username, "Future Catws Song")
        with SessionLocal() as db:
            old = db.scalar(select(ScheduledRelease).where(ScheduledRelease.song_id == song_id))
            release_at = datetime.now(timezone.utc) + timedelta(days=1)
            if old:
                old.release_at = release_at
            else:
                db.add(ScheduledRelease(song_id=song_id, release_at=release_at))
            db.commit()
        r = client.get("/api/songs")
        assert r.status_code == 200
        assert all(s["id"] != song_id for s in r.json())


def test_admin_can_edit_song_and_release_schedule():
    admin_name = "testadmin_v3"
    password = "StrongAdminPass123"
    with SessionLocal() as db:
        admin = db.scalar(select(User).where(User.username == admin_name))
        if not admin:
            admin = User(username=admin_name, password_hash=hash_password(password), role="admin")
            db.add(admin)
            db.commit()
        elif admin.role != "admin":
            admin.role = "admin"
            admin.password_hash = hash_password(password)
            db.commit()

    with TestClient(app) as client:
        login = client.post("/api/auth/login", json={"username": admin_name, "password": password})
        assert login.status_code == 200
        headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
        files = {
            "audio": ("tiny.mp3", b"ID3test", "audio/mpeg"),
            "cover": ("cover.jpg", b"\xff\xd8\xfftiny", "image/jpeg"),
        }
        created = client.post(
            "/api/admin/songs",
            headers=headers,
            data={"title": "Before Edit", "artist": "Catws", "category": "Relax", "is_featured": "false"},
            files=files,
        )
        assert created.status_code == 201, created.text
        song_id = created.json()["id"]

        release = (datetime.now(timezone.utc) + timedelta(days=2)).isoformat()
        edited = client.patch(
            f"/api/admin/songs/{song_id}",
            headers=headers,
            data={
                "title": "After Edit",
                "artist": "Catws Studio",
                "category": "8D",
                "is_featured": "true",
                "release_action": "set",
                "release_at": release,
            },
        )
        assert edited.status_code == 200, edited.text
        assert edited.json()["title"] == "After Edit"
        assert edited.json()["is_featured"] is True
        assert edited.json()["release_at"] is not None

        # Future scheduled song should be hidden from the public list.
        public = client.get("/api/songs")
        assert public.status_code == 200
        assert all(item["id"] != song_id for item in public.json())

        # Clearing the schedule makes it public immediately.
        cleared = client.patch(
            f"/api/admin/songs/{song_id}",
            headers=headers,
            data={"release_action": "clear"},
        )
        assert cleared.status_code == 200
        assert cleared.json()["release_at"] is None

        deleted = client.delete(f"/api/admin/songs/{song_id}", headers=headers)
        assert deleted.status_code == 204


def test_normal_and_8d_admin_catalog_routes_are_separate():
    admin_name = "typed_catalog_admin_v5"
    password = "StrongAdminPass123"
    with SessionLocal() as db:
        admin = db.scalar(select(User).where(User.username == admin_name))
        if not admin:
            admin = User(username=admin_name, password_hash=hash_password(password), role="admin")
            db.add(admin)
            db.commit()
    with TestClient(app) as client:
        login = client.post("/api/auth/login", json={"username": admin_name, "password": password})
        headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
        files = {
            "audio": ("typed.mp3", b"ID3typed", "audio/mpeg"),
            "cover": ("typed.jpg", b"\xff\xd8\xfftyped", "image/jpeg"),
        }
        normal = client.post("/api/admin/songs/normal", headers=headers, data={"title": "Typed Normal"}, files=files)
        eightd = client.post("/api/admin/songs/8d", headers=headers, data={"title": "Typed 8D"}, files=files)
        assert normal.status_code == 201
        assert eightd.status_code == 201
        assert normal.json()["song_type"] == "normal"
        assert eightd.json()["song_type"] == "8d"
        assert "/normal/audio/" in normal.json()["audio_url"]
        assert "/eightd/audio/" in eightd.json()["audio_url"]
        assert {song["song_type"] for song in client.get("/api/songs/normal").json()} == {"normal"}
        assert {song["song_type"] for song in client.get("/api/songs/8d").json()} == {"8d"}
        user_headers = _login(client, "typed_catalog_user_v5")
        forbidden = client.post("/api/admin/songs/normal", headers=user_headers, data={"title": "Nope"}, files=files)
        assert forbidden.status_code == 403


def test_admin_can_bulk_upload_up_to_ten_song_cover_pairs():
    admin_name = "bulk_upload_admin_v1"
    password = "StrongAdminPass123"
    with SessionLocal() as db:
        admin = db.scalar(select(User).where(User.username == admin_name))
        if not admin:
            admin = User(username=admin_name, password_hash=hash_password(password), role="admin")
            db.add(admin)
            db.commit()

    with TestClient(app) as client:
        login = client.post("/api/auth/login", json={"username": admin_name, "password": password})
        assert login.status_code == 200
        headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
        audio = [
            ("audio", (f"Track {index}.mp3", b"ID3bulk", "audio/mpeg"))
            for index in range(1, 3)
        ]
        covers = [
            ("cover", (f"Track {index}.jpg", b"\xff\xd8\xffbulk", "image/jpeg"))
            for index in range(1, 3)
        ]
        manifest = json.dumps([
            {"audio_name": f"Track {index}.mp3", "cover_name": f"Track {index}.jpg", "title": f"Bulk Track {index}"}
            for index in range(1, 3)
        ])
        response = client.post(
            "/api/admin/songs/bulk",
            headers=headers,
            data={"manifest": manifest, "artist": "Catws Bulk", "category": "Bulk Test", "song_type": "normal"},
            files=audio + covers,
        )
        assert response.status_code == 201, response.text
        assert [song["title"] for song in response.json()] == ["Bulk Track 1", "Bulk Track 2"]



def test_user_can_create_save_list_and_get_download_link(monkeypatch):
    from app.routers import audio as audio_router

    async def fake_save_upload(upload, kind):
        assert kind == "audio"
        return "audio/user-source.mp3"

    monkeypatch.setattr(audio_router, "save_upload", fake_save_upload)
    monkeypatch.setattr(audio_router, "convert_to_8d", lambda *args, **kwargs: "outputs/user-created-8d.mp3")
    monkeypatch.setattr(audio_router, "delete_relative", lambda *_args, **_kwargs: None)

    username = "creator_user_v4"
    with TestClient(app) as client:
        headers = _login(client, username)
        created = client.post(
            "/api/audio/create",
            headers=headers,
            data={
                "title": "My Private 8D",
                "pan_speed": "0.5",
                "intensity": "1.0",
                "reverb": "0.35",
                "decay": "2.5",
            },
            files={"audio": ("my-song.mp3", b"ID3demo", "audio/mpeg")},
        )
        assert created.status_code == 201, created.text
        body = created.json()
        assert body["title"] == "My Private 8D"
        assert body["saved_to_catws"] is False
        creation_id = body["id"]

        # Unsaved creations are not shown in the default private Catws library.
        before = client.get("/api/audio/creations", headers=headers)
        assert before.status_code == 200
        assert all(item["id"] != creation_id for item in before.json())

        saved = client.post(f"/api/audio/creations/{creation_id}/save", headers=headers)
        assert saved.status_code == 200
        assert saved.json()["saved_to_catws"] is True

        library = client.get("/api/audio/creations", headers=headers)
        assert library.status_code == 200
        assert any(item["id"] == creation_id for item in library.json())

        link = client.post(f"/api/audio/creations/{creation_id}/download-link", headers=headers)
        assert link.status_code == 200
        assert f"/api/audio/download/{creation_id}?token=" in link.json()["url"]

        deleted = client.delete(f"/api/audio/creations/{creation_id}", headers=headers)
        assert deleted.status_code == 204


def test_normal_and_8d_playlists_are_separate():
    username = "separate_library_user_v5"
    with TestClient(app) as client:
        headers = _login(client, username)
        song_id = _song(username, "Normal Only Track")

        # Normal playlist accepts catalog songs.
        normal = client.post(
            "/api/library/playlists",
            headers={**headers, "Content-Type": "application/json"},
            json={"name": "Normal Mix", "description": "Catalog songs"},
        )
        assert normal.status_code == 201
        normal_id = normal.json()["id"]
        assert client.post(f"/api/library/playlists/{normal_id}/songs/{song_id}", headers=headers).status_code == 200

        # Saved user-created 8D track lives in its own model/library.
        with SessionLocal() as db:
            user = db.scalar(select(User).where(User.username == username))
            creation = User8DCreation(
                user_id=user.id,
                title="My 8D Only Track",
                source_filename="source.mp3",
                output_path="outputs/my-8d-only.mp3",
                saved_to_catws=True,
            )
            db.add(creation)
            db.commit()
            db.refresh(creation)
            creation_id = creation.id

        eightd = client.post(
            "/api/library/8d-playlists",
            headers={**headers, "Content-Type": "application/json"},
            json={"name": "8D Chill", "description": "Only my 8D songs"},
        )
        assert eightd.status_code == 201, eightd.text
        eightd_id = eightd.json()["id"]
        added = client.post(f"/api/library/8d-playlists/{eightd_id}/songs/{creation_id}", headers=headers)
        assert added.status_code == 200, added.text
        detail = client.get(f"/api/library/8d-playlists/{eightd_id}", headers=headers)
        assert detail.status_code == 200
        assert detail.json()["song_count"] == 1
        assert detail.json()["songs"][0]["id"] == creation_id

        normal_detail = client.get(f"/api/library/playlists/{normal_id}", headers=headers)
        assert normal_detail.status_code == 200
        assert normal_detail.json()["song_count"] == 1
        assert normal_detail.json()["songs"][0]["id"] == song_id


def test_app_version_is_public_and_release_crud_is_admin_only():
    admin_name = "release_admin_v1"
    password = "StrongAdminPass123"
    with SessionLocal() as db:
        admin = db.scalar(select(User).where(User.username == admin_name))
        if not admin:
            admin = User(
                username=admin_name,
                password_hash=hash_password(password),
                role="admin",
            )
            db.add(admin)
            db.commit()

    with TestClient(app) as client:
        public_before = client.get("/api/app/version")
        assert public_before.status_code == 200
        assert public_before.json()["latest_version_code"] == 0

        user_headers = _login(client, "release_regular_user_v1")
        forbidden = client.get("/api/admin/app-releases", headers=user_headers)
        assert forbidden.status_code == 403

        login = client.post(
            "/api/auth/login",
            json={"username": admin_name, "password": password},
        )
        assert login.status_code == 200
        admin_headers = {"Authorization": f"Bearer {login.json()['access_token']}"}

        invalid = client.post(
            "/api/admin/app-releases",
            headers=admin_headers,
            json={
                "version_name": "4.0.1",
                "version_code": 5,
                "download_url": "http://example.com/catws.apk",
            },
        )
        assert invalid.status_code == 422

        created = client.post(
            "/api/admin/app-releases",
            headers=admin_headers,
            json={
                "version_name": "4.0.1",
                "version_code": 5,
                "minimum_supported_version_code": 3,
                "title": "CATWS Songs 4.0.1",
                "message": "Faster startup and new songs.",
                "download_url": "https://downloads.example.com/catws-4.0.1.apk",
                "is_active": True,
            },
        )
        assert created.status_code == 201, created.text
        release_id = created.json()["id"]

        public_after = client.get("/api/app/version")
        assert public_after.status_code == 200
        assert public_after.json()["latest_version_code"] == 5
        assert public_after.json()["minimum_supported_version_code"] == 3

        edited = client.patch(
            f"/api/admin/app-releases/{release_id}",
            headers=admin_headers,
            json={"force_update": True},
        )
        assert edited.status_code == 200
        assert edited.json()["force_update"] is True

        listed = client.get("/api/admin/app-releases", headers=admin_headers)
        assert listed.status_code == 200
        assert any(item["id"] == release_id for item in listed.json())

        deleted = client.delete(
            f"/api/admin/app-releases/{release_id}", headers=admin_headers
        )
        assert deleted.status_code == 204
