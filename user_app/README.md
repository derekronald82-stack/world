# CATWS SONGS User App

This is the listener-facing Flutter entrypoint. It reuses the existing CATWS
theme, catalog, persistent player, playlists, likes, history, and 8D Studio
package from `../frontend`, while suppressing every admin control.

Run from this directory:

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=https://YOUR-RENDER-SERVICE.onrender.com
```
