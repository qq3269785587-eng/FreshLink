param([switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
$startupLock = New-Object System.Threading.Mutex($false, 'Local\FreshLinkProjectStartup')
$ownsLock = $false
try {
    try { $ownsLock = $startupLock.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $ownsLock = $true }
    if (!$ownsLock) { Write-Host 'FreshLink startup is already in progress.'; return }
    if ((Get-Service MySQL80).Status -ne 'Running') { throw 'MySQL80 is stopped. Start the existing service first.' }
    if (!(Test-Path -LiteralPath $FreshLinkJar)) { throw 'Backend build is missing. Run scripts\Build-Backend.ps1.' }
    $redisScript = Join-Path $FreshLinkRuntime 'redis\Start-Redis.ps1'
    $redisExe = Join-Path $FreshLinkRuntime 'redis\bin\Redis-7.4.11-Windows-x64-msys2\redis-server.exe'
    $null = Assert-FreshLinkPort -Port 6379 -CommandPath $redisExe
    & $redisScript
    & (Join-Path $PSScriptRoot 'Start-Frontend.ps1')
    if (!(Assert-FreshLinkPort -Port 8080 -CommandPath $FreshLinkRuntimeJar)) {
        $scriptPath = Join-Path $PSScriptRoot 'Start-Backend.ps1'
        $process = Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -WorkingDirectory $FreshLinkRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $FreshLinkLogs 'backend.out.log') -RedirectStandardError (Join-Path $FreshLinkLogs 'backend.err.log') -PassThru
        $process.Id | Set-Content -LiteralPath (Join-Path $FreshLinkRuntime 'run\backend-launcher.pid')
    }
    Write-Host 'Waiting for FreshLink frontend and backend readiness...'
    $deadline = (Get-Date).AddMinutes(5)
    $ready = $false
    do {
        try {
            $frontend = Invoke-WebRequest -Uri 'http://127.0.0.1:3100/' -UseBasicParsing -TimeoutSec 5
            $backend = Invoke-WebRequest -Uri ('http://127.0.0.1:8080/jeecg-boot/sys/randomImage/startup-' + [Guid]::NewGuid().ToString('N')) -UseBasicParsing -TimeoutSec 5
            $result = $backend.Content | ConvertFrom-Json
            $ready = $frontend.StatusCode -eq 200 -and $frontend.Content.Contains('id="app"') -and $backend.StatusCode -eq 200 -and $result.success -eq $true
        } catch { $ready = $false }
        if (!$ready) { Start-Sleep -Seconds 2 }
    } until ($ready -or (Get-Date) -ge $deadline)
    if (!$ready) { throw "FreshLink startup timed out. Check logs in $FreshLinkLogs" }
    Write-Host 'FreshLink is ready: http://127.0.0.1:3100/'
    if (!$NoBrowser) { Start-Process 'http://127.0.0.1:3100/' }
} finally {
    if ($ownsLock) { $startupLock.ReleaseMutex() }
    $startupLock.Dispose()
}
