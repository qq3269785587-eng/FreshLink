param([switch]$Offline)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
$maven = if ($env:FRESHLINK_MAVEN_CMD) { $env:FRESHLINK_MAVEN_CMD } else { 'D:\Yuki\JAVA\software\idea\IntelliJ IDEA Community Edition 2025.2.2\plugins\maven\lib\maven3\bin\mvn.cmd' }
if (!(Test-Path -LiteralPath $maven)) { throw 'Configure FRESHLINK_MAVEN_CMD with the Maven executable path.' }
$env:JAVA_HOME = $FreshLinkJavaHome
$settings = Join-Path $FreshLinkConfig 'maven-report-settings.xml'
$repository = Join-Path $FreshLinkRuntime 'cache\maven-repository'
$mavenArguments = @('-s', $settings, "-Dmaven.repo.local=$repository", '-pl', 'jeecg-module-system/jeecg-system-start', '-am', 'package')
if ($Offline) { $mavenArguments = @('-o') + $mavenArguments }
Push-Location $FreshLinkBackend
try {
    & $maven @mavenArguments
    if ($LASTEXITCODE -ne 0) { throw "Maven failed with exit code $LASTEXITCODE" }
    Write-Host 'Backend package complete. The existing POM skips tests; this is not business-test acceptance.'
} finally { Pop-Location }
