# CATWS SONGS Android release and update guide

## Release identity

- Android application ID: `com.catws.songs`
- Current Flutter version: `4.0.0+4` (`versionName 4.0.0`, `versionCode 4`)
- Keep the application ID and the existing release keystore unchanged for every update. Android will reject an APK signed with a different key as an upgrade.

Changing songs, covers, metadata, or other server content does not require an APK release. Publish a new APK only for Flutter/Android code changes, and increment the build number every time: `version: 4.0.1+5`.

## Build and signing

Create `frontend/android/key.properties` locally (this file is ignored by git):

```properties
storePassword=your-keystore-password
keyPassword=your-key-password
keyAlias=your-key-alias
storeFile=C:/secure/catws-upload-key.jks
```

The Gradle release config reads that file and fails a release build if it is missing or incomplete. Debug builds continue to use the normal debug key. Never commit the keystore or `key.properties`.

Build with the production API URL:

```powershell
cd frontend
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=https://your-api-domain.com
```

The APK output is normally `frontend/build/app/outputs/flutter-apk/app-release.apk`. Test the signed APK on a device before publishing it to the download location.

## Publishing an update

1. Increment `version` in `frontend/pubspec.yaml` so the `+N` build number is greater than the installed build.
2. Build and sign with the same production keystore.
3. Upload the APK to an HTTPS URL (GitHub Releases, object storage, or another trusted host).
4. Create one active release using the admin API below. Creating or activating a release deactivates the previous Android release.

Example request:

```powershell
curl.exe -X POST https://your-api-domain.com/api/admin/app-releases `
  -H "Authorization: Bearer ADMIN_TOKEN" `
  -H "Content-Type: application/json" `
  -d '{"version_name":"4.0.1","version_code":5,"minimum_supported_version_code":4,"force_update":false,"title":"CATWS Songs 4.0.1","message":"Bug fixes and performance improvements.","download_url":"https://downloads.example.com/catws-4.0.1.apk","is_active":true}'
```

The public app check is `GET /api/app/version`. It requires no login and returns the highest active Android release. Release list/create/update/delete endpoints are admin-only at `/api/admin/app-releases`.

## User experience and safety

The app checks for updates after the initial screen is rendered, so a slow or unavailable server never blocks startup. Optional updates can be dismissed and are not shown again for the same version code. Forced updates disable dismissal and back navigation until the user chooses `Update now`.

The APK URL is validated as HTTPS by the backend and again in Flutter. The app opens the URL in the system browser; it does not silently install APKs and does not request `REQUEST_INSTALL_PACKAGES`.
