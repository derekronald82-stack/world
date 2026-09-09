# Catws Songs on a personal VPS

This deployment keeps PostgreSQL private inside Docker, stores production audio/covers in S3-compatible object storage, and serves the FastAPI API over HTTPS. The laptop is not part of the runtime path.

## 1. Prepare the server

Install Docker Engine/Compose and a DNS name for the server. Clone this project to `/srv/catws`:

```bash
sudo mkdir -p /srv/catws
sudo chown "$USER" /srv/catws
git clone YOUR_REPOSITORY_URL /srv/catws
cd /srv/catws
cp vps.env.example vps.env
chmod 600 vps.env
```

Edit `vps.env`. Use a public HTTPS API name in `PUBLIC_BASE_URL`, the admin web origin in `CORS_ORIGINS`, and the S3-compatible credentials in the storage section. `ADMIN_SYNC_PASSWORD=false` is the safe default. Set it to `true` only for one controlled restart when deliberately replacing an existing admin password, then set it back to `false`.

## 2. Start the API and database

```bash
docker compose --env-file vps.env -f docker-compose.vps.yml up -d --build
curl http://127.0.0.1:8000/api/health
```

The Compose file does not mount a media volume. With `STORAGE_BACKEND=s3`, uploaded objects go to these prefixes:

```text
normal/audio/
normal/covers/
eightd/audio/
eightd/covers/
user-generated/eightd/
```

Back up the named PostgreSQL volume and the object-storage bucket separately.

## 3. Build and publish the admin website

On a machine with Flutter installed:

```powershell
cd frontend
flutter pub get
flutter build web --release --dart-define=API_BASE_URL=https://api.example.com
```

Copy `frontend/build/web/` to `/srv/catws/frontend/build/web` on the VPS. The build includes `downloads/catws-songs.apk`; the website button opens `/downloads/catws-songs.apk`.

## 4. Add HTTPS reverse proxy

Install Caddy or Nginx. The included `deploy/Caddyfile.example` shows the recommended two-host setup:

- `api.example.com` proxies to `127.0.0.1:8000`.
- `admin.example.com` serves `frontend/build/web` with SPA fallback to `index.html`.

Caddy obtains and renews HTTPS certificates automatically after DNS points at the VPS. Set `CORS_ORIGINS=https://admin.example.com` after the website host is known.

## 5. Build the APK against the same API

```powershell
.\BUILD_APK.ps1 -ApiUrl "https://api.example.com"
```

The release output is `frontend/build/app/outputs/flutter-apk/app-release.apk`. Copy that file to `frontend/web/downloads/catws-songs.apk` before rebuilding the web site if you want the download button to serve the newest APK.

## Operations

```bash
docker compose --env-file vps.env -f docker-compose.vps.yml ps
docker compose --env-file vps.env -f docker-compose.vps.yml logs -f backend
docker compose --env-file vps.env -f docker-compose.vps.yml pull
docker compose --env-file vps.env -f docker-compose.vps.yml up -d --build
```

Do not expose PostgreSQL to the internet, commit `vps.env`, or put database/S3 credentials in Flutter. The application currently creates tables and performs additive startup compatibility changes; use a real migration tool before future non-additive schema changes.
