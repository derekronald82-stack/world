$ErrorActionPreference = "Stop"
$envFile = Join-Path $PSScriptRoot "local-stack.env"
if (-not (Test-Path $envFile)) { throw "local-stack.env was not found." }
docker compose --env-file $envFile -f (Join-Path $PSScriptRoot "docker-compose.local.yml") down
Write-Host "Catws local services stopped. PostgreSQL and media volumes were kept."
