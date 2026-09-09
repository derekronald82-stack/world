param([Parameter(Mandatory=$true)][string]$ApiUrl)
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..\frontend')
try { .\build_android.ps1 -ApiUrl $ApiUrl -EntryPoint 'admin_app.dart' }
finally { Pop-Location }
