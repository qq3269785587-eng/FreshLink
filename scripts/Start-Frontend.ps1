$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
$vitePath = Join-Path $FreshLinkWeb 'node_modules\vite\bin\vite.js'
if (Assert-FreshLinkPort -Port 3100 -CommandPath $vitePath) { Write-Host 'FreshLink frontend is already running.'; return }
if (!(Test-Path -LiteralPath $vitePath)) { throw 'Vite dependency is missing; inspect the project dependency setup.' }
$nodePath = (Get-Command node.exe -ErrorAction Stop).Source
$process = Start-Process -FilePath $nodePath -ArgumentList "`"$vitePath`" --host 127.0.0.1 --port 3100 --strictPort" -WorkingDirectory $FreshLinkWeb -WindowStyle Hidden -RedirectStandardOutput (Join-Path $FreshLinkLogs 'frontend.out.log') -RedirectStandardError (Join-Path $FreshLinkLogs 'frontend.err.log') -PassThru
$process.Id | Set-Content -LiteralPath (Join-Path $FreshLinkRuntime 'run\frontend.pid')
Write-Host 'FreshLink frontend is starting at http://127.0.0.1:3100/'
