[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EvidenceDirectory)
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
$evidencePath = if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { [IO.Path]::GetFullPath($EvidenceDirectory) } else { [IO.Path]::GetFullPath((Join-Path $root $EvidenceDirectory)) }
$workRoot = [IO.Path]::GetFullPath((Join-Path $root 'work')) + [IO.Path]::DirectorySeparatorChar
if (!$evidencePath.StartsWith($workRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence must be stored under repository work/.' }
if (Test-Path $evidencePath) { throw 'Evidence directory already exists. Choose a new path; existing evidence is never overwritten.' }
$backendEvidence = Join-Path $evidencePath 'backend'
$frontendEvidence = Join-Path $evidencePath 'frontend'
New-Item -ItemType Directory -Force -Path $backendEvidence,$frontendEvidence | Out-Null

$maven = [string]$config.mavenPath
$repository = Join-Path $root 'runtime\cache\maven-repository'
$oldJavaHome = $env:JAVA_HOME
$env:JAVA_HOME = [string]$config.javaHome
Push-Location (Join-Path $root 'apps\backend')
try {
    $arguments = @('-s',(Join-Path $root '.mvn/settings.xml'),"-Dmaven.repo.local=$repository",'-Pp0-tests','-pl','jeecg-module-wms','-am','test')
    & $maven @arguments *> (Join-Path $backendEvidence 'maven-tests.log')
    $backendExitCode = $LASTEXITCODE
    if ($backendExitCode -ne 0) { throw "Fresh backend test whitelist failed with exit code $backendExitCode" }
} finally { Pop-Location; $env:JAVA_HOME = $oldJavaHome }

$pnpm = [string]$config.pnpmPath
Push-Location (Join-Path $root 'apps\web')
try {
    & $pnpm run fresh:test *> (Join-Path $frontendEvidence 'frontend-tests.log')
    $frontendExitCode = $LASTEXITCODE
    if ($frontendExitCode -ne 0) { throw "Frontend fresh:test failed with exit code $frontendExitCode" }
} finally { Pop-Location }

$backendLog = Get-Content -LiteralPath (Join-Path $backendEvidence 'maven-tests.log') -Raw
$summaries = [regex]::Matches($backendLog,'Tests run: (\d+), Failures: (\d+), Errors: (\d+), Skipped: (\d+)')
$summary = if ($summaries.Count) { $summaries[$summaries.Count - 1] } else { [regex]::Match('','never') }
$frontendLog = Get-Content -LiteralPath (Join-Path $frontendEvidence 'frontend-tests.log') -Raw
$frontendSummary = [regex]::Match($frontendLog,'Tests:\s*(\d+)\s+passed')
@"
# Local fresh test run

- Backend command: Maven `-Pp0-tests -pl jeecg-module-wms -am test`
- Backend exit code: $backendExitCode
- Backend test summary: $(if ($summary.Success) { $summary.Value } else { 'summary not parsed; inspect backend/maven-tests.log' })
- Frontend command: `pnpm run fresh:test`
- Frontend exit code: $frontendExitCode
- Frontend summary: $(if ($frontendSummary.Success) { $frontendSummary.Value } else { 'summary not parsed; inspect frontend/frontend-tests.log' })
- Evidence contains test logs only. Do not add passwords, session tokens, or raw local database credentials.
"@ | Set-Content -LiteralPath (Join-Path $evidencePath 'results.md') -Encoding UTF8
Write-Host "Fresh tests passed. Evidence: $evidencePath"
