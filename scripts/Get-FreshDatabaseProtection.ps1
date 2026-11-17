param([Parameter(Mandatory=$true)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
$destination=[IO.Path]::GetFullPath((Join-Path $FreshLinkRoot $EvidenceDirectory))
$allowed=[IO.Path]::GetFullPath((Join-Path $FreshLinkRoot 'work'))+[IO.Path]::DirectorySeparatorChar
if(!($destination+[IO.Path]::DirectorySeparatorChar).StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Output must be in work'}
if(Test-Path (Join-Path $destination 'business-checksums.tsv')){throw 'Refusing to overwrite evidence'}
New-Item -ItemType Directory -Force $destination|Out-Null
$lines=Get-Content (Join-Path $FreshLinkConfig 'mysql-local-credentials.txt')
$dbUser=($lines|Where-Object {$_.StartsWith('username=')}|Select-Object -First 1).Substring(9)
$previous=$env:MYSQL_PWD
try {
 $env:MYSQL_PWD=($lines|Where-Object {$_.StartsWith('password=')}|Select-Object -First 1).Substring(9)
 $mysql='D:\Yuki\MySQL\bin\mysql.exe'
 $tables=& $mysql --no-defaults --host=127.0.0.1 --user=$dbUser --batch --raw --skip-column-names -e "SELECT CONCAT(TABLE_SCHEMA,'.',TABLE_NAME) FROM information_schema.tables WHERE TABLE_SCHEMA IN ('xingchenwms','freshlink_p0_codex_20261117_b') AND TABLE_TYPE='BASE TABLE' AND (LEFT(TABLE_NAME,4)='wms_' OR LEFT(TABLE_NAME,6)='fresh_') ORDER BY TABLE_SCHEMA,TABLE_NAME;" 2>$null
 if($LASTEXITCODE -ne 0 -or !$tables){throw 'Read-only table enumeration failed'}
 $sql='CHECKSUM TABLE '+($tables -join ',')+' EXTENDED;'
 & $mysql --no-defaults --host=127.0.0.1 --user=$dbUser --batch --raw -e $sql 2>$null | Set-Content (Join-Path $destination 'business-checksums.tsv')
 if($LASTEXITCODE -ne 0){throw 'Read-only checksum failed'}
 @{checkedAt=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss');tableCount=@($tables).Count;scope='All wms_ and fresh_ base tables in original and isolated schema; read-only CHECKSUM TABLE EXTENDED; excludes system/login logs and Redis';sql=$sql}|ConvertTo-Json|Set-Content (Join-Path $destination 'scope.json')
 Write-Output "Read-only business table checksums captured: $(@($tables).Count) tables"
} finally {$env:MYSQL_PWD=$previous}
