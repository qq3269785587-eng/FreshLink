param(
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [string]$DatabaseName = 'freshlink_p0_codex_20261117_b'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')

if ($DatabaseName -cne 'freshlink_p0_codex_20261117_b') {
    throw 'Only the isolated FreshLink test schema is allowed.'
}
$evidencePath = if ([IO.Path]::IsPathRooted($EvidenceDirectory)) {
    $EvidenceDirectory
} else {
    Join-Path $FreshLinkRoot $EvidenceDirectory
}
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $FreshLinkRoot 'work')) + [IO.Path]::DirectorySeparatorChar
if (!([IO.Path]::GetFullPath($evidencePath) + [IO.Path]::DirectorySeparatorChar).StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Migration evidence must remain inside project work/.'
}
if (Test-Path -LiteralPath (Join-Path $evidencePath 'migration-summary.json')) {
    throw 'Refusing to overwrite existing migration evidence; use a new attempt directory.'
}
New-Item -ItemType Directory -Force -Path $evidencePath | Out-Null

$config = Get-Content -LiteralPath (Join-Path $FreshLinkConfig 'p0-db-credentials.json') -Raw | ConvertFrom-Json
if ($config.schema -cne $DatabaseName -or $config.host -cne '127.0.0.1' -or $config.username -cne 'freshlink_p0_app_b' -or !$config.password) {
    throw 'Isolated database configuration does not match the allowed test schema/account.'
}
$mysql = 'D:\Yuki\MySQL\bin\mysql.exe'
$sqlDirectory = Join-Path $FreshLinkBackend 'db\fresh'
$sqlFiles = @('P1_00_schema.sql', 'P1_10_menu_role_dict.sql', 'P1_20_demo_data.sql')
$env:MYSQL_PWD = [string]$config.password

function Invoke-Sql([string]$sql) {
    $output = & $mysql --no-defaults --host=127.0.0.1 --port=3306 "--user=$($config.username)" "--database=$DatabaseName" --batch --raw --skip-column-names -e $sql 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Isolated SQL query failed: $sql" }
    return ,@($output)
}

function Get-Metrics {
    $hasFresh = ((Invoke-Sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name='fresh_supplier';")[0] -eq '1')
    $lines = [System.Collections.Generic.List[string]]::new()
    $baseQuery = @"
SELECT CONCAT('tables=', COUNT(*)) FROM information_schema.tables WHERE table_schema=DATABASE();
SELECT CONCAT('fresh_tables=', COUNT(*)) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name LIKE 'fresh_%';
SELECT CONCAT('menus=', COUNT(*)) FROM sys_permission WHERE id LIKE 'fresh_p1_%' AND del_flag=0;
SELECT CONCAT('roles=', COUNT(*)) FROM sys_role WHERE id LIKE 'fresh_p1_role_%';
SELECT CONCAT('dicts=', COUNT(*)) FROM sys_dict WHERE id LIKE 'fresh_p1_dict_%';
SELECT CONCAT('dict_items=', COUNT(*)) FROM sys_dict_item WHERE id LIKE 'fresh_p1_di_%';
SELECT CONCAT('outorder_menus=', COUNT(*)) FROM sys_permission WHERE url LIKE '/outorder%' AND del_flag=0;
SELECT CONCAT('fresh_role_grant_dupes=', COUNT(*)) FROM (SELECT role_id, permission_id FROM sys_role_permission WHERE role_id LIKE 'fresh_p1_role_%' GROUP BY role_id, permission_id HAVING COUNT(*)>1) d;
"@
    foreach ($line in (Invoke-Sql $baseQuery)) { $lines.Add([string]$line) }
    if ($hasFresh) {
        $freshQuery = @"
SELECT CONCAT('suppliers=', COUNT(*)) FROM fresh_supplier;
SELECT CONCAT('stores=', COUNT(*)) FROM fresh_store;
SELECT CONCAT('bindings=', COUNT(*)) FROM fresh_user_store;
SELECT CONCAT('demo_products=', COUNT(*)) FROM wms_products WHERE id IN ('fresh_p1_product_x','fresh_p1_product_y');
SELECT CONCAT('demo_zones=', COUNT(*)) FROM wms_storage_zones WHERE id LIKE 'fresh_p1_zone_%';
SELECT CONCAT('demo_locations=', COUNT(*)) FROM wms_storage_locations WHERE id LIKE 'fresh_p1_loc_%';
SELECT CONCAT('migration_ledger=', COUNT(*)) FROM fresh_schema_migration;
SELECT CONCAT('product_x_storage=', IFNULL(MAX(storage_type),'MISSING')) FROM wms_products WHERE id='fresh_p1_product_x';
SELECT CONCAT('product_x_near_expiry=', IFNULL(MAX(near_expiry_days),'MISSING')) FROM wms_products WHERE id='fresh_p1_product_x';
SELECT CONCAT('zone_cold_storage=', IFNULL(MAX(storage_type),'MISSING')) FROM wms_storage_zones WHERE id='fresh_p1_zone_cold';
"@
        foreach ($line in (Invoke-Sql $freshQuery)) { $lines.Add([string]$line) }
    } else {
        foreach ($key in 'suppliers','stores','bindings','demo_products','demo_zones','demo_locations','migration_ledger','product_x_storage','product_x_near_expiry','zone_cold_storage') {
            $lines.Add("$key=-")
        }
    }
    $map = [ordered]@{}
    foreach ($line in $lines) {
        $parts = $line.Split('=', 2)
        if ($parts.Count -eq 2) { $map[$parts[0]] = $parts[1] }
    }
    return $map
}

function Save-Metrics([string]$name, $metrics) {
    $path = Join-Path $evidencePath $name
    $metrics.GetEnumerator() | ForEach-Object { "$($_.Key)`t$($_.Value)" } | Set-Content -LiteralPath $path -Encoding utf8
}

function Invoke-SqlFile([string]$file, [string]$logName) {
    $stdout = Join-Path $evidencePath $logName
    $stderr = Join-Path $evidencePath ($logName -replace '\.log$', '.stderr.log')
    $arguments = @('--no-defaults', '--host=127.0.0.1', '--port=3306', "--user=$($config.username)",
        "--database=$DatabaseName", '--default-character-set=utf8mb4', '--batch')
    $process = Start-Process -FilePath $mysql -ArgumentList $arguments -RedirectStandardInput (Join-Path $sqlDirectory $file) `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru -NoNewWindow
    return [pscustomobject]@{ file = $file; exitCode = $process.ExitCode; stdout = $stdout; stderr = $stderr }
}

try {
    $initialBeforeFile = Join-Path $evidencePath 'db-metrics-before-initial.tsv'
    if (Test-Path -LiteralPath $initialBeforeFile) {
        $before = [ordered]@{}
        Get-Content -LiteralPath $initialBeforeFile | ForEach-Object {
            $parts = ([string]$_).Split("`t", 2)
            if ($parts.Count -eq 2) { $before[$parts[0]] = $parts[1] }
        }
    } else {
        $before = Get-Metrics
    }
    Save-Metrics 'db-metrics-before.tsv' $before

    $runs = @()
    foreach ($pass in 1, 2) {
        foreach ($file in $sqlFiles) {
            $result = Invoke-SqlFile $file ("migration-pass{0}-{1}.log" -f $pass, ($file -replace '\.sql$', ''))
            $runs += [pscustomobject]@{ pass = $pass; file = $file; exitCode = $result.exitCode }
            if ($result.exitCode -ne 0) {
                throw "Migration $file failed on pass $pass (exit $($result.exitCode)); see $($result.stderr)"
            }
        }
        # Capture immediately after each pass, before executing the next pass.
        if ($pass -eq 1) {
            $afterPass1 = Get-Metrics
            Save-Metrics 'db-metrics-pass1.tsv' $afterPass1
        } else {
            $afterPass2 = Get-Metrics
            Save-Metrics 'db-metrics-final.tsv' $afterPass2
        }
    }

    $problems = @()
    $expected = @{
        fresh_tables   = '4'
        menus          = '17'
        roles          = '3'
        dicts          = '2'
        dict_items     = '5'
        suppliers      = '2'
        stores         = '2'
        demo_products  = '2'
        demo_zones     = '5'
        demo_locations = '6'
        fresh_role_grant_dupes = '0'
        migration_ledger = '3'
        product_x_storage = 'CHILLED'
        product_x_near_expiry = '3'
        zone_cold_storage = 'CHILLED'
    }
    foreach ($key in $expected.Keys) {
        if ($afterPass2[$key] -ne $expected[$key]) {
            $problems += "$key expected $($expected[$key]) but was $($afterPass2[$key])"
        }
    }
    if ($before['outorder_menus'] -ne $afterPass2['outorder_menus']) {
        $problems += "existing outorder menus changed: $($before['outorder_menus']) -> $($afterPass2['outorder_menus'])"
    }
    foreach ($key in $afterPass1.Keys) {
        if ($afterPass1[$key] -ne $afterPass2[$key]) {
            $problems += "rerun changed ${key}: $($afterPass1[$key]) -> $($afterPass2[$key])"
        }
    }
    if ($problems.Count -gt 0) {
        throw ('Migration verification failed: ' + ($problems -join '; '))
    }

    $summary = [ordered]@{
        database = $DatabaseName
        executedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        sqlFiles = $sqlFiles
        runs = $runs
        before = $before
        afterPass1 = $afterPass1
        after = $afterPass2
        rerunIdempotent = $true
        oldOutorderMenuCount = $afterPass2['outorder_menus']
        conclusion = 'PASS'
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidencePath 'migration-summary.json') -Encoding utf8

    $md = @(
        '# P1 database migration evidence',
        '',
        "- Database: ``$DatabaseName`` (isolated test schema; no original business database touched)",
        "- Executed: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) (Asia/Shanghai)",
        "- SQL: $($sqlFiles -join ', ') executed twice (pass 1 and pass 2)",
        "- Pre-run metrics: ``db-metrics-before.tsv`` (this may already be an upgraded database; no claim of initial upgrade)",
        "- All SQL exit codes: $((($runs | ForEach-Object { "pass$($_.pass)/$($_.file)=$($_.exitCode)" }) -join ', '))",
        "- Re-run idempotent: yes (all tracked counts identical between pass 1 and pass 2)",
        "- Existing outorder menus before/after: $($before['outorder_menus']) / $($afterPass2['outorder_menus'])",
        "- role-permission duplicates (FreshLink roles): $($afterPass2['fresh_role_grant_dupes'])",
        '',
        '| metric | before | after |',
        '|---|---:|---:|'
    )
    foreach ($key in $afterPass2.Keys) {
        $beforeValue = if ($before.Contains($key)) { $before[$key] } else { '-' }
        $md += "| $key | $beforeValue | $($afterPass2[$key]) |"
    }
    $md += ''
    $md += 'Conclusion: PASS'
    $md | Set-Content -LiteralPath (Join-Path $evidencePath 'migration.md') -Encoding utf8
    Write-Output "P1 migration PASS; evidence: $evidencePath"
}
finally {
    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
}
