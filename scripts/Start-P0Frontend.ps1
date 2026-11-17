param([int]$Port = 13100)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
if ($Port -ne 13100) { throw 'P0 frontend is restricted to port 13100.' }
$vitePath = Join-Path $FreshLinkWeb 'node_modules\vite\bin\vite.js'
if (Assert-FreshLinkPort -Port $Port -CommandPath $vitePath) {
    throw 'P0 port is already running; verify its backend proxy before reusing it.'
}
$oldProxy = $env:VITE_PROXY
try {
    $env:VITE_PROXY = '[["/jeecgboot","http://127.0.0.1:18080/jeecg-boot"]]'
    $nodePath = (Get-Command node.exe -ErrorAction Stop).Source
    $process = Start-Process -FilePath $nodePath -ArgumentList "`"$vitePath`" --host 127.0.0.1 --port $Port --strictPort" -WorkingDirectory $FreshLinkWeb -WindowStyle Hidden -RedirectStandardOutput (Join-Path $FreshLinkLogs 'p0-frontend.out.log') -RedirectStandardError (Join-Path $FreshLinkLogs 'p0-frontend.err.log') -PassThru
    $process.Id | Set-Content -LiteralPath (Join-Path $FreshLinkRuntime 'run\p0-frontend.pid')
    Write-Host "P0 frontend PID $($process.Id): http://127.0.0.1:$Port/ -> isolated backend 18080"
} finally { $env:VITE_PROXY = $oldProxy }
