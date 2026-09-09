param(
  [Parameter(Mandatory=$true)][string]$ApiUrl
)
$ErrorActionPreference = "Stop"
Push-Location (Join-Path $PSScriptRoot "frontend")
try {
  .\build_android.ps1 -ApiUrl $ApiUrl
} finally {
  Pop-Location
}
