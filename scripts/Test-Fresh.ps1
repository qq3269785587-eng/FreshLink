param(
    [string]$EvidenceDirectory = 'work\fresh-acceptance\P0\attempt-01\tests'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')

$evidencePath = if ([IO.Path]::IsPathRooted($EvidenceDirectory)) {
    $EvidenceDirectory
} else {
    Join-Path $FreshLinkRoot $EvidenceDirectory
}
$backendEvidence = Join-Path $evidencePath 'backend'
$frontendEvidence = Join-Path $evidencePath 'frontend'
New-Item -ItemType Directory -Force -Path $backendEvidence, $frontendEvidence | Out-Null

$maven = if ($env:FRESHLINK_MAVEN_CMD) {
    $env:FRESHLINK_MAVEN_CMD
} else {
    'D:\Yuki\JAVA\software\idea\IntelliJ IDEA Community Edition 2025.2.2\plugins\maven\lib\maven3\bin\mvn.cmd'
}
if (!(Test-Path -LiteralPath $maven)) { throw 'Configure FRESHLINK_MAVEN_CMD with the Maven executable path.' }
$env:JAVA_HOME = $FreshLinkJavaHome
$settings = Join-Path $FreshLinkConfig 'maven-report-settings.xml'
$repository = Join-Path $FreshLinkRuntime 'cache\maven-repository'
$backendLog = Join-Path $backendEvidence 'maven-p0-tests.log'
$frontendLog = Join-Path $frontendEvidence 'jest-p0-tests.log'
$backendStdout = Join-Path $backendEvidence 'maven-p0-tests.stdout.log'
$backendStderr = Join-Path $backendEvidence 'maven-p0-tests.stderr.log'
$frontendStdout = Join-Path $frontendEvidence 'jest-p0-tests.stdout.log'
$frontendStderr = Join-Path $frontendEvidence 'jest-p0-tests.stderr.log'

Push-Location $FreshLinkBackend
try {
    $mavenArguments = @('-o', '-s', $settings, "-Dmaven.repo.local=$repository", '-Pp0-tests', '-pl', 'jeecg-module-wms', '-am', 'test')
    Write-Host "Running backend P0 suite; log: $backendLog"
    $backendProcess = Start-Process -FilePath $maven -ArgumentList $mavenArguments -Wait -PassThru -NoNewWindow -RedirectStandardOutput $backendStdout -RedirectStandardError $backendStderr
    $backendExitCode = $backendProcess.ExitCode
    Get-Content @($backendStdout, $backendStderr) -ErrorAction SilentlyContinue | Set-Content -LiteralPath $backendLog -Encoding UTF8
    Get-Content $backendLog -Tail 35
    if ($backendExitCode -ne 0) { throw "Backend P0 tests failed with exit code $backendExitCode" }
} finally {
    Pop-Location
}

Push-Location $FreshLinkWeb
try {
    Write-Host "Running frontend P0 suite; log: $frontendLog"
    $npm = (Get-Command npm.cmd -ErrorAction Stop).Source
    $frontendProcess = Start-Process -FilePath $npm -ArgumentList @('run', 'fresh:test') -Wait -PassThru -NoNewWindow -RedirectStandardOutput $frontendStdout -RedirectStandardError $frontendStderr
    $frontendExitCode = $frontendProcess.ExitCode
    Get-Content @($frontendStdout, $frontendStderr) -ErrorAction SilentlyContinue | Set-Content -LiteralPath $frontendLog -Encoding UTF8
    Get-Content $frontendLog -Tail 20
    if ($frontendExitCode -ne 0) { throw "Frontend P0 tests failed with exit code $frontendExitCode" }
} finally {
    Pop-Location
}

Write-Host 'FreshLink P0 automated suites passed.'
