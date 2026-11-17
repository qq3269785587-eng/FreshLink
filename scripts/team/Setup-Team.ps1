[CmdletBinding()]
param(
    [string]$JavaHome = $env:FRESHLINK_JAVA_HOME,
    [string]$MavenCommand = $env:FRESHLINK_MAVEN_CMD,
    [string]$NodeCommand,
    [string]$PnpmCommand,
    [Security.SecureString]$RedisPassword,
    [string]$MySqlClientPath,
    [string]$MySqlHost = '127.0.0.1',
    [string]$Schema,
    [string]$DatabaseUser,
    [Security.SecureString]$DatabasePassword,
    [ValidateRange(1,65535)][int]$MySqlPort = 3306,
    [string]$RedisHost = '127.0.0.1',
    [ValidateRange(1,65535)][int]$RedisPort = 6379,
    [ValidateRange(0,15)][int]$RedisDatabase = 14,
    [ValidateRange(1,65535)][int]$BackendPort = 18081,
    [ValidateRange(1,65535)][int]$FrontendPort = 13102
)

$ErrorActionPreference = 'Stop'

function Resolve-TeamRoot {
    $candidate = Get-Item -LiteralPath $PSScriptRoot
    while ($candidate) {
        if ((Test-Path (Join-Path $candidate.FullName 'apps\backend\pom.xml')) -and
            (Test-Path (Join-Path $candidate.FullName 'apps\web\package.json'))) {
            return $candidate.FullName
        }
        $candidate = $candidate.Parent
    }
    throw 'Could not locate the FreshLink repository root (apps/backend and apps/web).'
}

function Resolve-CommandPath([string]$PathOrName, [string]$CommandName, [switch]$Optional) {
    if (![string]::IsNullOrWhiteSpace($PathOrName)) {
        $item = Get-Item -LiteralPath $PathOrName -ErrorAction SilentlyContinue
        if (!$item -or $item.PSIsContainer) { throw "$CommandName path does not exist: $PathOrName" }
        return $item.FullName
    }
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    if ($Optional) { return $null }
    throw "$CommandName was not found. Install it or pass the full path to Setup-Team.ps1."
}

function Test-TcpEndpoint([string]$HostName, [int]$Port, [string]$Label) {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $pending = $client.BeginConnect($HostName, $Port, $null, $null)
        if (!$pending.AsyncWaitHandle.WaitOne(3000, $false)) { throw "$Label did not answer at ${HostName}:$Port." }
        $client.EndConnect($pending)
        if (!$client.Connected) { throw "$Label did not answer at ${HostName}:$Port." }
    } catch {
        throw "$Label is not reachable at ${HostName}:$Port. Start/configure that local service before setup."
    } finally {
        $client.Close()
    }
}

function Set-PrivateAcl([string]$Path) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $isDirectory = Test-Path -LiteralPath $Path -PathType Container
    $acl = if ($isDirectory) { [Security.AccessControl.DirectorySecurity]::new() } else { [Security.AccessControl.FileSecurity]::new() }
    $acl.SetAccessRuleProtection($true, $false)
    $security = if ($isDirectory) {
        [Security.AccessControl.FileSystemAccessRule]::new($identity.User,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    } else { [Security.AccessControl.FileSystemAccessRule]::new($identity.User,'FullControl','Allow') }
    [void]$acl.AddAccessRule($security)
    $grant = if ($isDirectory) { "$($identity.Name):(OI)(CI)F" } else { "$($identity.Name):F" }
    & icacls.exe $Path /inheritance:r /grant:r $grant | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not protect the local private configuration with a user-only ACL.' }
}

function Convert-SecureStringToPlainText([Security.SecureString]$Value) {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

$root = Resolve-TeamRoot
$configPath = Join-Path $root 'runtime\config\team-private.json'
$localEnvPath = Join-Path $root 'apps\web\.env.development.local'
if (Test-Path -LiteralPath $configPath) { throw 'Private team config already exists. Refusing to overwrite local credentials.' }
if (Test-Path -LiteralPath $localEnvPath) { throw 'apps/web/.env.development.local already exists. Back it up manually before setup; this script will not overwrite it.' }

if ([string]::IsNullOrWhiteSpace($JavaHome)) { $JavaHome = Split-Path (Resolve-CommandPath $null 'java.exe') -Parent; $JavaHome = Split-Path $JavaHome -Parent }
if (!(Test-Path (Join-Path $JavaHome 'bin\java.exe'))) { throw 'JavaHome must point to a JDK directory containing bin\java.exe.' }
$javaVersionText = (& (Join-Path $JavaHome 'bin\java.exe') -version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $javaVersionText -notmatch 'version "17(?:\.|"|\+)') { throw 'FreshLink backend requires JDK 17.' }

$mavenPath = Resolve-CommandPath $MavenCommand 'mvn.cmd'
$mavenVersion = (& $mavenPath -v 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'Maven failed its version check.' }
if ([string]::IsNullOrWhiteSpace($NodeCommand)) { $NodeCommand = (Resolve-CommandPath $null 'node.exe') }
if ([string]::IsNullOrWhiteSpace($PnpmCommand)) { $PnpmCommand = (Resolve-CommandPath $null 'pnpm.cmd') }
$nodeVersion = (& $NodeCommand --version | Out-String).Trim()
$nodeMatch = [regex]::Match($nodeVersion, '^v?(\d+)\.(\d+)\.(\d+)')
$nodeMajor = if ($nodeMatch.Success) { [int]$nodeMatch.Groups[1].Value } else { 0 }
$nodeMinor = if ($nodeMatch.Success) { [int]$nodeMatch.Groups[2].Value } else { 0 }
if ($LASTEXITCODE -ne 0 -or !$nodeMatch.Success -or ($nodeMajor -lt 20) -or ($nodeMajor -eq 20 -and $nodeMinor -lt 18)) {
    throw "Node.js 20.18.1 or newer supported major is required by the locked frontend dependencies (found $nodeVersion)."
}
$pnpmVersion = (& $PnpmCommand --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $pnpmVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'pnpm could not report a valid version.' }
if ([version]$pnpmVersion -lt [version]'9.0.0') { throw "pnpm 9 or newer is required for lockfileVersion 9 (found $pnpmVersion)." }

$mysqlClientResolved = Resolve-CommandPath $MySqlClientPath 'mysql.exe' -Optional
if (!$mysqlClientResolved) { throw 'mysql.exe was not found. Install the MySQL command-line client or pass -MySqlClientPath.' }
if (!(Test-Path $mysqlClientResolved)) { throw 'mysql.exe is unavailable.' }
Test-TcpEndpoint $MySqlHost $MySqlPort 'MySQL'
Test-TcpEndpoint $RedisHost $RedisPort 'Redis'

foreach ($port in @($BackendPort,$FrontendPort)) {
    $listener = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
    if ($listener.Count) { throw "FreshLink team port $port is already in use. Choose another port; no process was stopped." }
}
if ($BackendPort -eq $FrontendPort) { throw 'BackendPort and FrontendPort must differ.' }

$schema = if ([string]::IsNullOrWhiteSpace($Schema)) { (Read-Host 'Enter a NEW empty MySQL schema name starting with freshlink_').Trim() } else { $Schema.Trim() }
if ($schema -cnotmatch '^freshlink_[a-z0-9_]{1,40}$' -or $schema -match '^(freshlink_p0|freshlink_prod|freshlink_production)') {
    throw 'Schema must be a freshlink_* name and cannot identify the original business database.'
}
$dbUsername = if ([string]::IsNullOrWhiteSpace($DatabaseUser)) { (Read-Host 'Enter the local application MySQL username scoped to this schema').Trim() } else { $DatabaseUser.Trim() }
if ([string]::IsNullOrWhiteSpace($dbUsername)) { throw 'A local MySQL application username is required.' }
$dbPasswordSecure = if ($DatabasePassword) { $DatabasePassword } else { Read-Host 'Enter that MySQL application password (stored encrypted for this Windows user)' -AsSecureString }
if ($dbPasswordSecure.Length -eq 0) { throw 'A MySQL password is required.' }
$dbPasswordCipher = ConvertFrom-SecureString -SecureString $dbPasswordSecure

$redisPasswordSecure = if ($null -ne $RedisPassword) { $RedisPassword } else { Read-Host 'Redis password, or press Enter if this local Redis has no password' -AsSecureString }
$redisPasswordCipher = if ($redisPasswordSecure.Length -gt 0) { ConvertFrom-SecureString -SecureString $redisPasswordSecure } else { $null }

$privateDirectory = Split-Path $configPath -Parent
New-Item -ItemType Directory -Force -Path $privateDirectory | Out-Null
Set-PrivateAcl $privateDirectory
$config = [ordered]@{
    schema = $schema
    mysql = [ordered]@{ host=$MySqlHost; port=$MySqlPort; username=$dbUsername; passwordCiphertext=$dbPasswordCipher }
    redis = [ordered]@{ host=$RedisHost; port=$RedisPort; database=$RedisDatabase; passwordCiphertext=$redisPasswordCipher }
    backendPort = $BackendPort
    frontendPort = $FrontendPort
    mysqlClientPath = $mysqlClientResolved
    javaHome = [IO.Path]::GetFullPath($JavaHome)
    mavenPath = $mavenPath
    nodePath = $NodeCommand
    pnpmPath = $PnpmCommand
}
$json = $config | ConvertTo-Json -Depth 6
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($configPath, $json, $utf8NoBom)
try { Set-PrivateAcl $configPath }
catch { Remove-Item -LiteralPath $configPath -Force; throw }

$proxy = "[[`"/jeecgboot`",`"http://127.0.0.1:$BackendPort/jeecg-boot`"]]"
$frontendEnv = @(
    'VITE_USE_MOCK=false',
    "VITE_PORT=$FrontendPort",
    "VITE_GLOB_DOMAIN_URL=http://127.0.0.1:${BackendPort}/jeecg-boot",
    'VITE_GLOB_API_URL=/jeecgboot',
    "VITE_PROXY=$proxy"
) -join "`r`n"
[IO.File]::WriteAllText($localEnvPath, $frontendEnv + "`r`n", $utf8NoBom)

$requiredBaseSql = Join-Path $root 'apps\backend\db\team\00_base_schema.sql'
$requiredSeedSql = Join-Path $root 'apps\backend\db\team\01_framework_seed.sql'
if (!(Test-Path $requiredBaseSql) -or !(Test-Path $requiredSeedSql)) {
    Write-Warning 'Team database SQL files are not present yet. The app setup is saved, but wait for the database seed files before initializing a schema.'
}

Write-Host ''
Write-Host 'FreshLink team setup saved for the current Windows account.'
Write-Host "JDK: 17; Maven: $($mavenVersion -split "`r?`n" | Select-Object -First 1)"
Write-Host "Node: $nodeVersion; pnpm: $pnpmVersion; MySQL client: $mysqlClientResolved"
Write-Host "MySQL endpoint: ${MySqlHost}:$MySqlPort/$schema; Redis endpoint: ${RedisHost}:$RedisPort DB $RedisDatabase"
Write-Host "Backend: http://127.0.0.1:$BackendPort/jeecg-boot; frontend: http://127.0.0.1:$FrontendPort/"
Write-Host 'The MySQL schema is not created or changed by setup. Run the reviewed database initializer against this new schema.'
