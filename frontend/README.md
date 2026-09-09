# CATWS SONGS shared Flutter package

## Setup

```powershell
.\setup_frontend.ps1
```

## Run

```powershell
flutter run --dart-define=API_BASE_URL=https://YOUR-RENDER-SERVICE.onrender.com
```

For a backend on the same Wi-Fi as an Android phone, use the laptop's LAN address:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.39.114.119:8000
```

## Build APK

```powershell
.\build_android.ps1 -ApiUrl "https://YOUR-PUBLIC-API-DOMAIN"
```

## New: Create your own 8D song

Every logged-in user can open the **8D** icon from the home navigation or More menu.

They can:

- choose MP3/WAV/FLAC/M4A/AAC/OGG
- set pan speed, intensity, reverb and decay
- create the 8D version
- preview it
- download it
- save it to **My 8D Songs**
- download it again later
- delete it

The public music catalog remains admin-managed. A user's personal 8D creation is not automatically published to all users.

## Admin

The original `frontend` package remains the shared, theme-preserving runtime.
`../user_app` launches the listener app with admin controls suppressed, and
`../admin_app` launches the separate admin login/dashboard app. The backend
still enforces the admin role, so hiding controls is not the security boundary.

## Admin website

Build the separate admin Flutter app for the browser against the same FastAPI URL:

```powershell
flutter build web --release --dart-define=API_BASE_URL=https://YOUR-RENDER-SERVICE.onrender.com
```

Publish `build/web/` as the admin site. The packaged `downloads/catws-songs.apk` file is served at `/downloads/catws-songs.apk`.
