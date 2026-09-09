$ErrorActionPreference = "Stop"
flutter create .
flutter pub get

$manifest = Join-Path $PSScriptRoot "android/app/src/main/AndroidManifest.xml"
if (Test-Path $manifest) {
  $text = Get-Content $manifest -Raw
  if ($text -notmatch 'android.permission.INTERNET') {
    $replacement = '<manifest$1>' + [Environment]::NewLine + '    <uses-permission android:name="android.permission.INTERNET" />'
    $text = [regex]::Replace($text, '<manifest([^>]*)>', $replacement, 1)
  }
  $text = $text -replace 'android:label="[^"]*"', 'android:label="Catws Songs"'
  Set-Content -Path $manifest -Value $text -Encoding UTF8
}

Write-Host "Flutter platform files created and Android INTERNET permission checked." -ForegroundColor Green
Write-Host "Run with: flutter run --dart-define=API_BASE_URL=https://YOUR-PUBLIC-API-DOMAIN"
