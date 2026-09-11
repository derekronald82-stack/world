# CATWS Android release signing

- Package ID: `com.catws.songs`
- Current release version: `4.0.0+4`
- Existing production keystore found locally: **No**
- New permanent production keystore: `D:\CATWS_SIGNING\catws-release.jks`
- Alias: `catws`
- Certificate SHA-256: `DF:DD:47:8A:F7:DA:2F:4A:53:7D:44:6E:D4:EC:46:17:63:11:AB:44:19:D8:F2:5F:86:C0:A3:74:E0:F0:A2:C0`

No previous `.jks`, `.keystore`, or `key.properties` matching CATWS was found in the project or the available developer environment. A new permanent key was generated only after that check. If an older CATWS production APK is later found to use another certificate, do not distribute this new key as an update to it.

## Required local setup

Create `frontend/android/key.properties` locally, without committing it:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=YOUR_KEY_ALIAS
storeFile=C:/secure/catws-upload-key.jks
```

Use the original CATWS keystore if one exists in a secure backup. Store at least two encrypted backups in separate secure locations. Keep the keystore passwords in a password manager; do not put them in source code, chat, GitHub, or this document.

After restoring the original key, record only the public certificate fingerprint here:

```powershell
& "$env:ANDROID_HOME\build-tools\<version>\apksigner.bat" verify --verbose --print-certs frontend/build/app/outputs/flutter-apk/app-release.apk
```

The Gradle release build now fails clearly when `key.properties` is absent, incomplete, or points to a missing keystore. It never silently signs a production release with the debug key.
