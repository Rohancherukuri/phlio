param([string]$LanAddress, [switch]$Install)
$ErrorActionPreference = 'Stop'
$backendRoot = Split-Path -Parent $PSScriptRoot
$rtcRoot = Join-Path $backendRoot 'data/livekit'
New-Item -ItemType Directory -Force $rtcRoot | Out-Null
$binary = Join-Path $rtcRoot 'livekit-server.exe'
if (-not (Test-Path -LiteralPath $binary)) {
    if (-not $Install) { throw 'Run scripts/Start-Realtime.ps1 -Install once to download LiveKit.' }
    $archive = Join-Path $rtcRoot 'livekit.zip'
    Invoke-WebRequest 'https://github.com/livekit/livekit/releases/download/v1.13.9/livekit_1.13.9_windows_amd64.zip' -OutFile $archive
    Expand-Archive -LiteralPath $archive -DestinationPath $rtcRoot -Force
}
$config = Join-Path $rtcRoot 'local.yaml'
if (-not (Test-Path -LiteralPath $config)) {
    $envPath = Join-Path $backendRoot '.env'
    $envLines = @()
    if (Test-Path -LiteralPath $envPath) {
        $envLines = @(Get-Content -LiteralPath $envPath)
        if ($envLines | Where-Object { $_ -match '^LIVEKIT_[A-Z_]+=\s*[^\s]+' }) {
            throw 'Existing LIVEKIT settings retained. Configure data/livekit/local.yaml to match your server settings.'
        }
    }
    if (-not $LanAddress) {
        $LanAddress = (Get-NetIPConfiguration | Where-Object IPv4DefaultGateway | Select-Object -First 1).IPv4Address.IPAddress
    }
    if (-not $LanAddress) { throw 'Pass -LanAddress with the address reachable from your test devices.' }
    $parsedAddress = $null
    if (-not [System.Net.IPAddress]::TryParse($LanAddress, [ref]$parsedAddress)) { throw 'LanAddress must be an IP address.' }
    $secretBytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($secretBytes)
    $rtcSecret = [BitConverter]::ToString($secretBytes).Replace('-', '').ToLowerInvariant()
    @"
port: 7880
bind_addresses: ["0.0.0.0"]
rtc:
  tcp_port: 7881
  port_range_start: 50000
  port_range_end: 50100
  use_external_ip: false
  node_ip: $LanAddress
keys:
  phlio-local: $rtcSecret
"@ | Set-Content -LiteralPath $config -Encoding utf8
    $envLines | Where-Object { $_ -notmatch '^LIVEKIT_' } | Set-Content -LiteralPath $envPath -Encoding utf8
    @"

LIVEKIT_URL=ws://${LanAddress}:7880
LIVEKIT_API_URL=http://127.0.0.1:7880
LIVEKIT_API_KEY=phlio-local
LIVEKIT_API_SECRET=$rtcSecret
"@ | Add-Content -LiteralPath $envPath -Encoding utf8
}
if (-not (Get-NetTCPConnection -LocalPort 7880 -State Listen -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath $binary -ArgumentList @('--config', "`"$config`"") -WindowStyle Hidden -RedirectStandardOutput (Join-Path $rtcRoot 'server.log') -RedirectStandardError (Join-Path $rtcRoot 'error.log')
}
Write-Output 'LiveKit local server started. Restart the API after changing LIVEKIT settings. Test devices need LAN access to TCP 7880/7881 and UDP 50000–50100.'
