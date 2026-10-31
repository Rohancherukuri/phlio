# Moves the local Phlio database from SurrealDB 2.x to 3.x.
#
# SurrealDB 3 can't open a 2.x data folder, so this:
#   1. exports the local database with the 2.x CLI (prepared for 3.x),
#   2. stops the local API, seeded Spaces and SurrealDB,
#   3. upgrades the surreal CLI to 3.x (scoop app "surrealdb", or `surreal upgrade`),
#   4. keeps the old data folder as data/surreal/graph.v2-backup-<date>.db,
#   5. starts SurrealDB 3 on a fresh data/surreal/graph.db and imports the export.
# Afterwards run .\scripts\Start-GraphDemo.ps1 -Restart as usual.
#
# Safe to run again: if the CLI is already 3.x it skips steps 1-3 and imports
# the export from the earlier run (only into an empty, fresh database).
#
#   .\scripts\Upgrade-SurrealDB3.ps1                 # latest 3.x
#   .\scripts\Upgrade-SurrealDB3.ps1 -Version 3.3.2  # a specific version
param([string]$Version = '')
$ErrorActionPreference = 'Stop'
$backendRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $backendRoot
try {
    function Test-Port([int]$Port) {
        [bool](Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    }
    function Stop-Port([int]$Port) {
        Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }
    }
    function Get-SurrealVersion {
        $exe = (Get-Command surreal -ErrorAction Stop).Source
        ((& $exe version) -join ' ').Trim()
    }
    function Start-LocalSurreal {
        $exe = (Get-Command surreal -ErrorAction Stop).Source
        $path = (Join-Path $backendRoot 'data/surreal/graph.db').Replace('\', '/')
        Start-Process -FilePath $exe -ArgumentList @('start', '--bind', '127.0.0.1:8001', '--user', 'root', '--pass', 'root', "surrealkv:$path") -WindowStyle Hidden -RedirectStandardOutput (Join-Path $backendRoot 'data/surreal/server.log') -RedirectStandardError (Join-Path $backendRoot 'data/surreal/server-error.log')
        for ($i = 0; $i -lt 40; $i++) {
            if (Test-Port 8001) { return }
            Start-Sleep -Milliseconds 250
        }
        throw 'SurrealDB did not start. See backend/data/surreal/server-error.log.'
    }

    $settings = (uv run python -c "from app.config import Settings; s = Settings(); print(s.surreal_namespace, s.surreal_database)" | Select-Object -Last 1).Trim().Split(' ')
    $namespace, $database = $settings[0], $settings[1]
    $export = Join-Path $backendRoot "data/export/$database.v3.import.surql"
    $current = Get-SurrealVersion
    Write-Host "surreal CLI: $current  (database $namespace/$database)"

    if ($current -match '^2\.') {
        # 1. Export with the 2.x CLI while the 2.x server can still read the data.
        New-Item -ItemType Directory -Force -Path 'data/surreal' | Out-Null
        if (-not (Test-Port 8001)) { Start-LocalSurreal }
        Write-Host 'Exporting the local database ...'
        uv run python -m scripts.publish_local_data --export-only 3
        if ($LASTEXITCODE -ne 0) { throw 'Export failed; nothing was changed.' }
        if (-not (Test-Path -LiteralPath $export)) { throw "Export file not found: $export" }

        # 2. Stop everything using the database.
        Write-Host 'Stopping the local API, seeded Spaces and SurrealDB ...'
        $spacesPid = Join-Path $backendRoot 'data/seeded-spaces.pid'
        if (Test-Path -LiteralPath $spacesPid) {
            Stop-Process -Id ([int](Get-Content -LiteralPath $spacesPid)) -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $spacesPid -ErrorAction SilentlyContinue
        }
        foreach ($port in @(8000, 8002, 8001)) { Stop-Port $port }
        Start-Sleep -Seconds 2

        # 3. Upgrade the CLI.
        $exe = (Get-Command surreal).Source
        if ($exe -like '*scoop*') {
            # Scoop's app is called "surrealdb" (the command is surreal.exe). Read the
            # real name from the shim, which points at ...\apps\<name>\current\surreal.exe.
            $app = 'surrealdb'
            $shim = [IO.Path]::ChangeExtension($exe, '.shim')
            if ((Test-Path -LiteralPath $shim) -and ((Get-Content -LiteralPath $shim -Raw) -match '\\apps\\([^\\]+)\\')) {
                $app = $Matches[1]
            }
            Write-Host "Upgrading $app with scoop ..."
            if ($Version) {
                scoop uninstall $app
                scoop install "$app@$Version"
            } else {
                scoop update $app
            }
            # The local "main" bucket can be stuck on an old 2.x manifest (scoop then
            # says "latest version" while 3.x is out). Reinstall from the current
            # manifest in ScoopInstaller/Main instead.
            if ((Get-SurrealVersion) -notmatch '^3\.') {
                Write-Host "Scoop's bucket still lists 2.x; installing from the current Main manifest ..."
                scoop uninstall $app
                scoop install 'https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/surrealdb.json'
            }
        } else {
            Write-Host 'Upgrading surreal ...'
            if ($Version) { & $exe upgrade --version $Version } else { & $exe upgrade }
        }
        $current = Get-SurrealVersion
        Write-Host "surreal CLI now: $current"
        if ($current -notmatch '^3\.') {
            throw "The CLI is still $current. Install SurrealDB 3 (scoop install https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/surrealdb.json), then run this script again; your data is untouched."
        }
    }
    elseif ($current -notmatch '^3\.') {
        throw "Unexpected surreal version: $current"
    }

    if (-not (Test-Path -LiteralPath $export)) {
        throw "No 3.x export at $export. Reinstall the 2.x CLI and run this script again, or import a 3.x export by hand."
    }

    # 4. Keep the 2.x data folder as a backup (only once).
    foreach ($port in @(8000, 8002, 8001)) { Stop-Port $port }
    Start-Sleep -Seconds 1
    $dataPath = Join-Path $backendRoot 'data/surreal/graph.db'
    $marker = Join-Path $backendRoot 'data/surreal/.v3'
    if ((Test-Path -LiteralPath $dataPath) -and -not (Test-Path -LiteralPath $marker)) {
        $backup = "graph.v2-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').db"
        Rename-Item -LiteralPath $dataPath -NewName $backup
        Write-Host "Old 2.x data kept at backend/data/surreal/$backup"
    }
    elseif (Test-Path -LiteralPath $marker) {
        throw 'The local database is already on SurrealDB 3 (data/surreal/.v3 exists). Nothing to do.'
    }

    # 5. Fresh 3.x database + import.
    Start-LocalSurreal
    Write-Host 'Importing into SurrealDB 3 ...'
    $exe = (Get-Command surreal).Source
    & $exe import --endpoint http://127.0.0.1:8001 --username root --password root --namespace $namespace --database $database $export
    if ($LASTEXITCODE -ne 0) { throw 'Import failed. The 2.x backup is untouched; see the message above.' }
    Set-Content -LiteralPath $marker -Value $current
    Stop-Port 8001
    Write-Host ''
    Write-Host "Done: local database is on $current."
    Write-Host 'Next: .\scripts\Start-GraphDemo.ps1 -Restart'
}
finally {
    Pop-Location
}
