# Catws Songs FastAPI Backend 4.0

## Run locally with SQLite

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env
python -m uvicorn app.main:app --reload
```

For PostgreSQL use `.env.local.example` or `.env.cloud.example`.

## Main endpoints

Authentication and catalog:

- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/songs`
- `POST /api/admin/songs` — admin upload
- `PATCH /api/admin/songs/{id}` — admin edit
- `DELETE /api/admin/songs/{id}` — admin delete + storage cleanup
- `/api/library/*` — favorites, playlists and listening history

8D features:

- `POST /api/audio/convert/{song_id}` — create an 8D version of a catalog song
- `POST /api/audio/create` — user uploads their own/permitted audio and creates a personal 8D result
- `GET /api/audio/creations` — My 8D Songs
- `POST /api/audio/creations/{id}/save` — keep result in Catws
- `DELETE /api/audio/creations/{id}` — remove personal 8D result + stored file
- `POST /api/audio/creations/{id}/download-link` — short-lived secure download link

## Personal 8D storage

The source upload is used only as a temporary processing object. The generated MP3 is stored under `catws/users/{user_id}/eightd/` in Cloudinary and referenced by `user_8d_creations` in PostgreSQL.

## Storage modes

Production uses `STORAGE_BACKEND=cloudinary`. Catalog media is stored under `catws/normal/audio/`, `catws/normal/covers/`, `catws/eightd/audio/`, and `catws/eightd/covers/`; Render only serves application code.

Local storage remains available for development/tests only. It is not a durable production store.

For cloud download links, `PUBLIC_BASE_URL` must be your public FastAPI HTTPS URL.

## Migrate existing local media

Set the production `DATABASE_URL`, `STORAGE_BACKEND=cloudinary`, `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, and `CLOUDINARY_API_SECRET`, then run from `backend/`:

```powershell
python scripts/migrate_media_to_cloudinary.py --dry-run
python scripts/migrate_media_to_cloudinary.py
```

The migration verifies each uploaded object and updates the database object paths. It never deletes local media or the old database. Keep those backups until the catalog and playback have been verified after a Render redeploy.

## Tests

```powershell
pytest -q
```

### Separate playlist APIs (V5)

Normal catalog playlists remain under `/api/library/playlists`. Personal saved 8D creations use `/api/library/8d-playlists`. They use separate database tables by design.
