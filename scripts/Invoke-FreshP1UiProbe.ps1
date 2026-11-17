param(
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [string]$BaseUrl = 'http://127.0.0.1:13100'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')

$evidencePath = if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { $EvidenceDirectory } else { Join-Path $FreshLinkRoot $EvidenceDirectory }
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $FreshLinkRoot 'work')) + [IO.Path]::DirectorySeparatorChar
if (!([IO.Path]::GetFullPath($evidencePath) + [IO.Path]::DirectorySeparatorChar).StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'UI evidence must remain inside project work/.'
}
New-Item -ItemType Directory -Force -Path (Join-Path $evidencePath 'screenshots') | Out-Null

$node = (Get-Command node.exe -ErrorAction Stop).Source
$oldBase = $env:FRESHLINK_UI_BASE
try {
    $env:FRESHLINK_UI_BASE = $BaseUrl
    & $node (Join-Path $PSScriptRoot 'FreshP1UiProbe.mjs') $evidencePath
    if ($LASTEXITCODE -ne 0) { throw "P1 UI probe failed with exit code $LASTEXITCODE" }
} finally {
    $env:FRESHLINK_UI_BASE = $oldBase
}
Write-Output "P1 UI probe PASS; evidence: $evidencePath"
