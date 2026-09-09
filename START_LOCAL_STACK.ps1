$ErrorActionPreference = "Stop"
$envFile = Join-Path $PSScriptRoot "local-stack.env"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw "Docker Desktop is not installed or docker is not available in PATH."
}

if (-not (Test-Path $envFile)) {
  $dbPass = "Db_" + ([guid]::NewGuid().ToString("N"))
  $pgPass = "Pg_" + ([guid]::NewGuid().ToString("N"))
  $secret = ([guid]::NewGuid().ToString("N")) + ([guid]::NewGuid().ToString("N"))
  $adminPass = "Admin_" + ([guid]::NewGuid().ToString("N"))
@"
POSTGRES_DB=catws_music
POSTGRES_USER=catws_app
POSTGRES_PASSWORD=$dbPass
PGADMIN_EMAIL=admin@catws.local
PGADMIN_PASSWORD=$pgPass
SECRET_KEY=$secret
ADMIN_USERNAME=admin
ADMIN_PASSWORD=$adminPass
ADMIN_SYNC_PASSWORD=false
"@ | Set-Content -Encoding UTF8 $envFile
  Write-Host "Created local-stack.env with random local credentials. Keep this file private." -ForegroundColor Green
  Write-Host "Local Catws admin username: admin"
  Write-Host "Local Catws admin password: $adminPass" -ForegroundColor Yellow
  Write-Host "pgAdmin email: admin@catws.local"
  Write-Host "pgAdmin password: $pgPass" -ForegroundColor Yellow
}

docker compose --env-file $envFile -f (Join-Path $PSScriptRoot "docker-compose.local.yml") up -d --build
Write-Host ""
Write-Host "Catws API: http://127.0.0.1:8000/api/health" -ForegroundColor Green
Write-Host "API docs:  http://127.0.0.1:8000/docs"
Write-Host "pgAdmin:   http://127.0.0.1:5050"
Write-Host ""
Write-Host "This local stack is for development. For a phone to work from anywhere, deploy the backend + PostgreSQL + storage publicly over HTTPS."
