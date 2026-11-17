$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (Assert-FreshLinkPort -Port 8080 -CommandPath $FreshLinkRuntimeJar) { Write-Host 'FreshLink backend is already running.'; return }
$credentialPath = Join-Path $FreshLinkConfig 'mysql-local-credentials.txt'
$passwordLine = Get-Content -LiteralPath $credentialPath | Where-Object { $_.StartsWith('password=') } | Select-Object -First 1
if (!$passwordLine) { throw 'Local database password configuration is missing.' }
if (!(Test-Path -LiteralPath $FreshLinkJar)) { throw 'Backend JAR is missing. Run scripts\Build-Backend.ps1 first.' }
if (!(Test-Path -LiteralPath (Join-Path $FreshLinkJavaHome 'bin\java.exe'))) { throw 'JDK 17 is missing. Configure FRESHLINK_JAVA_HOME.' }
$env:SPRING_DATASOURCE_DYNAMIC_DATASOURCE_MASTER_PASSWORD = $passwordLine.Substring(9)
$env:JAVA_HOME = $FreshLinkJavaHome
$env:JEECG_PATH_UPLOAD = Join-Path $FreshLinkRuntime 'data\uploads'
$env:JEECG_PATH_WEBAPP = Join-Path $FreshLinkRuntime 'data\webapp'
New-Item -ItemType Directory -Force -Path $env:JEECG_PATH_UPLOAD,$env:JEECG_PATH_WEBAPP | Out-Null
Copy-Item -LiteralPath $FreshLinkJar -Destination $FreshLinkRuntimeJar -Force
# Existing logback uses ../logs; runtime as cwd keeps application logs in project/logs.
Push-Location $FreshLinkRuntime
try { & (Join-Path $FreshLinkJavaHome 'bin\java.exe') -Xms256m -Xmx1536m -jar $FreshLinkRuntimeJar }
finally { Pop-Location; Remove-Item Env:SPRING_DATASOURCE_DYNAMIC_DATASOURCE_MASTER_PASSWORD -ErrorAction SilentlyContinue }
