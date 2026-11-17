$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
$mysqlExe = 'D:\Yuki\MySQL\bin\mysql.exe'
$lines = Get-Content -LiteralPath (Join-Path $FreshLinkConfig 'mysql-local-credentials.txt')
$userLine = $lines | Where-Object { $_.StartsWith('username=') } | Select-Object -First 1
$passwordLine = $lines | Where-Object { $_.StartsWith('password=') } | Select-Object -First 1
if (!$userLine -or !$passwordLine) { throw 'Local MySQL configuration is incomplete.' }
$dbUser = $userLine.Substring(9)
$env:MYSQL_PWD = $passwordLine.Substring(9)
$evidence = Join-Path $FreshLinkRoot 'work\fresh-acceptance\P0\attempt-01\db'
try {
    foreach ($schema in @('xingchenwms','freshlink_p0_codex_20261117_b')) {
        $query = @"
SELECT '$schema' AS schema_name, COUNT(*) AS inventory_rows,
 SUM(stock_quantity) AS stock, SUM(allocated_quantity) AS allocated, SUM(available_quantity) AS available,
 SUM(stock_quantity <> allocated_quantity + available_quantity) AS unbalanced_rows,
 SUM(stock_quantity - allocated_quantity - available_quantity) AS imbalance,
 SUM(batch_number IS NULL OR batch_number='') AS blank_batch_rows,
 SUM(CASE WHEN batch_number IS NULL OR batch_number='' THEN stock_quantity ELSE 0 END) AS blank_batch_stock
FROM $schema.wms_inventory;
SELECT 'events' AS object_type, COUNT(*) AS object_count FROM information_schema.events WHERE event_schema='$schema'
UNION ALL SELECT 'routines', COUNT(*) FROM information_schema.routines WHERE routine_schema='$schema'
UNION ALL SELECT 'triggers', COUNT(*) FROM information_schema.triggers WHERE trigger_schema='$schema';
"@
        $result = & $mysqlExe --no-defaults --host=127.0.0.1 --user=$dbUser --batch --raw -e $query 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'Read-only P0 inventory audit failed.' }
        $result | Set-Content -LiteralPath (Join-Path $evidence "$schema-audit.tsv") -Encoding utf8
    }
    Write-Output 'Read-only source and isolated inventory audit saved; no business rows changed.'
} finally { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }
