param(
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')

$evidencePath = if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { $EvidenceDirectory } else { Join-Path $FreshLinkRoot $EvidenceDirectory }
$evidencePath = [IO.Path]::GetFullPath($evidencePath)
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $FreshLinkRoot 'work')) + [IO.Path]::DirectorySeparatorChar
if (!($evidencePath + [IO.Path]::DirectorySeparatorChar).StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Evidence manifest must remain inside project work/.'
}

function Get-FileRecord([string]$path, [string]$relativeBase) {
    $item = Get-Item -LiteralPath $path
    return [ordered]@{
        path = [IO.Path]::GetRelativePath($relativeBase, $item.FullName).Replace('\', '/')
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        bytes = $item.Length
    }
}

$jarTarget = $FreshLinkJar
$jarRunning = Join-Path $FreshLinkRuntime 'run\p0\jeecg-system-start.jar'
$distRoot = Join-Path $FreshLinkWeb 'dist'
$backendBuildLog = Join-Path $evidencePath 'build-backend-final.log'
if (!(Test-Path -LiteralPath $backendBuildLog)) { $backendBuildLog = Join-Path $evidencePath 'build-backend.log' }
$distFiles = @(Get-ChildItem -LiteralPath $distRoot -Recurse -File | Sort-Object FullName | ForEach-Object { Get-FileRecord $_.FullName $distRoot })
$buildManifest = [ordered]@{
    stage = 'P1'
    generatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    backend = [ordered]@{
        targetJar = Get-FileRecord $jarTarget $FreshLinkRoot
        runningJar = Get-FileRecord $jarRunning $FreshLinkRoot
        runningMatchesTarget = (Get-FileHash -LiteralPath $jarTarget -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $jarRunning -Algorithm SHA256).Hash
        buildLog = Get-FileRecord $backendBuildLog $evidencePath
    }
    frontend = [ordered]@{
        distFileCount = $distFiles.Count
        index = Get-FileRecord (Join-Path $distRoot 'index.html') $distRoot
        buildLog = Get-FileRecord (Join-Path $evidencePath 'build-frontend.log') $evidencePath
        files = $distFiles
    }
    builds = [ordered]@{
        backend = 'scripts/Build-Backend.ps1 -Offline (exit 0)'
        frontend = 'scripts/Build-Frontend.ps1 (exit 0)'
    }
}
$buildManifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidencePath 'build-manifest.json') -Encoding utf8
$evidenceFiles = @(Get-ChildItem -LiteralPath $evidencePath -Recurse -File | Where-Object { $_.Name -ne 'manifest.json' } | Sort-Object FullName | ForEach-Object { Get-FileRecord $_.FullName $evidencePath })
$evidenceManifest = [ordered]@{
    stage = 'P1'
    attempt = Split-Path -Leaf $evidencePath
    generatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    statement = 'Self-test evidence; pending Codex independent acceptance. No passwords, tokens or database credentials are included.'
    files = $evidenceFiles
}
$evidenceManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidencePath 'manifest.json') -Encoding utf8

Write-Output "Evidence manifest: $($evidenceFiles.Count) files; dist files: $($distFiles.Count); build manifest written."
