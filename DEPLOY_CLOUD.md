# Deploy CATWS SONGS with PostgreSQL + Cloudinary persistence

Render should run the FastAPI application only. Permanent catalog metadata lives in PostgreSQL and permanent media lives in Cloudinary, so Render sleep/restart/redeploy cannot remove songs.

## Render environment variables

Set these in the Render service. Do not commit real values and do not put server secrets in Flutter:

```env
APP_NAME=Catws Music API
ENVIRONMENT=production
DATABASE_URL=YOUR_POSTGRES_DATABASE_URL
SECRET_KEY=YOUR_LONG_RANDOM_SECRET
ACCESS_TOKEN_MINUTES=1440
STORAGE_BACKEND=cloudinary
CLOUDINARY_CLOUD_NAME=YOUR_CLOUD_NAME
CLOUDINARY_API_KEY=YOUR_API_KEY
CLOUDINARY_API_SECRET=YOUR_API_SECRET
PUBLIC_BASE_URL=https://YOUR-RENDER-SERVICE.onrender.com
ADMIN_USERNAME=admin
ADMIN_PASSWORD=YOUR_ADMIN_PASSWORD
MAX_AUDIO_MB=50
MAX_IMAGE_MB=8
CORS_ORIGINS=*
```

`DATABASE_URL` must be a PostgreSQL URL using the `postgresql+psycopg` driver. Production startup fails clearly if it is missing, SQLite is selected, or the Cloudinary credentials are not set.

## Migration

Before migration, keep the existing local `media/` folder and old database. From `backend/`, run:

```powershell
python scripts/migrate_media_to_cloudinary.py --dry-run
python scripts/migrate_media_to_cloudinary.py
```

The script uploads legacy audio/covers with UUID public IDs, verifies them, updates URL/public-ID metadata, and logs failures. It never deletes local media or the old database. Keep the backup until the redeploy playback check passes.

## Render commands

The repository is configured with `render.yaml` and `backend/Dockerfile`. The container installs FFmpeg and starts:

```text
alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

Health check:

```text
https://YOUR-RENDER-SERVICE.onrender.com/api/health
```

## Flutter build

Both Admin and User builds use the same public HTTPS API through `API_BASE_URL`:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=https://YOUR-RENDER-SERVICE.onrender.com
```

After deployment, verify `GET /api/songs`, a normal upload, an 8D upload, User app refresh/playback, and the same checks again after a Render manual deploy.
