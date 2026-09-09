# Catws Songs 5.0 — Complete Flutter + FastAPI Music App

Catws Songs is a cloud-ready music app with a Flutter Android frontend and FastAPI backend.

## V4 highlight — user-created 8D songs

Every logged-in user now has **Create your 8D song**.

```text
Choose personal audio
      ↓
Advanced 8D processing
      ↓
Preview result
   ↙       ↘
Download   Save to Catws
               ↓
          My 8D Songs
```

The personal 8D creator supports MP3, WAV, FLAC, M4A, AAC and OGG, with pan speed, intensity, hall reverb and decay controls. The generated result can be downloaded or saved to the user's Catws account. Saved creations can later be played, downloaded again or deleted.

The original user upload is deleted after conversion; Catws retains the generated output only.

## Advanced 8D engine

V4 integrates the HRTF-style circular panning + hall reverb processing from the provided `8d_audio_converter.zip` into the FastAPI service. The output is normalized to about -1 dBFS and exported as a stereo MP3.

## Existing features retained

- public HTTPS API configuration — no same-Wi-Fi requirement after deployment
- PostgreSQL-ready backend
- PostgreSQL production persistence + Cloudinary audio/image storage
- admin upload/edit/delete
- scheduled future releases
- featured songs, search, categories and new releases
- Liked Songs
- playlists
- recently played/history
- player queue, previous/next, shuffle and repeat-one
- seek/progress
- sleep timer
- add-to-playlist from player
- 8D conversion for catalog songs
- admin stats
- Docker + FFmpeg deployment

## New database table

`user_8d_creations` stores only structured data and the generated file path. Large MP3 files stay in local/object storage, not directly in PostgreSQL.

## Production architecture

```text
Android APK
    |
    | HTTPS
    v
FastAPI backend
   /        \
PostgreSQL          Cloudinary (`catws/...`)
metadata             songs / covers / 8D outputs
```

## Start here

- `DEPLOY_CLOUD.md` — public cloud deployment
- `OWN_DATABASE_SETUP.md` — your own PostgreSQL setup
- `USER_8D_STUDIO.md` — personal 8D creator details
- `backend/README.md`
- `frontend/README.md`

## Security notes

- Never put PostgreSQL/Cloudinary secrets inside Flutter.
- Use HTTPS for production.
- Use a long random `SECRET_KEY`.
- Use a strong admin password.
- `PUBLIC_BASE_URL` must be the public FastAPI URL so signed download links work.
- For a larger production service, add migrations, rate limits, malware/media scanning, monitoring and backups.

## Content

Users should upload/convert audio they created, own, or have permission to use.

## V5: Separate Normal and 8D libraries

## V6: Separate applications and durable media

`user_app/` and `admin_app/` are separate Flutter entrypoints that reuse the
existing CATWS theme and player package in `frontend/`. The user entrypoint
never renders admin controls. Production uses PostgreSQL plus Cloudinary;
catalog rows and their Cloudinary public IDs are durable and are never removed
automatically because of inactivity or Render restarts.

The Library button now opens two clear choices:

- **Option 1 — Normal Songs**: liked catalog songs, normal playlists, and normal listening history.
- **Option 2 — 8D Songs**: saved user-created 8D songs and their own separate 8D playlists.

Normal playlists store only catalog `songs`. 8D playlists use separate database tables (`user_8d_playlists` and `user_8d_playlist_items`) and contain only saved `user_8d_creations`. This prevents the two playlist types from being mixed accidentally. Users can add a saved 8D song to an 8D playlist from the 8D Creator or the 8D Library.
