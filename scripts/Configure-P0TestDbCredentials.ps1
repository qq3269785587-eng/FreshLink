$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')

$databaseName = 'freshlink_p0_codex_20261117_b'
$databaseUser = 'freshlink_p0_app_b'
$databaseHost = '127.0.0.1'
$configPath = Join-Path $FreshLinkConfig 'p0-db-credentials.json'
$credentialsPath = Join-Path $FreshLinkConfig 'mysql-local-credentials.txt'
$mysqlExe = 'D:\Yuki\MySQL\bin\mysql.exe'

if (Test-Path -LiteralPath $configPath) { throw 'Refusing to overwrite existing P0 database credentials.' }
$source = Get-Content -LiteralPath $credentialsPath
$userLine = $source | Where-Object { $_.StartsWith('username=') } | Select-Object -First 1
$passwordLine = $source | Where-Object { $_.StartsWith('password=') } | Select-Object -First 1
if (!$userLine -or !$passwordLine) { throw 'Local MySQL connection configuration is incomplete.' }
$rootUser = $userLine.Substring(9)
$env:MYSQL_PWD = $passwordLine.Substring(9)

function Invoke-RootQuery([string]$Sql) {
    $output = & $mysqlExe --no-defaults --host=127.0.0.1 --user=$rootUser --batch --raw --skip-column-names -e $Sql 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Root MySQL query failed.' }
    return [string]$output
}

try {
    $schemaCount = Invoke-RootQuery "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$databaseName';"
    $tableCount = Invoke-RootQuery "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$databaseName';"
    if ($schemaCount -ne '1' -or $tableCount -ne '148') { throw 'P0 test schema is missing or its restored table count is unexpected.' }
    $userCount = Invoke-RootQuery "SELECT COUNT(*) FROM mysql.user WHERE user='$databaseUser' AND host='$databaseHost';"
    if ($userCount -ne '0') { throw 'Refusing to modify an existing MySQL account.' }

    $randomBytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($randomBytes)
    $appPassword = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+','A').Replace('/','B')
    $sql = "CREATE USER '$databaseUser'@'$databaseHost' IDENTIFIED BY '$appPassword'; GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, SHOW VIEW, TRIGGER, EVENT ON ``$databaseName``.* TO '$databaseUser'@'$databaseHost';"

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = $mysqlExe
    $process.StartInfo.Arguments = "--no-defaults --host=127.0.0.1 --user=$rootUser"
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardInput = $true
    $process.StartInfo.RedirectStandardError = $true
    if (!$process.Start()) { throw 'Could not start MySQL privilege setup.' }
    $errorTask = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.WriteLine($sql)
    $process.StandardInput.Close()
    $process.WaitForExit()
    $sql = $null
    if ($process.ExitCode -ne 0) { throw 'Could not create restricted P0 database credentials.' }

    $null = New-Item -ItemType File -Path $configPath
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'Allow')))
    Set-Acl -LiteralPath $configPath -AclObject $acl

    $credentialObject = [ordered]@{ schema = $databaseName; host = $databaseHost; username = $databaseUser; password = $appPassword }
    $json = ConvertTo-Json -InputObject $credentialObject
    [IO.File]::WriteAllText($configPath, $json, [Text.UTF8Encoding]::new($true))

    if ((Invoke-RootQuery "SELECT COUNT(*) FROM information_schema.schema_privileges WHERE grantee=CONCAT(CHAR(39),'$databaseUser',CHAR(39),'@',CHAR(39),'$databaseHost',CHAR(39)) AND table_schema='$databaseName';") -eq '0') {
        throw 'Restricted account was created but schema grants could not be verified.'
    }
    Write-Output "Restricted P0 database account configured for $databaseName; credentials saved to runtime/config/p0-db-credentials.json with current-user-only ACL."
}
finally {
    $appPassword = $null
    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
}
