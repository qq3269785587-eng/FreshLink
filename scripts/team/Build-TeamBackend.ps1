[CmdletBinding()]
param([switch]$Offline)
$ErrorActionPreference = 'Stop'

function Resolve-TeamRoot {
    $candidate = Get-Item -LiteralPath $PSScriptRoot
    while ($candidate) {
        if ((Test-Path (Join-Path $candidate.FullName 'apps\backend\pom.xml')) -and (Test-Path (Join-Path $candidate.FullName 'apps\web\package.json'))) { return $candidate.FullName }
        $candidate = $candidate.Parent
    }
    throw 'Could not locate FreshLink repository root.'
}
$root = Resolve-TeamRoot
$configPath = Join-Path $root 'runtime\config\team-private.json'
if (!(Test-Path $configPath)) { throw 'Run scripts/team/Setup-Team.ps1 first.' }
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$maven = [string]$config.mavenPath
$repository = Join-Path $root 'runtime\cache\maven-repository'
New-Item -ItemType Directory -Force -Path $repository | Out-Null
$oldJavaHome = $env:JAVA_HOME
$env:JAVA_HOME = [string]$config.javaHome
Push-Location (Join-Path $root 'apps\backend')
try {
    $mavenArgs = @('-s',(Join-Path $root '.mvn/settings.xml'),"-Dmaven.repo.local=$repository", '-pl','jeecg-module-system/jeecg-system-start','-am','package')
    if ($Offline) { $mavenArgs = @('-o') + $mavenArgs }
    & $maven @mavenArgs
    if ($LASTEXITCODE -ne 0) { throw "Backend package failed with exit code $LASTEXITCODE" }
    Write-Host 'Backend package succeeded. The default package skips tests; run scripts/team/Test-Team.ps1 separately.'
} finally {
    Pop-Location
    $env:JAVA_HOME = $oldJavaHome
}
