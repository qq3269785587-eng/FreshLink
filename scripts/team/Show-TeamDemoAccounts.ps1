[CmdletBinding()]
param([string]$CredentialPath='runtime/config/team-demo-accounts.json')
$ErrorActionPreference='Stop'
$path=[IO.Path]::GetFullPath((Join-Path (Get-Location).Path $CredentialPath))
$root=[IO.Path]::GetFullPath((Join-Path (Get-Location).Path 'runtime/config'))+[IO.Path]::DirectorySeparatorChar
if (!$path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'CredentialPath must remain under runtime/config.' }
$data=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
Write-Output "Database: $($data.schema)"
foreach($property in $data.users.PSObject.Properties) {
    $secure=ConvertTo-SecureString ([string]$property.Value)
    $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    [pscustomobject]@{username=$property.Name; password=$plain}
}
