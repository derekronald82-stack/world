# CATWS SONGS Admin App

This is a separate admin-facing Flutter entrypoint. The backend still verifies
the JWT role on every write; a user token receives HTTP 403 even if a request
is crafted outside this app.

Run from this directory:

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=https://YOUR-RENDER-SERVICE.onrender.com
```
