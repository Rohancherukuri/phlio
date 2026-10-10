param([switch]$Seed, [switch]$RunApp)
$ErrorActionPreference = 'Stop'
$backendRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Split-Path -Parent $backendRoot
Push-Location -LiteralPath $backendRoot
try {
New-Item -ItemType Directory -Force -Path 'data/surreal' | Out-Null
if (-not (Get-NetTCPConnection -LocalPort 8001 -State Listen -ErrorAction SilentlyContinue)) {
    $surrealExe = (Get-Command surreal -ErrorAction Stop).Source
    $databasePath = (Join-Path $backendRoot 'data/surreal/graph.db').Replace('\', '/')
    Start-Process -FilePath $surrealExe -ArgumentList @('start', '--bind', '127.0.0.1:8001', '--user', 'root', '--pass', 'root', "surrealkv:$databasePath") -WindowStyle Hidden -RedirectStandardOutput (Join-Path $backendRoot 'data/surreal/server.log') -RedirectStandardError (Join-Path $backendRoot 'data/surreal/server-error.log')
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        if (Get-NetTCPConnection -LocalPort 8001 -State Listen -ErrorAction SilentlyContinue) { break }
        Start-Sleep -Milliseconds 250
    }
}
uv run python -c "import redis; assert redis.Redis(host='127.0.0.1', protocol=2, socket_connect_timeout=2).ping()"
if ($LASTEXITCODE -ne 0) { throw 'Start Redis on 127.0.0.1:6379, then run this script again.' }
if ($Seed) {
    uv run python -m scripts.seed_social_graph
    if ($LASTEXITCODE -ne 0) { throw 'Seeding failed. See the error above; rerunning resumes safely.' }
    uv run python -m scripts.seed_platform_content
    if ($LASTEXITCODE -ne 0) { throw 'Platform content seed failed.' }
    uv run python -m scripts.enrich_social_demo
    if ($LASTEXITCODE -ne 0) { throw 'Social enrichment failed.' }
}
if (-not (Get-NetTCPConnection -LocalPort 8002 -State Listen -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath (Get-Command uv).Source -ArgumentList @('run', 'python', '-m', 'scripts.run_graph_demo') -WorkingDirectory $backendRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $backendRoot 'data/graph-api.log') -RedirectStandardError (Join-Path $backendRoot 'data/graph-api-error.log')
}
$apiReady = $false
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    try {
        Invoke-RestMethod -Uri 'http://127.0.0.1:8002/health' -TimeoutSec 1 | Out-Null
        $apiReady = $true
        break
    } catch {
        Start-Sleep -Milliseconds 250
    }
}
if (-not $apiReady) { throw 'API startup failed. See backend/data/graph-api-error.log.' }
if (-not (Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath (Get-Command uv).Source -ArgumentList @('run', 'uvicorn', 'app.main:app', '--host', '0.0.0.0', '--port', '8000') -WorkingDirectory $backendRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $backendRoot 'data/api.log') -RedirectStandardError (Join-Path $backendRoot 'data/api-error.log')
}
Write-Output 'Normal API: http://127.0.0.1:8000/docs; graph demo: http://127.0.0.1:8002/docs'
if ($RunApp) {
    Set-Location -LiteralPath (Join-Path $projectRoot 'frontend/ui')
    flutter run --dart-define=API_BASE_URL=http://localhost:8002/api/v1
}

} finally {
    Pop-Location
}
