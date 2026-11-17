$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')

$databaseName = 'freshlink_p0_codex_20261117_b'
$appUsername = 'freshlink_p0_app_b'
$testUsername = 'p0_demo'
$testPassword = $env:FRESHLINK_P0_DEMO_PASSWORD
if ([string]::IsNullOrWhiteSpace($testPassword)) { throw "Set FRESHLINK_P0_DEMO_PASSWORD locally; historical P0 probes are not team bootstrap scripts." }
$testLoginPath = Join-Path $FreshLinkConfig 'p0-test-login.json'
$rootCredentialsPath = Join-Path $FreshLinkConfig 'mysql-local-credentials.txt'
$mysqlExe = 'D:\Yuki\MySQL\bin\mysql.exe'
$javaExe = Join-Path $FreshLinkJavaHome 'bin\java.exe'
$javacExe = Join-Path $FreshLinkJavaHome 'bin\javac.exe'
$toolDir = Join-Path $FreshLinkRoot 'work\fresh-acceptance\P0\attempt-01\tools\p0-password-hash'
$utilitySource = Join-Path $FreshLinkBackend 'jeecg-boot-base-core\src\main\java\org\jeecg\common\util\PasswordUtil.java'

if (Test-Path -LiteralPath $testLoginPath) { throw 'Refusing to overwrite existing P0 demo login configuration.' }
$rootConfig = Get-Content -LiteralPath $rootCredentialsPath
$rootUserLine = $rootConfig | Where-Object { $_.StartsWith('username=') } | Select-Object -First 1
$rootPasswordLine = $rootConfig | Where-Object { $_.StartsWith('password=') } | Select-Object -First 1
if (!$rootUserLine -or !$rootPasswordLine) { throw 'Local MySQL root configuration is incomplete.' }
$rootUsername = $rootUserLine.Substring(9)
$env:MYSQL_PWD = $rootPasswordLine.Substring(9)

function Invoke-RootQuery([string]$Sql) {
    $output = & $mysqlExe --no-defaults --host=127.0.0.1 --user=$rootUsername --batch --raw --skip-column-names -e $Sql 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'MySQL verification query failed.' }
    return $output
}

try {
    $schemaExists = [string](Invoke-RootQuery "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='$databaseName';")
    $tableCount = [string](Invoke-RootQuery "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$databaseName';")
    $adminCount = [string](Invoke-RootQuery "SELECT COUNT(*) FROM $databaseName.sys_user WHERE username='admin' AND status=1 AND del_flag=0;")
    $demoCount = [string](Invoke-RootQuery "SELECT COUNT(*) FROM $databaseName.sys_user WHERE username='$testUsername';")
    $adminId = [string](Invoke-RootQuery "SELECT id FROM $databaseName.sys_user WHERE username='admin' AND status=1 AND del_flag=0 LIMIT 1;")
    $adminRoleCount = [string](Invoke-RootQuery "SELECT COUNT(*) FROM $databaseName.sys_user_role WHERE user_id='$adminId';")
    if ($schemaExists -ne '1' -or $tableCount -ne '148' -or $adminCount -ne '1' -or $demoCount -ne '0' -or $adminRoleCount -eq '0') {
        throw 'P0 demo account preconditions are not satisfied; no application account was changed.'
    }
    $unused = [string](Invoke-RootQuery "SELECT COUNT(*) FROM mysql.user WHERE user='$appUsername' AND host='127.0.0.1';")
    if ($unused -ne '1') { throw 'Restricted P0 database account is missing.' }

    New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
    $helperPath = Join-Path $toolDir 'P0PasswordHash.java'
    $helperSource = @'
import java.io.BufferedReader;
import java.io.InputStreamReader;
import org.jeecg.common.util.PasswordUtil;

public final class P0PasswordHash {
    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, "UTF-8"));
        String username = input.readLine();
        String password = input.readLine();
        String salt = input.readLine();
        System.out.print(PasswordUtil.encrypt(username, password, salt));
    }
}
'@
    [IO.File]::WriteAllText($helperPath, $helperSource, [Text.UTF8Encoding]::new($false))
    & $javacExe -encoding UTF-8 -d $toolDir $utilitySource $helperPath
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile the project password hashing utility.' }

    $salt = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $hashInput = "$testUsername`n$testPassword`n$salt"
    $passwordHash = $hashInput | & $javaExe -cp $toolDir P0PasswordHash
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$passwordHash)) { throw 'Could not generate the P0-only application password hash.' }

    $testId = [Guid]::NewGuid().ToString('N')
    $createUserSql = @"
INSERT INTO $databaseName.sys_user
(id, username, realname, password, salt, avatar, birthday, sex, email, phone, org_code, status, del_flag, third_id, third_type, activiti_sync, work_no, telephone, create_by, create_time, update_by, update_time, user_identity, depart_ids, client_id, login_tenant_id, bpm_status)
SELECT '$testId', '$testUsername', 'P0 Demo', '$passwordHash', '$salt', avatar, birthday, sex, NULL, NULL, org_code, 1, 0, NULL, NULL, activiti_sync, NULL, NULL, '$testUsername', NOW(), NULL, NULL, user_identity, depart_ids, client_id, login_tenant_id, bpm_status
FROM $databaseName.sys_user WHERE username='admin' AND status=1 AND del_flag=0 LIMIT 1;
INSERT INTO $databaseName.sys_user_role (id, user_id, role_id, tenant_id)
SELECT REPLACE(UUID(),'-',''), '$testId', role_id, tenant_id FROM $databaseName.sys_user_role WHERE user_id='$adminId';
"@
    $sqlRunner = New-Object System.Diagnostics.Process
    $sqlRunner.StartInfo.FileName = $mysqlExe
    $sqlRunner.StartInfo.Arguments = "--no-defaults --host=127.0.0.1 --user=$rootUsername"
    $sqlRunner.StartInfo.UseShellExecute = $false
    $sqlRunner.StartInfo.CreateNoWindow = $true
    $sqlRunner.StartInfo.RedirectStandardInput = $true
    $sqlRunner.StartInfo.RedirectStandardError = $true
    if (!$sqlRunner.Start()) { throw 'Could not start the isolated account provisioning query.' }
    $sqlErrorTask = $sqlRunner.StandardError.ReadToEndAsync()
    $sqlRunner.StandardInput.WriteLine($createUserSql)
    $sqlRunner.StandardInput.Close()
    $sqlRunner.WaitForExit()
    $createUserSql = $null
    if ($sqlRunner.ExitCode -ne 0) { throw 'Creating the P0-only login in the isolated clone failed.' }

    $null = New-Item -ItemType File -Path $testLoginPath
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'Allow')))
    Set-Acl -LiteralPath $testLoginPath -AclObject $acl
    $loginJson = ConvertTo-Json -InputObject ([ordered]@{ username = $testUsername; password = $testPassword; database = $databaseName })
    [IO.File]::WriteAllText($testLoginPath, $loginJson, [Text.UTF8Encoding]::new($true))

    $finalUserCount = [string](Invoke-RootQuery "SELECT COUNT(*) FROM $databaseName.sys_user WHERE username='$testUsername' AND status=1 AND del_flag=0;")
    $finalRoleCount = [string](Invoke-RootQuery "SELECT COUNT(*) FROM $databaseName.sys_user_role WHERE user_id='$testId';")
    if ($finalUserCount -ne '1' -or $finalRoleCount -ne $adminRoleCount) { throw 'P0 account/role links did not verify after creation.' }
    Write-Output "Created $testUsername in the isolated application clone with $finalRoleCount cloned role links; private browser credentials are at runtime/config/p0-test-login.json."
}
finally {
    $testPassword = $env:FRESHLINK_P0_DEMO_PASSWORD
if ([string]::IsNullOrWhiteSpace($testPassword)) { throw "Set FRESHLINK_P0_DEMO_PASSWORD locally; historical P0 probes are not team bootstrap scripts." }
    $passwordHash = $null
    $hashInput = $null
    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
}
