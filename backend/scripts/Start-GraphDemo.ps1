param([switch]$Seed, [switch]$RunApp, [switch]$Restart)
$ErrorActionPreference = 'Stop'
$backendRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Split-Path -Parent $backendRoot
Push-Location -LiteralPath $backendRoot
try {
if (Test-Path -LiteralPath (Join-Path $backendRoot 'data/livekit/local.yaml')) {
    & (Join-Path $PSScriptRoot 'Start-Realtime.ps1')
}
# -Restart stops the running API processes so code changes are picked up
# (otherwise an API already listening on 8000/8002 keeps serving old code).
$spacesPid = Join-Path $backendRoot 'data/seeded-spaces.pid'
if ($Restart) {
    # The seeded Spaces runner shares the API code; restart it too.
    if (Test-Path -LiteralPath $spacesPid) {
        Stop-Process -Id ([int](Get-Content -LiteralPath $spacesPid)) -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $spacesPid -ErrorAction SilentlyContinue
    }
    foreach ($apiPort in @(8000, 8002)) {
        Get-NetTCPConnection -LocalPort $apiPort -State Listen -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
    }
    Start-Sleep -Milliseconds 800
}
New-Item -ItemType Directory -Force -Path 'data/surreal' | Out-Null
if ((Test-Path -LiteralPath 'data/translation/madlad400/model.bin') -and -not (Get-NetTCPConnection -LocalPort 8010 -State Listen -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath (Get-Command uv).Source -ArgumentList @('run', 'python', '-m', 'scripts.translation_server') -WorkingDirectory $backendRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $backendRoot 'data/translation-api.log') -RedirectStandardError (Join-Path $backendRoot 'data/translation-api-error.log')
}

if (-not (Get-NetTCPConnection -LocalPort 8001 -State Listen -ErrorAction SilentlyContinue)) {
    $surrealExe = (Get-Command surreal -ErrorAction Stop).Source
    $databasePath = (Join-Path $backendRoot 'data/surreal/graph.db').Replace('\', '/')
    # SurrealDB 3 can't open a 2.x data folder; Upgrade-SurrealDB3.ps1 converts it (and leaves data/surreal/.v3).
    $surrealVersion = ((& $surrealExe version) -join ' ')
    if ($surrealVersion -match '^3\.' -and (Test-Path -LiteralPath $databasePath) -and -not (Test-Path -LiteralPath (Join-Path $backendRoot 'data/surreal/.v3'))) {
        throw "surreal is now $surrealVersion but data/surreal/graph.db is from SurrealDB 2. Run .\scripts\Upgrade-SurrealDB3.ps1 first."
    }
    Start-Process -FilePath $surrealExe -ArgumentList @('start', '--bind', '127.0.0.1:8001', '--user', 'root', '--pass', 'root', "surrealkv:$databasePath") -WindowStyle Hidden -RedirectStandardOutput (Join-Path $backendRoot 'data/surreal/server.log') -RedirectStandardError (Join-Path $backendRoot 'data/surreal/server-error.log')
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        if (Get-NetTCPConnection -LocalPort 8001 -State Listen -ErrorAction SilentlyContinue) { break }
        Start-Sleep -Milliseconds 250
    }
}
uv run python -c "import redis; assert redis.Redis(host='127.0.0.1', protocol=2, socket_connect_timeout=2).ping()"
if ($LASTEXITCODE -ne 0) { throw 'Start Redis on 127.0.0.1:6379, then run this script again.' }
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
$normalApiReady = $false
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    try {
        Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 2 | Out-Null
        $normalApiReady = $true
        break
    } catch { Start-Sleep -Milliseconds 500 }
}
if (-not $normalApiReady) { throw 'Login API on port 8000 failed to start. See backend/data/api-error.log.' }
Write-Output 'Normal API: http://127.0.0.1:8000/docs; graph demo: http://127.0.0.1:8002/docs'
# Community Spaces: demo accounts hosting live audio Spaces on the local
# LiveKit server (voices in media/spaces_seed). Runs in the background.
if ((Test-Path -LiteralPath (Join-Path $backendRoot 'data/livekit/local.yaml')) -and (Test-Path -LiteralPath (Join-Path $backendRoot 'media/spaces_seed/spaces.json'))) {
    $spacesRunning = $false
    if (Test-Path -LiteralPath $spacesPid) {
        $spacesRunning = [bool](Get-Process -Id ([int](Get-Content -LiteralPath $spacesPid)) -ErrorAction SilentlyContinue)
    }
    if (-not $spacesRunning) {
        Start-Process -FilePath (Get-Command uv).Source -ArgumentList @('run', 'python', '-m', 'scripts.run_seeded_spaces') -WorkingDirectory $backendRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $backendRoot 'data/seeded-spaces.log') -RedirectStandardError (Join-Path $backendRoot 'data/seeded-spaces-error.log')
        Write-Output 'Community Spaces starting (log: backend/data/seeded-spaces-error.log).'
    }
}
# Keep the community's 24-hour moments live (re-dates seeded moments; fast).
uv run python -m scripts.seed_community_moments
if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not refresh community moments. See the error above.' }
# localhost in an Android app is the phone, not this PC. Restore both USB
# tunnels on every start, including after a cable reconnect or device reboot.
if (Get-Command adb -ErrorAction SilentlyContinue) {
    $bridgeScript = Join-Path $PSScriptRoot 'Watch-UsbApiBridge.ps1'
    Start-Process powershell -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$bridgeScript`"")
    foreach ($line in (& adb devices)) {
        if ($line -match '^([^\s]+)\s+device$') {
            $deviceSerial = $Matches[1]
            foreach ($apiPort in @(8000, 8002)) {
                & adb -s $deviceSerial reverse "tcp:$apiPort" "tcp:$apiPort"
                if ($LASTEXITCODE -ne 0) { Write-Warning "Could not connect device $deviceSerial to API port $apiPort." }
            }
        }
    }
}
if ($Seed) {
    uv run python -m scripts.seed_social_graph
    if ($LASTEXITCODE -ne 0) { throw 'Seeding failed. See the error above; rerunning resumes safely.' }
    uv run python -m scripts.seed_platform_content
    if ($LASTEXITCODE -ne 0) { throw 'Platform content seed failed.' }
    uv run python -m scripts.enrich_social_demo
    if ($LASTEXITCODE -ne 0) { throw 'Social enrichment failed.' }
    uv run python -m scripts.import_licensed_social
    if ($LASTEXITCODE -ne 0) { throw 'Licensed social media import failed.' }
    uv run python -m scripts.prepare_video_renditions
    if ($LASTEXITCODE -ne 0) { throw 'Video quality preparation failed.' }
    uv run python -m scripts.humanize_demo_accounts
    if ($LASTEXITCODE -ne 0) { throw 'Community profile update failed.' }
    uv run python -m scripts.import_shop_catalog
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Retailer refresh failed; continuing with the saved catalog. Retry python -m scripts.import_shop_catalog later.' }
    uv run python -m scripts.import_book_catalog
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Book refresh failed; continuing with saved listings. Retry python -m scripts.import_book_catalog later.' }
    uv run python -m scripts.import_stream_music
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Music refresh failed; saved tracks remain available.' }
    uv run python -m scripts.import_live_recordings
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Recording import failed; saved recordings remain available.' }
    uv run python -m scripts.reconcile_catalog_sources
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Shared catalog reconciliation failed. See the error above.' }
    uv run python -m scripts.seed_catalog_engagement
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Catalog demo engagement seed failed. See the error above.' }
    uv run python -m scripts.seed_community_comments
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Community comment seed failed. See the error above.' }
}
if ($RunApp) {
    Set-Location -LiteralPath (Join-Path $projectRoot 'frontend/ui')
    flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8002/api/v1
}

} finally {
    Pop-Location
}
