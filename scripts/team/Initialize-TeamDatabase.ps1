[CmdletBinding()]
param(
    [string]$ConfigPath = 'runtime/config/team-private.json',
    [string]$MysqlPath = 'mysql.exe',
    [string]$PasswordUtilPath = 'apps/backend/jeecg-boot-base-core/src/main/java/org/jeecg/common/util/PasswordUtil.java',
    [string]$AdminUser,
    [Security.SecureString]$AdminPassword
)

$ErrorActionPreference = 'Stop'
$repo = (Get-Location).Path
if (!(Test-Path -LiteralPath (Join-Path $repo 'apps/backend/db/fresh/P1_00_schema.sql'))) {
    throw 'Run this script from the repository root.'
}
$configFullPath = [IO.Path]::GetFullPath((Join-Path $repo $ConfigPath))
$privateConfigRoot = [IO.Path]::GetFullPath((Join-Path $repo 'runtime/config')) + [IO.Path]::DirectorySeparatorChar
if (!$configFullPath.StartsWith($privateConfigRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'ConfigPath must remain under runtime/config.' }
$cfg = Get-Content -LiteralPath $configFullPath -Raw | ConvertFrom-Json
$schema = [string]$cfg.schema
if ($schema -cnotmatch '^freshlink_[a-z0-9_]{1,40}$' -or $schema -ceq 'xingchenwms') { throw 'Schema must be a new name with the freshlink_ prefix.' }
if ($schema -match '^(freshlink_p0|freshlink_prod|freshlink_production)') { throw 'Reserved schema name.' }
if (!$cfg.mysql.host -or !$cfg.mysql.username -or !$cfg.mysql.passwordCiphertext) { throw 'Config must contain MySQL host, username, and DPAPI passwordCiphertext.' }
if ([string]$cfg.mysql.host -cne '127.0.0.1') { throw 'The team database is restricted to MySQL at 127.0.0.1.' }
$appUser = [string]$cfg.mysql.username
if ($appUser -notmatch '^[A-Za-z0-9_]{1,32}$') { throw 'MySQL application username must contain only letters, digits, and underscores.' }
if (!$PSBoundParameters.ContainsKey('MysqlPath') -and $cfg.mysqlClientPath) { $MysqlPath=[string]$cfg.mysqlClientPath }
if (!(Test-Path -LiteralPath $MysqlPath)) { $mysqlCommand = Get-Command $MysqlPath -ErrorAction SilentlyContinue; if (!$mysqlCommand) { throw 'mysql.exe was not found; pass -MysqlPath or configure mysqlClientPath.' }; $MysqlPath=$mysqlCommand.Source }

$adminUser = if ($AdminUser) { $AdminUser } else { Read-Host 'MySQL administrator username' }
if ($appUser -ceq $adminUser) { throw 'Use a distinct application database username and MySQL administrator username.' }
$adminSecure = if ($AdminPassword) { $AdminPassword } else { Read-Host 'MySQL administrator password (not saved)' -AsSecureString }
$adminPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminSecure)
$adminPlainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($adminPtr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($adminPtr)
$appSecure = ConvertTo-SecureString ([string]$cfg.mysql.passwordCiphertext)
$appPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($appSecure)
$appPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($appPtr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($appPtr)
$credPath=Join-Path $repo 'runtime/config/team-demo-accounts.json'
if (Test-Path -LiteralPath $credPath) { throw 'Local team-demo-accounts.json already exists. Move it aside and review it before initializing a different schema.' }
$credentials=[ordered]@{}
$script:teamSchemaReady=$false
$env:MYSQL_PWD = $adminPlainPassword

function Invoke-MySql([string]$sql, [string]$user=$adminUser) {
    if ($script:teamSchemaReady) { $sql = "USE ``$schema``;`n" + $sql }
    $env:MYSQL_PWD = if ($user -ceq $adminUser) { $adminPlainPassword } else { $appPassword }
    $p=[Diagnostics.Process]::new();$p.StartInfo.FileName=$MysqlPath
    foreach($arg in @('--no-defaults',"--host=$($cfg.mysql.host)","--port=$($cfg.mysql.port)","--user=$user",'--default-character-set=utf8mb4','--batch','--raw','--skip-column-names')){$p.StartInfo.ArgumentList.Add($arg)}
    $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.RedirectStandardInput=$true;$p.StartInfo.RedirectStandardOutput=$true;$p.StartInfo.RedirectStandardError=$true
    $p.StartInfo.StandardInputEncoding=[Text.UTF8Encoding]::new($false);$p.StartInfo.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
    if(!$p.Start()){throw 'Could not start mysql.exe.'};$stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync();$p.StandardInput.WriteLine($sql);$p.StandardInput.Close();$p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        $safeError = $stderr.Result.Replace($adminPlainPassword,'[redacted]').Replace($appPassword,'[redacted]')
        throw "MySQL command failed: $safeError"
    }
    return ,@($stdout.Result -split "`r?`n" | Where-Object { $_ -ne '' })
}
function Import-MySqlFile([string]$path) {
    $full = [IO.Path]::GetFullPath((Join-Path $repo $path))
    if (!$full.StartsWith($repo + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'SQL file path escaped repository.' }
    $proc = [Diagnostics.Process]::new()
    $proc.StartInfo.FileName = $MysqlPath
    $proc.StartInfo.ArgumentList.Add('--no-defaults')
    $proc.StartInfo.ArgumentList.Add("--host=$($cfg.mysql.host)")
    $proc.StartInfo.ArgumentList.Add("--port=$($cfg.mysql.port)")
    $proc.StartInfo.ArgumentList.Add("--user=$adminUser")
    $proc.StartInfo.ArgumentList.Add("--database=$schema")
    $proc.StartInfo.ArgumentList.Add('--default-character-set=utf8mb4')
    $proc.StartInfo.UseShellExecute = $false; $proc.StartInfo.CreateNoWindow=$true
    $proc.StartInfo.RedirectStandardInput=$true; $proc.StartInfo.RedirectStandardError=$true
    $proc.StartInfo.StandardInputEncoding=[Text.UTF8Encoding]::new($false)
    if (!$proc.Start()) { throw 'Could not start mysql.exe.' }
    $errTask=$proc.StandardError.ReadToEndAsync()
    $proc.StandardInput.Write([IO.File]::ReadAllText($full,[Text.Encoding]::UTF8)); $proc.StandardInput.Close(); $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) { throw "Import failed for $([IO.Path]::GetFileName($full)); mysql reported: $($errTask.Result)" }
}

try {
    $found = Invoke-MySql "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$schema';"
    if ([string]$found[0] -ne '0') { throw 'Refusing to initialize an existing schema. Use a new schema name; this script never resets a database.' }
    $null=New-Item -ItemType Directory -Force -Path (Split-Path $credPath)
    $null=New-Item -ItemType File -Path $credPath
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl=[Security.AccessControl.FileSecurity]::new();$acl.SetAccessRuleProtection($true,$false)
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity,'FullControl','Allow'));Set-Acl -LiteralPath $credPath -AclObject $acl
    Invoke-MySql "CREATE DATABASE ``$schema`` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;" | Out-Null
    $script:teamSchemaReady=$true
    $files = @(
        'apps/backend/db/team/00_base_schema.sql',
        'apps/backend/db/team/01_framework_seed.sql',
        'apps/backend/db/fresh/P1_00_schema.sql',
        'apps/backend/db/fresh/P1_10_menu_role_dict.sql',
        'apps/backend/db/fresh/P1_20_demo_data.sql',
        'apps/backend/db/fresh/D1_00_warehouse_codes.sql',
        'apps/backend/db/fresh/D2_00_inbound_lots.sql',
        'apps/backend/db/fresh/D3_00_outbound.sql',
        'apps/backend/db/fresh/D3_01_delivery.sql'
    )
    foreach ($file in $files) { Import-MySqlFile $file }

    # Create the configured least-privilege runtime account against this schema only.
    # The password is handled by this process and never written into a script/config.
    $safeSqlPassword = $appPassword.Replace('\','\\').Replace("'","''")
    $appHost='127.0.0.1'
    $userCount=Invoke-MySql "SELECT COUNT(*) FROM mysql.user WHERE user='$appUser' AND host='$appHost';"
    if ([string]$userCount[0] -eq '0') {
        Invoke-MySql "CREATE USER '$appUser'@'$appHost' IDENTIFIED BY '$safeSqlPassword'; GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,ALTER,INDEX,DROP,REFERENCES,CREATE TEMPORARY TABLES,LOCK TABLES ON ``$schema``.* TO '$appUser'@'$appHost';" | Out-Null
    } else {
        $grants=Invoke-MySql "SHOW GRANTS FOR '$appUser'@'$appHost';"
        $grantText=[string]::Join("`n",$grants)
        $nonUsageGrants=@($grants | Where-Object { $_ -match '(?i)^GRANT ' -and $_ -notmatch '(?i)^GRANT USAGE\b' })
        $badScope=@($nonUsageGrants | Where-Object { $_ -notmatch ('(?i)\bON\s+`'+[regex]::Escape($schema)+'`\.\*(?:\s|;|$)') })
        $requiredPrivileges=@('SELECT','INSERT','UPDATE','DELETE','CREATE','ALTER','INDEX','DROP','REFERENCES','CREATE TEMPORARY TABLES','LOCK TABLES')
        $missingPrivileges=@($requiredPrivileges | Where-Object { $grantText -notmatch ('(?i)\b'+[regex]::Escape($_)+'\b') })
        if ($badScope.Count -gt 0 -or $nonUsageGrants.Count -eq 0 -or $missingPrivileges.Count -gt 0) {
            throw 'Existing MySQL account does not have an appropriately scoped grant for this schema. It was not modified; provision a new restricted account.'
        }
        $env:MYSQL_PWD=$appPassword
        $canConnect=& $MysqlPath --no-defaults "--host=$($cfg.mysql.host)" "--port=$($cfg.mysql.port)" "--user=$appUser" --database=$schema --batch --skip-column-names -e 'SELECT 1' 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]$canConnect -ne '1') { throw 'Existing app account cannot connect using the local configured password. It was not modified.' }
    }

    Invoke-MySql "INSERT INTO sys_role (id,role_name,role_code,description,create_by,create_time,tenant_id) VALUES ('freshlink_role_admin','团队管理员','admin','团队本机系统管理员','team-init',NOW(),0); INSERT IGNORE INTO sys_role_permission (id,role_id,permission_id,operate_date) SELECT CONCAT('tadm',SUBSTRING(MD5(CONCAT('freshlink_role_admin','|',p.id)),1,28)),'freshlink_role_admin',p.id,NOW() FROM sys_permission p WHERE p.del_flag=0;" $appUser | Out-Null

    # Generate application-compatible hashes with the project's own PasswordUtil.
    $toolDir=Join-Path $repo 'runtime/tools/team-password-hash'; New-Item -ItemType Directory -Force $toolDir | Out-Null
    $helper=Join-Path $toolDir 'TeamPasswordHash.java'
    $source=@'
import java.io.*; import org.jeecg.common.util.PasswordUtil;
public class TeamPasswordHash { public static void main(String[] a) throws Exception { BufferedReader r=new BufferedReader(new InputStreamReader(System.in,"UTF-8")); System.out.print(PasswordUtil.encrypt(r.readLine(),r.readLine(),r.readLine())); } }
'@
    [IO.File]::WriteAllText($helper,$source,[Text.UTF8Encoding]::new($false))
    $javaHome=$env:JAVA_HOME
    if (!$javaHome) { $javacCmd=Get-Command javac.exe -ErrorAction SilentlyContinue; if (!$javacCmd) { throw 'JAVA_HOME or javac.exe is required to create login accounts.' }; $javaHome=Split-Path (Split-Path $javacCmd.Source) }
    $javac=Join-Path $javaHome 'bin/javac.exe'; $java=Join-Path $javaHome 'bin/java.exe'
    & $javac -encoding UTF-8 -d $toolDir (Join-Path $repo $PasswordUtilPath) $helper
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile PasswordUtil.' }
    $users=@(
        @{name='admin'; display='团队本机管理员'; role='admin'; store=$null},
        @{name='fresh_hq'; display='生鲜总部管理员'; role='fresh_hq'; store=$null},
        @{name='fresh_wh'; display='生鲜仓管'; role='fresh_warehouse'; store=$null},
        @{name='fresh_store_a'; display='门店A用户'; role='fresh_store'; store='A'},
        @{name='fresh_store_b'; display='门店B用户'; role='fresh_store'; store='B'}
    )
    foreach ($u in $users) {
        $pw='Fl-' + [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(18)) + '!'
        $salt=[Guid]::NewGuid().ToString('N').Substring(0,8); $uid=[Guid]::NewGuid().ToString('N')
        $credentials[$u.name]=ConvertFrom-SecureString (ConvertTo-SecureString $pw -AsPlainText -Force)
        $cred=[ordered]@{schema=$schema; generatedAt=(Get-Date).ToString('o'); encryption='Windows DPAPI CurrentUser'; users=$credentials}
        [IO.File]::WriteAllText($credPath,(ConvertTo-Json -Depth 5 $cred),[Text.UTF8Encoding]::new($true))
        $inputText="$($u.name)`n$pw`n$salt`n"
        $hash=($inputText | & $java -cp $toolDir TeamPasswordHash)
        if ($LASTEXITCODE -ne 0 -or !$hash) { throw 'Password hash generation failed.' }
        $roleRows=Invoke-MySql "SELECT id FROM sys_role WHERE role_code='$($u.role)' LIMIT 1;" $appUser
        if (!$roleRows.Count) { throw "Expected role missing: $($u.role)" }
        $rid=[string]$roleRows[0]
        $safeHash=([string]$hash).Replace("'","''")
        $sql=@"
INSERT INTO sys_user (id,username,realname,password,salt,org_code,status,del_flag,create_by,create_time,login_tenant_id)
VALUES ('$uid','$($u.name)','$($u.display)','$safeHash','$salt','FRESH.ORG',1,0,'team-init',NOW(),0);
INSERT INTO sys_user_depart (ID,user_id,dep_id) VALUES (REPLACE(UUID(),'-',''),'$uid','freshlink_team_org');
INSERT INTO sys_user_role (id,user_id,role_id,tenant_id) VALUES (REPLACE(UUID(),'-',''),'$uid','$rid',0);
"@
        # Invoke SQL over stdin to avoid exposing generated hashes in process arguments.
        $p=[Diagnostics.Process]::new(); $p.StartInfo.FileName=$MysqlPath
        $env:MYSQL_PWD=$appPassword
        foreach($arg in @('--no-defaults',"--host=$($cfg.mysql.host)","--port=$($cfg.mysql.port)","--user=$appUser","--database=$schema",'--default-character-set=utf8mb4')){$p.StartInfo.ArgumentList.Add($arg)}
        $p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.RedirectStandardInput=$true;$p.StartInfo.RedirectStandardError=$true
        $p.StartInfo.StandardInputEncoding=[Text.UTF8Encoding]::new($false); if(!$p.Start()){throw 'mysql failed to start.'}; $et=$p.StandardError.ReadToEndAsync();$p.StandardInput.WriteLine($sql);$p.StandardInput.Close();$p.WaitForExit();if($p.ExitCode -ne 0){throw ('Could not create a local account: '+$et.Result.Replace($safeHash,'[redacted]').Replace($pw,'[redacted]').Replace($appPassword,'[redacted]'))}
        if ($u.store) { Invoke-MySql "INSERT INTO fresh_user_store (id,user_id,store_id,create_by,create_time) SELECT REPLACE(UUID(),'-',''),'$uid',id,'team-init',NOW() FROM fresh_store WHERE store_code='$($u.store)';" $appUser | Out-Null }
    }
    Write-Output "Team database initialized: $schema. Local account passwords are in runtime/config/team-demo-accounts.json; keep this ignored file private."
}
finally {
    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
    $adminPlainPassword=$null;$appPassword=$null
}
