param(
  [Parameter(Mandatory=$true)][string]$ApiUrl,
  [string]$EntryPoint = "main.dart"
)
$ErrorActionPreference = "Stop"

if ($ApiUrl -notmatch '^https://') {
  Write-Warning "For a public release, use an HTTPS API URL."
}

if (-not (Test-Path (Join-Path $PSScriptRoot "android"))) {
  & (Join-Path $PSScriptRoot "setup_frontend.ps1")
}

flutter pub get
flutter build apk --release --target=lib/$EntryPoint --dart-define=API_BASE_URL=$ApiUrl
Write-Host "APK: build/app/outputs/flutter-apk/app-release.apk" -ForegroundColor Green
