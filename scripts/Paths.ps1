$FreshLinkRoot = Split-Path $PSScriptRoot -Parent
$FreshLinkBackend = Join-Path $FreshLinkRoot 'apps\backend'
$FreshLinkWeb = Join-Path $FreshLinkRoot 'apps\web'
$FreshLinkRuntime = Join-Path $FreshLinkRoot 'runtime'
$FreshLinkConfig = Join-Path $FreshLinkRuntime 'config'
$FreshLinkLogs = Join-Path $FreshLinkRoot 'logs'
$FreshLinkJar = Join-Path $FreshLinkBackend 'jeecg-module-system\jeecg-system-start\target\jeecg-system-start-3.8.1.jar'
$FreshLinkRuntimeJar = Join-Path $FreshLinkRuntime 'run\jeecg-system-start.jar'
$FreshLinkJavaHome = if ($env:FRESHLINK_JAVA_HOME) { $env:FRESHLINK_JAVA_HOME } else { 'D:\Yuki\JAVA\software\jdk-17' }
New-Item -ItemType Directory -Force -Path $FreshLinkLogs,(Join-Path $FreshLinkRuntime 'run') | Out-Null
$env:npm_config_cache = Join-Path $FreshLinkRuntime 'cache\npm-cache'
$env:PNPM_HOME = Join-Path $FreshLinkRuntime 'tools\pnpm-home'

function Assert-FreshLinkPort {
    param([int]$Port, [string]$CommandPath)
    $listener = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
    if (!$listener.Count) { return $false }
    foreach ($listenerPid in ($listener.OwningProcess | Select-Object -Unique)) {
        $listenerProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $listenerPid"
        if (!$listenerProcess -or !$listenerProcess.CommandLine -or $listenerProcess.CommandLine.IndexOf($CommandPath, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            throw "Port $Port belongs to another or unverified process ($listenerPid). Stop that process explicitly before starting FreshLink."
        }
    }
    return $true
}
