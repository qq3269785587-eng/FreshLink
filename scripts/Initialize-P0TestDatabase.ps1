param(
    [string]$DatabaseName = 'freshlink_p0_codex_20261117_b'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')

# P0 restores only to this single, newly named, isolated test database. Never drop it.
if ($DatabaseName -cne 'freshlink_p0_codex_20261117_b') {
    throw 'DatabaseName must be exactly freshlink_p0_codex_20261117_b.'
}

$mysqlExe = 'D:\Yuki\MySQL\bin\mysql.exe'
$dumpExe = 'D:\Yuki\MySQL\bin\mysqldump.exe'
$credentialsPath = Join-Path $FreshLinkConfig 'mysql-local-credentials.txt'
$backupDirectory = Join-Path $FreshLinkRuntime 'backups'
$evidenceDirectory = Join-Path $FreshLinkRoot 'work\fresh-acceptance\P0\attempt-01\db'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dumpPath = Join-Path $backupDirectory "xingchenwms-20261117-codex-p0-$timestamp.sql"
$dumpErr = Join-Path $evidenceDirectory 'mysqldump.stderr.txt'
$mysqlErr = Join-Path $evidenceDirectory 'mysql-restore.stderr.txt'

foreach ($requiredPath in @($mysqlExe, $dumpExe, $credentialsPath)) {
    if (!(Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw "Required local tool/config is missing: $requiredPath" }
}
New-Item -ItemType Directory -Force -Path $backupDirectory,$evidenceDirectory | Out-Null
if (Test-Path -LiteralPath $dumpPath) { throw 'Refusing to overwrite an existing database backup.' }

$credentialLines = Get-Content -LiteralPath $credentialsPath
$passwordLine = $credentialLines | Where-Object { $_.StartsWith('password=') } | Select-Object -First 1
if (!$passwordLine) { throw 'Local MySQL password configuration is missing.' }
$env:MYSQL_PWD = $passwordLine.Substring(9)

function Invoke-MySqlReadOnly {
    param([string]$Sql)
    $output = & $mysqlExe --no-defaults --host=127.0.0.1 --user=root --batch --raw --skip-column-names -e $Sql 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'MySQL read-only query failed; see local MySQL service status.' }
    return @($output)
}

try {
    $exists = [string](Invoke-MySqlReadOnly "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$DatabaseName';")
    if ($exists -ne '0') {
        throw "Refusing to initialize $DatabaseName because it already exists or the existence check was inconclusive. No schema was changed."
    }
    $originalMeta = [string](Invoke-MySqlReadOnly "SELECT default_character_set_name, default_collation_name FROM information_schema.schemata WHERE schema_name='xingchenwms';")
    if ([string]::IsNullOrWhiteSpace($originalMeta)) { throw 'Source database xingchenwms is missing or unavailable.' }
    $charset, $collation = $originalMeta -split "`t", 2
    if ($charset -notmatch '^[a-zA-Z0-9_]+$' -or $collation -notmatch '^[a-zA-Z0-9_]+$') { throw 'Unexpected source database charset/collation.' }

    $beforeTables = [string](Invoke-MySqlReadOnly "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='xingchenwms';")
    $beforeCounts = Invoke-MySqlReadOnly "SELECT table_name FROM information_schema.tables WHERE table_schema='xingchenwms' ORDER BY table_name;"
    $beforeCritical = Invoke-MySqlReadOnly "SELECT CONCAT('sys_user=',COUNT(*)) FROM xingchenwms.sys_user UNION ALL SELECT CONCAT('sys_permission=',COUNT(*)) FROM xingchenwms.sys_permission UNION ALL SELECT CONCAT('sys_dict=',COUNT(*)) FROM xingchenwms.sys_dict UNION ALL SELECT CONCAT('wms_inventory=',COUNT(*)) FROM xingchenwms.wms_inventory UNION ALL SELECT CONCAT('wms_inventory_trans=',COUNT(*)) FROM xingchenwms.wms_inventory_trans UNION ALL SELECT CONCAT('wms_out_orders=',COUNT(*)) FROM xingchenwms.wms_out_orders UNION ALL SELECT CONCAT('wms_products=',COUNT(*)) FROM xingchenwms.wms_products UNION ALL SELECT CONCAT('wms_tasks=',COUNT(*)) FROM xingchenwms.wms_tasks;"
    $schemaDetails = Invoke-MySqlReadOnly "SELECT CONCAT(table_name, '\t', ordinal_position, '\t', column_name, '\t', column_type, '\t', is_nullable) FROM information_schema.columns WHERE table_schema='xingchenwms' AND table_name IN ('wms_inventory','wms_inventory_trans') ORDER BY table_name, ordinal_position;"
    $uniqueKeys = Invoke-MySqlReadOnly "SELECT CONCAT(table_name, '\t', index_name, '\t', GROUP_CONCAT(column_name ORDER BY seq_in_index SEPARATOR ',')) FROM information_schema.statistics WHERE table_schema='xingchenwms' AND table_name IN ('wms_inventory','wms_inventory_trans') AND non_unique=0 GROUP BY table_name,index_name ORDER BY table_name,index_name;"
    $ddl = @(
        (Invoke-MySqlReadOnly 'SHOW CREATE TABLE xingchenwms.wms_inventory;'),
        (Invoke-MySqlReadOnly 'SHOW CREATE TABLE xingchenwms.wms_inventory_trans;')
    )

    $dumpProcess = New-Object System.Diagnostics.Process
    $dumpProcess.StartInfo.FileName = $dumpExe
    $dumpProcess.StartInfo.Arguments = '--no-defaults --host=127.0.0.1 --user=root --default-character-set=utf8mb4 --single-transaction --quick --routines --triggers --events --hex-blob --set-gtid-purged=OFF xingchenwms'
    $dumpProcess.StartInfo.UseShellExecute = $false
    $dumpProcess.StartInfo.CreateNoWindow = $true
    $dumpProcess.StartInfo.RedirectStandardOutput = $true
    $dumpProcess.StartInfo.RedirectStandardError = $true
    if (!$dumpProcess.Start()) { throw 'Could not start mysqldump.' }
    $dumpErrorTask = $dumpProcess.StandardError.ReadToEndAsync()
    $dumpStream = [IO.File]::Open($dumpPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $dumpProcess.StandardOutput.BaseStream.CopyTo($dumpStream) }
    finally { $dumpStream.Dispose() }
    $dumpProcess.WaitForExit()
    $dumpErrorTask.Result | Set-Content -LiteralPath $dumpErr -Encoding utf8
    if ($dumpProcess.ExitCode -ne 0 -or !(Test-Path -LiteralPath $dumpPath) -or (Get-Item -LiteralPath $dumpPath).Length -lt 1024) {
        throw "Database dump failed (exit $($dumpProcess.ExitCode)); source database was not modified. Review local diagnostic output."
    }
    $dumpHash = (Get-FileHash -LiteralPath $dumpPath -Algorithm SHA256).Hash

    $createSql = "CREATE DATABASE ``$DatabaseName`` CHARACTER SET $charset COLLATE $collation;"
    $createOutput = & $mysqlExe --no-defaults --host=127.0.0.1 --user=root --batch -e $createSql 2>$mysqlErr
    if ($LASTEXITCODE -ne 0) { throw 'Creating the new test schema failed; source database was not modified.' }

    $restore = New-Object System.Diagnostics.Process
    $restore.StartInfo.FileName = $mysqlExe
    $restore.StartInfo.Arguments = "--no-defaults --host=127.0.0.1 --user=root --default-character-set=utf8mb4 $DatabaseName"
    $restore.StartInfo.UseShellExecute = $false
    $restore.StartInfo.CreateNoWindow = $true
    $restore.StartInfo.RedirectStandardInput = $true
    $restore.StartInfo.RedirectStandardError = $true
    if (!$restore.Start()) { throw 'Could not start isolated MySQL restore.' }
    $restoreErrorTask = $restore.StandardError.ReadToEndAsync()
    $backupInput = [IO.File]::OpenRead($dumpPath)
    try { $backupInput.CopyTo($restore.StandardInput.BaseStream) }
    finally { $backupInput.Dispose(); $restore.StandardInput.Close() }
    $restore.WaitForExit()
    $restoreErrorTask.Result | Set-Content -LiteralPath $mysqlErr -Encoding utf8
    if ($restore.ExitCode -ne 0) { throw "Restore into isolated database failed (exit $($restore.ExitCode)). Source database was not modified; the isolated schema is preserved for diagnosis and is not safe to use." }

    $afterTables = [string](Invoke-MySqlReadOnly "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='xingchenwms';")
    $restoredTables = [string](Invoke-MySqlReadOnly "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DatabaseName';")
    $afterCounts = Invoke-MySqlReadOnly "SELECT table_name FROM information_schema.tables WHERE table_schema='xingchenwms' ORDER BY table_name;"
    $restoredCounts = Invoke-MySqlReadOnly "SELECT table_name FROM information_schema.tables WHERE table_schema='$DatabaseName' ORDER BY table_name;"
    $afterCritical = Invoke-MySqlReadOnly "SELECT CONCAT('sys_user=',COUNT(*)) FROM xingchenwms.sys_user UNION ALL SELECT CONCAT('sys_permission=',COUNT(*)) FROM xingchenwms.sys_permission UNION ALL SELECT CONCAT('sys_dict=',COUNT(*)) FROM xingchenwms.sys_dict UNION ALL SELECT CONCAT('wms_inventory=',COUNT(*)) FROM xingchenwms.wms_inventory UNION ALL SELECT CONCAT('wms_inventory_trans=',COUNT(*)) FROM xingchenwms.wms_inventory_trans UNION ALL SELECT CONCAT('wms_out_orders=',COUNT(*)) FROM xingchenwms.wms_out_orders UNION ALL SELECT CONCAT('wms_products=',COUNT(*)) FROM xingchenwms.wms_products UNION ALL SELECT CONCAT('wms_tasks=',COUNT(*)) FROM xingchenwms.wms_tasks;"
    $restoredCritical = Invoke-MySqlReadOnly "SELECT CONCAT('sys_user=',COUNT(*)) FROM $DatabaseName.sys_user UNION ALL SELECT CONCAT('sys_permission=',COUNT(*)) FROM $DatabaseName.sys_permission UNION ALL SELECT CONCAT('sys_dict=',COUNT(*)) FROM $DatabaseName.sys_dict UNION ALL SELECT CONCAT('wms_inventory=',COUNT(*)) FROM $DatabaseName.wms_inventory UNION ALL SELECT CONCAT('wms_inventory_trans=',COUNT(*)) FROM $DatabaseName.wms_inventory_trans UNION ALL SELECT CONCAT('wms_out_orders=',COUNT(*)) FROM $DatabaseName.wms_out_orders UNION ALL SELECT CONCAT('wms_products=',COUNT(*)) FROM $DatabaseName.wms_products UNION ALL SELECT CONCAT('wms_tasks=',COUNT(*)) FROM $DatabaseName.wms_tasks;"
    $restoredSchemaDetails = Invoke-MySqlReadOnly "SELECT CONCAT(table_name, '\t', ordinal_position, '\t', column_name, '\t', column_type, '\t', is_nullable) FROM information_schema.columns WHERE table_schema='$DatabaseName' AND table_name IN ('wms_inventory','wms_inventory_trans') ORDER BY table_name, ordinal_position;"
    $restoredUniqueKeys = Invoke-MySqlReadOnly "SELECT CONCAT(table_name, '\t', index_name, '\t', GROUP_CONCAT(column_name ORDER BY seq_in_index SEPARATOR ',')) FROM information_schema.statistics WHERE table_schema='$DatabaseName' AND table_name IN ('wms_inventory','wms_inventory_trans') AND non_unique=0 GROUP BY table_name,index_name ORDER BY table_name,index_name;"

    if ($beforeTables -ne $afterTables -or $afterTables -ne $restoredTables) { throw 'Source/restored table counts differ; inspect evidence before use.' }
    if (($beforeCritical -join "`n") -ne ($afterCritical -join "`n")) { throw 'Source critical row counts changed during backup.' }
    if (($afterCritical -join "`n") -ne ($restoredCritical -join "`n")) { throw 'Source and restored critical row counts differ.' }
    if (($schemaDetails -join "`n") -ne ($restoredSchemaDetails -join "`n")) { throw 'Source and restored inventory schema details differ.' }
    if (($uniqueKeys -join "`n") -ne ($restoredUniqueKeys -join "`n")) { throw 'Source and restored inventory unique keys differ.' }
    if (($beforeCounts -join '|') -ne ($afterCounts -join '|') -or ($afterCounts -join '|') -ne ($restoredCounts -join '|')) { throw 'Source and restored table inventories differ.' }

    $mysqlVersion = [string](Invoke-MySqlReadOnly 'SELECT VERSION();')
    $report = @(
        '# P0 数据库隔离恢复记录',
        '',
        "- 时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')",
        '- 源 schema：xingchenwms（仅只读核对与一致性快照）',
        "- 测试 schema：$DatabaseName（独立新 schema；创建前不存在）",
        "- MySQL 版本：$mysqlVersion",
        "- 源表数：$beforeTables；恢复后：$restoredTables",
        "- 备份文件：$([IO.Path]::GetFileName($dumpPath))（本机私有，未纳入证据包）",
        "- 备份 SHA256：$dumpHash",
        "- mysqldump 退出码：$($dumpProcess.ExitCode)；恢复退出码：$($restore.ExitCode)",
        '- 原业务库前后表数、表名清单、关键系统/库存/单据精确行数一致。',
        '- 不含账号密码、用户字段内容或原始业务行。',
        '',
        '## 关键表精确行数（源库前后相同）',
        '',
        '```text',
        ($beforeCritical -join "`n"),
        '```'
    )
    $report | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'restore-report.md') -Encoding utf8
    $beforeCounts | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'source-table-inventory-before.tsv') -Encoding utf8
    $afterCounts | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'source-table-inventory-after.tsv') -Encoding utf8
    $restoredCounts | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'restored-table-inventory.tsv') -Encoding utf8
    $schemaDetails | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'inventory-schema.tsv') -Encoding utf8
    $uniqueKeys | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'inventory-unique-keys.tsv') -Encoding utf8
    $ddl | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'inventory-show-create.txt') -Encoding utf8
    Write-Output "Restore verified: source=$beforeTables tables, restored=$restoredTables tables; database=$DatabaseName; backup-sha256=$dumpHash"
}
finally {
    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
}

