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
$root = Resolve-TeamRoot
$configPath = Join-Path $root 'runtime\config\team-private.json'
if (!(Test-Path $configPath)) { throw 'Run scripts/team/Setup-Team.ps1 first.' }
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$pnpm = [string]$config.pnpmPath
$store = Join-Path $root 'runtime\cache\pnpm-store'
New-Item -ItemType Directory -Force -Path $store | Out-Null
Push-Location (Join-Path $root 'apps\web')
try {
    $env:npm_config_cache = Join-Path $root 'runtime/cache/npm-cache'
    & $pnpm install --frozen-lockfile --store-dir $store "--config.cache-dir=$(Join-Path $root 'runtime/cache/pnpm-metadata')" "--config.state-dir=$(Join-Path $root 'runtime/cache/pnpm-state')"
    if ($LASTEXITCODE -ne 0) { throw "pnpm install failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }
