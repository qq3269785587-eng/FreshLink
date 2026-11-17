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
    throw 'Account evidence must remain inside project work/.'
}
New-Item -ItemType Directory -Force -Path $evidencePath | Out-Null

$config = Get-Content -LiteralPath (Join-Path $FreshLinkConfig 'p0-db-credentials.json') -Raw | ConvertFrom-Json
if ($config.schema -cne $DatabaseName -or $config.host -cne '127.0.0.1' -or $config.username -cne 'freshlink_p0_app_b' -or !$config.password) {
    throw 'Isolated database configuration does not match the allowed test schema/account.'
}
$mysql = 'D:\Yuki\MySQL\bin\mysql.exe'
$credentialsPath = Join-Path $FreshLinkConfig 'fresh-p1-demo-accounts.json'
$env:MYSQL_PWD = [string]$config.password

function Invoke-Sql([string]$sql) {
    $output = & $mysql --no-defaults --host=127.0.0.1 --port=3306 "--user=$($config.username)" "--database=$DatabaseName" --batch --raw --skip-column-names -e $sql 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Isolated account SQL query failed: $sql" }
    return ,@($output)
}

function Invoke-SqlText([string]$sql) {
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = $mysql
    $process.StartInfo.Arguments = "--no-defaults --host=127.0.0.1 --port=3306 --user=$($config.username) --database=$DatabaseName --default-character-set=utf8mb4"
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardInput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
    $process.StartInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    if (!$process.Start()) { throw 'Could not start the isolated account query.' }
    $err = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.WriteLine($sql)
    $process.StandardInput.Close()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Isolated account SQL failed: $($err.Result)"
    }
}

$demoUsers = @(
    @{ username = 'fresh_hq'; realname = '生鲜总部管理员'; role = 'fresh_hq'; storeCode = $null },
    @{ username = 'fresh_wh'; realname = '生鲜仓管'; role = 'fresh_warehouse'; storeCode = $null },
    @{ username = 'fresh_store_a'; realname = '门店A用户'; role = 'fresh_store'; storeCode = 'A' },
    @{ username = 'fresh_store_b'; realname = '门店B用户'; role = 'fresh_store'; storeCode = 'B' }
)

try {
    $schemaTables = [string](Invoke-Sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=DATABASE() AND table_name IN ('fresh_user_store','fresh_store','sys_user','sys_role');")[0]
    if ($schemaTables -ne '4') { throw 'P1 schema/roles are missing; run Invoke-FreshP1Migration.ps1 first.' }
    $admin = Invoke-Sql "SELECT id, IFNULL(org_code,''), IFNULL(login_tenant_id,0) FROM sys_user WHERE username='admin' AND status=1 AND del_flag=0 LIMIT 1;"
    if ($admin.Count -lt 1) { throw 'Baseline admin account is missing.' }
    $adminParts = ([string]$admin[0]).Split("`t")
    $adminId = $adminParts[0]
    $adminOrgCode = $adminParts[1]
    $adminTenant = $adminParts[2]

    $accounts = [ordered]@{}
    if (Test-Path -LiteralPath $credentialsPath) {
        $existing = Get-Content -LiteralPath $credentialsPath -Raw | ConvertFrom-Json
        if ($existing.database -cne $DatabaseName) { throw 'Existing demo credential file belongs to another database.' }
        foreach ($user in $demoUsers) {
            $accounts[$user.username] = [string]($existing.users.PSObject.Properties[$user.username].Value)
        }
    } else {
        foreach ($user in $demoUsers) {
            $accounts[$user.username] = 'FreshLink-P1-' + $user.username + '-' + ([Guid]::NewGuid().ToString('N').Substring(0, 10)) + '!'
        }
    }

    # Compile the project's own PasswordUtil so hashes match the running application.
    $toolDir = Join-Path $FreshLinkRuntime 'tools\fresh-p1-password-hash'
    New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
    $helperPath = Join-Path $toolDir 'FreshP1PasswordHash.java'
    $helperSource = @'
import java.io.BufferedReader;
import java.io.InputStreamReader;
import org.jeecg.common.util.PasswordUtil;

public final class FreshP1PasswordHash {
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
    $javac = Join-Path $FreshLinkJavaHome 'bin\javac.exe'
    $java = Join-Path $FreshLinkJavaHome 'bin\java.exe'
    $passwordUtil = Join-Path $FreshLinkBackend 'jeecg-boot-base-core\src\main\java\org\jeecg\common\util\PasswordUtil.java'
    & $javac -encoding UTF-8 -d $toolDir $passwordUtil $helperPath
    if ($LASTEXITCODE -ne 0) { throw 'Could not compile the project password hashing utility.' }

    $created = @()
    foreach ($user in $demoUsers) {
        $username = $user.username
        $password = $accounts[$username]
        $salt = [Guid]::NewGuid().ToString('N').Substring(0, 8)
        $hashInput = "$username`n$password`n$salt"
        $hash = ($hashInput | & $java -cp $toolDir FreshP1PasswordHash)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$hash)) { throw "Could not hash password for $username." }
        $userId = [Guid]::NewGuid().ToString('N')
        $roleId = [string](Invoke-Sql "SELECT id FROM sys_role WHERE role_code='$($user.role)' LIMIT 1;")[0]
        if ([string]::IsNullOrWhiteSpace($roleId)) { throw "Role $($user.role) is missing." }

        $exists = [string](Invoke-Sql "SELECT COUNT(*) FROM sys_user WHERE username='$username' AND del_flag=0;")[0]
        $safeRealName = $user.realname
        $sql = @"
SET @uid = (SELECT id FROM sys_user WHERE username='$username' AND del_flag=0 LIMIT 1);
INSERT INTO sys_user
(id, username, realname, password, salt, avatar, birthday, sex, email, phone, org_code, status, del_flag, third_id, third_type, activiti_sync, work_no, telephone, create_by, create_time, update_by, update_time, user_identity, depart_ids, client_id, login_tenant_id, bpm_status)
VALUES
('$userId', '$username', '$safeRealName', '$hash', '$salt', NULL, NULL, NULL, NULL, NULL, '$adminOrgCode', 1, 0, NULL, NULL, 0, NULL, NULL, '$username', NOW(), NULL, NULL, NULL, NULL, NULL, $adminTenant, NULL)
ON DUPLICATE KEY UPDATE password=VALUES(password), salt=VALUES(salt), status=1, del_flag=0, realname=VALUES(realname), update_time=NOW();
SET @uid = (SELECT id FROM sys_user WHERE username='$username' AND del_flag=0 LIMIT 1);
DELETE FROM sys_user_role WHERE user_id=@uid;
INSERT INTO sys_user_role (id, user_id, role_id, tenant_id) VALUES (REPLACE(UUID(),'-',''), @uid, '$roleId', $adminTenant);
"@
        Invoke-SqlText $sql
        $created += $username
    }

    foreach ($user in $demoUsers) {
        if (!$user.storeCode) { continue }
        $username = $user.username
        $storeId = [string](Invoke-Sql "SELECT id FROM fresh_store WHERE store_code='$($user.storeCode)' LIMIT 1;")[0]
        if ([string]::IsNullOrWhiteSpace($storeId)) { throw "Store $($user.storeCode) is missing." }
        $sql = @"
SET @uid = (SELECT id FROM sys_user WHERE username='$username' AND del_flag=0 LIMIT 1);
INSERT INTO fresh_user_store (id, user_id, store_id, create_by, create_time)
VALUES (REPLACE(UUID(),'-',''), @uid, '$storeId', 'provision-p1', NOW())
ON DUPLICATE KEY UPDATE store_id=VALUES(store_id), update_time=NOW();
"@
        Invoke-SqlText $sql
    }

    $null = New-Item -ItemType File -Path $credentialsPath -ErrorAction SilentlyContinue
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'Allow')))
    Set-Acl -LiteralPath $credentialsPath -AclObject $acl
    $credentialJson = ConvertTo-Json -Depth 5 -InputObject ([ordered]@{
        database = $DatabaseName
        purpose = 'FreshLink P1 demo accounts; private local file, never include in evidence'
        users = $accounts
    })
    [IO.File]::WriteAllText($credentialsPath, $credentialJson, [Text.UTF8Encoding]::new($true))

    $verification = @()
    foreach ($user in $demoUsers) {
        $username = $user.username
        $row = [string](Invoke-Sql "SELECT CONCAT(u.id,'|',r.role_code,'|',IFNULL(s.store_code,'')) FROM sys_user u LEFT JOIN sys_user_role ur ON ur.user_id=u.id LEFT JOIN sys_role r ON r.id=ur.role_id LEFT JOIN fresh_user_store f ON f.user_id=u.id LEFT JOIN fresh_store s ON s.id=f.store_id WHERE u.username='$username' AND u.status=1 AND u.del_flag=0 LIMIT 1;")[0]
        if ([string]::IsNullOrWhiteSpace($row)) { throw "Account verification failed for $username." }
        $parts = $row.Split('|')
        if ($parts[1] -ne $user.role) { throw "Role mismatch for $username." }
        if ($user.storeCode -and $parts[2] -ne $user.storeCode) { throw "Store binding mismatch for $username." }
        $verification += [pscustomobject]@{ username = $username; role = $parts[1]; storeCode = $parts[2]; passwordStored = $true }
    }

    $verification | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidencePath 'accounts-summary.json') -Encoding utf8
    $verification | Export-Csv -LiteralPath (Join-Path $evidencePath 'accounts-summary.tsv') -NoTypeInformation -Delimiter "`t" -Encoding utf8
    Write-Output "P1 demo accounts verified: $($verification.username -join ', '); credentials kept in runtime/config (not in evidence)."
}
finally {
    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
}
