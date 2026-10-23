# Local development only: adb reverse mappings disappear after USB reconnects.
# One watcher per Windows login; no credentials or app data are accessed.
$mutex = [Threading.Mutex]::new($false, 'Local\PhlioUsbApiBridge')
if (-not $mutex.WaitOne(0)) { $mutex.Dispose(); exit }
try {
    while ($true) {
        foreach ($line in (& adb devices 2>$null)) {
            if ($line -match '^([^\s]+)\s+device$') {
                $serial = $Matches[1]
                $mappings = (& adb -s $serial reverse --list 2>$null) -join "`n"
                foreach ($port in @(8000, 8002)) {
                    if ($mappings -notmatch "tcp:$port\s+tcp:$port") {
                        & adb -s $serial reverse "tcp:$port" "tcp:$port" 2>$null | Out-Null
                    }
                }
            }
        }
        Start-Sleep -Seconds 3
    }
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
