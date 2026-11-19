# Lets a phone on the same Wi-Fi reach the local Phlio API (ports 8000 / 8002).
#
# Symptom it fixes: the app on a real phone shows
#   SocketException: Connection timed out (errno = 110), address = 192.168.x.x
# while the API is running fine on this PC. A *timeout* (not "refused") means
# Windows Firewall dropped the connection, the PC's IP changed, or the phone
# is on another network.
#
# Run once from an elevated PowerShell:   .\scripts\Allow-PhoneAccess.ps1
#Requires -RunAsAdministrator

$ports = 8000, 8002
$rule = 'Phlio API (LAN)'
if (-not (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $rule -Direction Inbound -Protocol TCP -LocalPort $ports -Action Allow -Profile Private, Domain | Out-Null
    Write-Output "Added firewall rule '$rule' for TCP $($ports -join ', ') (Private / Domain networks)."
} else {
    Write-Output "Firewall rule '$rule' already exists."
}

foreach ($p in Get-NetConnectionProfile) {
    if ($p.NetworkCategory -eq 'Public') {
        Write-Warning ("Network '$($p.Name)' is set to Public, so Windows still blocks the phone. If this is your home Wi-Fi, " +
            "set it to Private in Settings > Network & internet > Wi-Fi > $($p.Name), or run: " +
            "Set-NetConnectionProfile -InterfaceIndex $($p.InterfaceIndex) -NetworkCategory Private")
    }
}

$ips = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -ExpandProperty IPAddress
Write-Output ''
Write-Output "This PC's addresses (use the one on your Wi-Fi):"
foreach ($ip in $ips) {
    Write-Output "  open on the phone:  http://$($ip):8002/health"
    Write-Output "  then run:           flutter run --dart-define=API_BASE_URL=http://$($ip):8002/api/v1"
}
Write-Output ''
Write-Output 'No Wi-Fi luck? Use the USB cable instead (always works):'
Write-Output '  adb reverse tcp:8002 tcp:8002'
Write-Output '  flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8002/api/v1'
