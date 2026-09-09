# Catws Songs — Your Own PostgreSQL Database

You can use Catws Songs with a PostgreSQL database that you control. PostgreSQL stores **metadata** (users, song information, playlists, likes, history). Actual MP3/cover/8D files should remain in file/object storage.

## Option A — easiest local setup with Docker

Requirements: Docker Desktop.

From PowerShell in this project folder:

```powershell
.\START_LOCAL_STACK.ps1
```

The script creates private random local credentials, starts PostgreSQL, pgAdmin and FastAPI, and preserves database/media data in Docker volumes.

Open:

- API health: `http://127.0.0.1:8000/api/health`
- API docs: `http://127.0.0.1:8000/docs`
- pgAdmin: `http://127.0.0.1:5050`

In pgAdmin, register a server with host `db`, port `5432`, database `catws_music`, username `catws_app`, and the password from `local-stack.env`.

## Option B — PostgreSQL already installed on Windows

Create a database and app user using pgAdmin or psql. Then copy `backend/.env.local.example` to `backend/.env` and set:

```env
DATABASE_URL=postgresql+psycopg://YOUR_USER:YOUR_PASSWORD@127.0.0.1:5432/catws_music
STORAGE_BACKEND=local
MEDIA_ROOT=media
PUBLIC_BASE_URL=http://127.0.0.1:8000
```

Run the backend:

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

The backend creates the tables automatically on startup.

## What goes in PostgreSQL?

- users and roles
- songs: title, artist, category, audio path, cover path, featured flag
- playlists and playlist membership
- liked songs
- listening history
- scheduled release time
- 8D conversion records

Do **not** place 50 MB MP3s directly in SQL. Large files belong in local file storage or S3-compatible object storage.

## Final public app

A database on your laptop is not reachable when the laptop is off. For an APK that works on mobile data / any Wi-Fi, deploy:

```text
Flutter APK -> HTTPS FastAPI -> public PostgreSQL
                           -> public object storage
```

Use `backend/.env.cloud.example` and `DEPLOY_CLOUD.md` for that setup.
