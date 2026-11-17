[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

function Resolve-TeamRoot {
    $candidate = Get-Item -LiteralPath $PSScriptRoot
    while ($candidate) {
        if ((Test-Path (Join-Path $candidate.FullName 'apps\backend\pom.xml')) -and (Test-Path (Join-Path $candidate.FullName 'apps\web\package.json'))) { return $candidate.FullName }
        $candidate = $candidate.Parent
    }
    throw 'Could not locate FreshLink repository root.'
}
function Convert-CipherToPlain([string]$Cipher) {
    $secure = ConvertTo-SecureString -String $Cipher
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
$root = Resolve-TeamRoot
$configPath = Join-Path $root 'runtime\config\team-private.json'
if (!(Test-Path $configPath)) { throw 'Run scripts/team/Setup-Team.ps1 first.' }
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$module = Join-Path $root 'apps\backend\jeecg-module-system\jeecg-system-start'
$jar = Get-ChildItem -LiteralPath (Join-Path $module 'target') -Filter '*.jar' -File | Where-Object { $_.Name -notmatch 'sources|javadoc|original' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (!$jar) { throw 'Backend jar not found. Run scripts/team/Build-TeamBackend.ps1 first.' }
$env:JAVA_HOME = [string]$config.javaHome
$env:PATH = (Join-Path $config.javaHome 'bin') + [IO.Path]::PathSeparator + $env:PATH
$env:SERVER_PORT = [string]$config.backendPort
$env:SERVER_ADDRESS = '127.0.0.1'
$env:SPRING_FLYWAY_ENABLED = 'false'
$env:SPRING_QUARTZ_AUTO_STARTUP = 'false'
$env:SPRING_DATASOURCE_DYNAMIC_DATASOURCE_MASTER_URL = "jdbc:mysql://$($config.mysql.host):$($config.mysql.port)/$($config.schema)?characterEncoding=UTF-8&useUnicode=true&useSSL=false&tinyInt1isBit=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai"
$env:SPRING_DATASOURCE_DYNAMIC_DATASOURCE_MASTER_USERNAME = [string]$config.mysql.username
$env:SPRING_DATASOURCE_DYNAMIC_DATASOURCE_MASTER_PASSWORD = Convert-CipherToPlain ([string]$config.mysql.passwordCiphertext)
$env:SPRING_DATA_REDIS_HOST = [string]$config.redis.host
$env:SPRING_DATA_REDIS_PORT = [string]$config.redis.port
$env:SPRING_DATA_REDIS_DATABASE = [string]$config.redis.database
$env:JEECG_REDISSON_ADDRESS = "redis://$($config.redis.host):$($config.redis.port)/$($config.redis.database)"
$env:JEECG_PATH_UPLOAD = Join-Path $root 'runtime\uploads'
$env:JEECG_PATH_WEBAPP = Join-Path $root 'runtime\webapp'
if (![string]::IsNullOrWhiteSpace([string]$config.redis.passwordCiphertext)) {
    $redisPassword = Convert-CipherToPlain ([string]$config.redis.passwordCiphertext)
    $env:SPRING_DATA_REDIS_PASSWORD = $redisPassword
    $env:JEECG_REDISSON_PASSWORD = $redisPassword
}
New-Item -ItemType Directory -Force -Path (Join-Path $root 'runtime'),$env:JEECG_PATH_UPLOAD,$env:JEECG_PATH_WEBAPP | Out-Null
Push-Location (Join-Path $root 'runtime')
try { & (Join-Path $config.javaHome 'bin\java.exe') -jar $jar.FullName }
finally {
    Pop-Location
    Remove-Item Env:SPRING_DATASOURCE_DYNAMIC_DATASOURCE_MASTER_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:SPRING_DATA_REDIS_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:JEECG_REDISSON_PASSWORD -ErrorAction SilentlyContinue
}
