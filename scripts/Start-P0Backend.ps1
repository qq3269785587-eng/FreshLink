param(
    [string]$DatabaseName = 'freshlink_p0_codex_20261117_b'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')

if ($DatabaseName -cne 'freshlink_p0_codex_20261117_b') {
    throw 'Only the newly restored P0 test schema is allowed.'
}
$testConfigPath = Join-Path $FreshLinkConfig 'p0-db-credentials.json'
$testRoot = Join-Path $FreshLinkRuntime 'run\p0'
$testLogs = Join-Path $testRoot 'logs'
$testUpload = Join-Path $FreshLinkRuntime 'data\p0\uploads'
$testWebapp = Join-Path $FreshLinkRuntime 'data\p0\webapp'
$testJar = Join-Path $FreshLinkRuntime 'run\p0\jeecg-system-start.jar'
$launcherPid = Join-Path $FreshLinkRuntime 'run\p0-backend-launcher.pid'
$javaPath = Join-Path $FreshLinkJavaHome 'bin\java.exe'

if (!(Test-Path -LiteralPath $testConfigPath -PathType Leaf)) { throw 'Restricted P0 database credentials are missing. Run Configure-P0TestDbCredentials.ps1 first.' }
if (!(Test-Path -LiteralPath $FreshLinkJar -PathType Leaf)) { throw 'Built backend JAR is missing.' }
if (!(Test-Path -LiteralPath $javaPath -PathType Leaf)) { throw 'JDK 17 is missing.' }
if (Get-NetTCPConnection -State Listen -LocalPort 18080 -ErrorAction SilentlyContinue) { throw 'Port 18080 is already in use; refusing to attach to an unknown process.' }

$databaseConfig = Get-Content -LiteralPath $testConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($databaseConfig.schema -cne $DatabaseName -or $databaseConfig.host -cne '127.0.0.1' -or $databaseConfig.username -cne 'freshlink_p0_app_b' -or !$databaseConfig.password) {
    throw 'P0 database credential file does not match the allowed test schema/account.'
}

New-Item -ItemType Directory -Force -Path $testRoot,$testLogs,$testUpload,$testWebapp | Out-Null
Copy-Item -LiteralPath $FreshLinkJar -Destination $testJar -Force
$env:SPRING_DATASOURCE_DYNAMIC_DATASOURCE_MASTER_USERNAME = $databaseConfig.username
$env:SPRING_DATASOURCE_DYNAMIC_DATASOURCE_MASTER_PASSWORD = $databaseConfig.password
$env:SPRING_DATA_REDIS_DATABASE = '15'
$env:JEECG_REDISSON_ADDRESS = 'redis://127.0.0.1:6379/15'
$env:JEECG_PATH_UPLOAD = $testUpload
$env:JEECG_PATH_WEBAPP = $testWebapp
$env:JAVA_HOME = $FreshLinkJavaHome

try {
    $jdbcUrl = "jdbc:mysql://127.0.0.1:3306/${DatabaseName}?characterEncoding=UTF-8&useUnicode=true&useSSL=false&tinyInt1isBit=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai"
    $arguments = @('-Xms256m','-Xmx1536m','-jar',"`"$testJar`"",'--server.address=127.0.0.1','--server.port=18080','--spring.quartz.auto-startup=false',"--spring.datasource.dynamic.datasource.master.url=$jdbcUrl") -join ' '
    $backend = Start-Process -FilePath $javaPath -ArgumentList $arguments -WorkingDirectory $testRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $testLogs 'backend.out.log') -RedirectStandardError (Join-Path $testLogs 'backend.err.log') -PassThru
    $backend.Id | Set-Content -LiteralPath $launcherPid
    $expectedHash = (Get-FileHash -LiteralPath $FreshLinkJar -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $testJar -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Copied P0 JAR hash does not match the build.' }
    $ready = $false
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        $backend.Refresh()
        if ($backend.HasExited) { throw "P0 backend exited before readiness (exit $($backend.ExitCode)). Inspect local runtime/run/p0/logs; do not share raw auth logs." }
        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort 18080 -ErrorAction SilentlyContinue)
        if ($listeners.Count) {
            if (@($listeners | Where-Object { $_.OwningProcess -ne $backend.Id -or $_.LocalAddress -ne '127.0.0.1' }).Count) {
                throw 'P0 listener identity/address does not match the launched process.'
            }
            $identity = Get-CimInstance Win32_Process -Filter "ProcessId = $($backend.Id)"
            if (!$identity.CommandLine -or $identity.CommandLine.IndexOf($testJar, [StringComparison]::OrdinalIgnoreCase) -lt 0) { throw 'P0 process command line does not match the deployed JAR.' }
            try {
                # Health check avoids creating/logging a captcha value.
                $response = Invoke-WebRequest -Uri 'http://127.0.0.1:18080/jeecg-boot/sys/403' -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
                $ready = $response.StatusCode -eq 200
            } catch {
                # A real HTTP response still proves that the application has finished binding.
                if ($_.Exception.Response) { $ready = $true }
            }
            if ($ready) { break }
        }
        Start-Sleep -Seconds 2
    }
    if (!$ready) { throw 'P0 backend readiness timed out. The process is preserved for diagnosis.' }
    Write-Output "P0 backend ready (PID $($backend.Id)); isolated endpoint http://127.0.0.1:18080/jeecg-boot; database $DatabaseName; Redis DB 15; JAR SHA256 $expectedHash."
}
finally {
    Remove-Item Env:SPRING_DATASOURCE_DYNAMIC_DATASOURCE_MASTER_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:SPRING_DATASOURCE_DYNAMIC_DATASOURCE_MASTER_USERNAME -ErrorAction SilentlyContinue
    Remove-Item Env:SPRING_DATA_REDIS_DATABASE -ErrorAction SilentlyContinue
    Remove-Item Env:JEECG_REDISSON_ADDRESS -ErrorAction SilentlyContinue
    Remove-Item Env:JEECG_PATH_UPLOAD -ErrorAction SilentlyContinue
    Remove-Item Env:JEECG_PATH_WEBAPP -ErrorAction SilentlyContinue
    Remove-Item Env:JAVA_HOME -ErrorAction SilentlyContinue
}
