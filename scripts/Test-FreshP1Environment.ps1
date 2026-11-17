param(
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [string]$PageBase = 'http://127.0.0.1:13101'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')

$databaseName = 'freshlink_p0_codex_20261117_b'
$evidencePath = if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { $EvidenceDirectory } else { Join-Path $FreshLinkRoot $EvidenceDirectory }
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $FreshLinkRoot 'work')) + [IO.Path]::DirectorySeparatorChar
if (!([IO.Path]::GetFullPath($evidencePath) + [IO.Path]::DirectorySeparatorChar).StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Environment evidence must remain inside project work/.'
}
New-Item -ItemType Directory -Force -Path $evidencePath | Out-Null
$evidenceFile = Join-Path $evidencePath 'environment.json'
if (Test-Path -LiteralPath $evidenceFile) { throw 'Refusing to overwrite existing environment evidence.' }

$dbConfig = Get-Content -LiteralPath (Join-Path $FreshLinkConfig 'p0-db-credentials.json') -Raw | ConvertFrom-Json
$redisCli = Join-Path $FreshLinkRuntime 'redis\bin\Redis-7.4.11-Windows-x64-msys2\redis-cli.exe'
$mysql = 'D:\Yuki\MySQL\bin\mysql.exe'
$env:MYSQL_PWD = [string]$dbConfig.password

function Invoke-Db([string]$sql) {
    $output = & $mysql --no-defaults --host=127.0.0.1 --port=3306 "--user=$($dbConfig.username)" "--database=$databaseName" --batch --raw --skip-column-names -e $sql 2>&1
    $exit = $LASTEXITCODE
    $output = @($output | Where-Object { [string]$_ -notmatch '^mysql: \[Warning\]' })
    if ($exit -ne 0) { throw "Environment database query failed: $($output -join ' ')" }
    return ,@($output)
}

$results = [ordered]@{
    checkedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    timezone = 'Asia/Shanghai'
    database = $databaseName
    checks = [ordered]@{}
}
$problems = @()

try {
    # 1. process and running build identity
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort 18080 -ErrorAction SilentlyContinue)
    if ($listeners.Count -ne 1) { throw 'Expected exactly one listener on 18080.' }
    $pid18080 = $listeners[0].OwningProcess
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $pid18080"
    $testJar = Join-Path $FreshLinkRuntime 'run\p0\jeecg-system-start.jar'
    $targetJar = $FreshLinkJar
    $jarHash = (Get-FileHash -LiteralPath $testJar -Algorithm SHA256).Hash
    $targetHash = (Get-FileHash -LiteralPath $targetJar -Algorithm SHA256).Hash
    $cmd = [string]$process.CommandLine
    $identity = [ordered]@{
        pid = $pid18080
        loopback = $listeners[0].LocalAddress -eq '127.0.0.1'
        commandHasJar = $cmd.IndexOf($testJar, [StringComparison]::OrdinalIgnoreCase) -ge 0
        commandHasPort = $cmd.IndexOf('--server.port=18080', [StringComparison]::OrdinalIgnoreCase) -ge 0
        commandHasTestDatabase = $cmd.IndexOf($databaseName, [StringComparison]::OrdinalIgnoreCase) -ge 0
        runningJarSha256 = $jarHash
        targetJarSha256 = $targetHash
        runningJarMatchesBuild = $jarHash -eq $targetHash
    }
    $results.checks.process = $identity
    if (!$identity.loopback -or !$identity.commandHasJar -or !$identity.commandHasPort -or !$identity.commandHasTestDatabase -or !$identity.runningJarMatchesBuild) {
        $problems += 'backend process/JAR identity does not match the current isolated build'
    }

    # 2. actual database connection from the restricted application account
    $dbIdentity = Invoke-Db "SELECT CONCAT(DATABASE(),'|',CURRENT_USER()) AS identity;"
    $grants = (Invoke-Db 'SHOW GRANTS FOR CURRENT_USER;') -join '; '
    $appSessions = [string](Invoke-Db "SELECT COUNT(*) FROM information_schema.processlist WHERE USER='freshlink_p0_app_b' AND DB='$databaseName' AND ID<>CONNECTION_ID();")[0]
    $otherSchemaGrant = $grants -match '(?i)ON `?xingchenwms`?\.\*'
    $results.checks.database = [ordered]@{
        identity = $dbIdentity[0]
        grantScopeOnlyTestSchema = $grants -match [regex]::Escape("ON ``$databaseName``.*") -and !$otherSchemaGrant
        appPoolSessions = [int]$appSessions
        grantsSummary = ($grants -replace 'GRANT [^;]{0,120}', 'GRANT ...' )
    }
    if ($dbIdentity[0] -notlike "$databaseName|freshlink_p0_app_b@*") { $problems += 'database identity mismatch' }
    if ($otherSchemaGrant) { $problems += 'application account has original business schema grants' }
    if ([int]$appSessions -lt 1) { $problems += 'no application connection-pool session observed' }

    # 3. page -> proxy -> backend chain (dev 13100 or production preview 13101)
    $pagePort = ([uri]$PageBase).Port
    $page = Invoke-WebRequest -Uri "$PageBase/" -SkipHttpErrorCheck -TimeoutSec 15
    $proxy403 = Invoke-WebRequest -Uri "$PageBase/jeecgboot/sys/403" -SkipHttpErrorCheck -TimeoutSec 15
    $frontendListener = @(Get-NetTCPConnection -State Listen -LocalPort $pagePort -ErrorAction SilentlyContinue)
    $frontendPid = if ($frontendListener.Count) { $frontendListener[0].OwningProcess } else { 0 }
    $frontendProcess = if ($frontendPid) { Get-CimInstance Win32_Process -Filter "ProcessId = $frontendPid" } else { $null }
    $frontendCmd = if ($frontendProcess) { [string]$frontendProcess.CommandLine } else { '' }
    $frontendMatches = if ($pagePort -eq 13101) {
        $frontendCmd.IndexOf('Serve-P0Build.py', [StringComparison]::OrdinalIgnoreCase) -ge 0
    } else {
        $frontendCmd.IndexOf('apps\web\node_modules\vite\bin\vite.js', [StringComparison]::OrdinalIgnoreCase) -ge 0 -and $frontendCmd.IndexOf('--port 13100', [StringComparison]::OrdinalIgnoreCase) -ge 0
    }

    # Login through the same proxy and query the frozen P0 order marker.
    $yaml = Get-Content -LiteralPath (Join-Path $FreshLinkBackend 'jeecg-module-system\jeecg-system-start\src\main\resources\application-dev.yml') -Raw -Encoding utf8
    $secretMatch = [regex]::Match($yaml, '(?m)^\s*signatureSecret:\s*(\S+)')
    $loginConfig = Get-Content -LiteralPath (Join-Path $FreshLinkConfig 'p0-test-login.json') -Raw | ConvertFrom-Json
    $captcha = ('p1' + [Guid]::NewGuid().ToString('N').Substring(0, 2)).ToLowerInvariant()
    $checkKey = [Guid]::NewGuid().ToString('N')
    $md5 = [Security.Cryptography.MD5]::Create()
    $prefix = [BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($checkKey + $secretMatch.Groups[1].Value))).Replace('-', '').ToLowerInvariant()
    $redisKey = $prefix + $captcha
    $captchaJson = ConvertTo-Json -InputObject $captcha -Compress
    $redisOutput = & $redisCli -h 127.0.0.1 -p 6379 -n 15 SET $redisKey $captchaJson EX 60
    $loginBody = @{ username = $loginConfig.username; password = $loginConfig.password; captcha = $captcha; checkKey = $checkKey } | ConvertTo-Json -Compress
    $loginResponse = Invoke-WebRequest -Uri "$PageBase/jeecgboot/sys/login" -Method POST -ContentType 'application/json' -Headers @{ Version = 'v3' } -Body $loginBody -SkipHttpErrorCheck -TimeoutSec 30
    $loginPayload = $loginResponse.Content | ConvertFrom-Json
    $token = [string]$loginPayload.result.token
    $p0OrderCount = [string](Invoke-Db "SELECT COUNT(*) FROM wms_out_orders WHERE order_no='OBD202611170001';")[0]
    $orderCall = Invoke-WebRequest -Uri "$PageBase/jeecgboot/outorder/wmsOutOrders/list?pageNo=1&pageSize=100" -Headers @{ 'X-Access-Token' = $token; Version = 'v3' } -SkipHttpErrorCheck -TimeoutSec 30
    $orderPayload = $orderCall.Content | ConvertFrom-Json
    $orderRows = @($orderPayload.result.records | Where-Object { $_.orderNo -eq 'OBD202611170001' -or $_.orderSourceNo -eq 'OBD202611170001' })
    $results.checks.pageProxy = [ordered]@{
        pageBase = $PageBase
        pageHttp = [int]$page.StatusCode
        pageHasApp = $page.Content -match 'id="app"'
        proxy403Http = [int]$proxy403.StatusCode
        frontendPid = $frontendPid
        frontendCommandMatches = $frontendMatches
        proxyLoginSuccess = $loginPayload.success -eq $true
        p0OrderRowCountSql = [int]$p0OrderCount
        p0OrderRowsThroughProxy = $orderRows.Count
        p0OrderSourceMatches = $orderRows.Count -eq 1 -and $orderRows[0].status -eq 'APPROVED'
    }
    if ([int]$page.StatusCode -ne 200 -or !$results.checks.pageProxy.pageHasApp) { $problems += 'frontend page not served' }
    if (![bool]$results.checks.pageProxy.frontendCommandMatches) { $problems += 'frontend process is not the project dev/preview server' }
    # The health path is protected; a 401 JSON from the backend still proves the proxy reaches it.
    if ([int]$proxy403.StatusCode -notin @(200, 401) -or $proxy403.Content -notmatch '"code"') { $problems += 'frontend /jeecgboot proxy does not reach backend' }
    if ($loginPayload.success -ne $true) { $problems += 'login through 13101 proxy failed' }
    if ($orderRows.Count -ne 1) { $problems += 'P0 order marker was not returned through the proxy' }

    # 4. tool versions
    $oldJavaHome = $env:JAVA_HOME
    $env:JAVA_HOME = $FreshLinkJavaHome
    try {
        $mavenVersion = (& 'D:\Yuki\JAVA\software\idea\IntelliJ IDEA Community Edition 2025.2.2\plugins\maven\lib\maven3\bin\mvn.cmd' -v 2>&1 | Select-Object -First 1)
    } finally {
        $env:JAVA_HOME = $oldJavaHome
    }
    $results.checks.versions = [ordered]@{
        java = [string](& (Join-Path $FreshLinkJavaHome 'bin\java.exe') -version 2>&1 | Select-Object -First 1)
        maven = $mavenVersion
        node = (node --version)
        npm = (npm --version)
        pnpm = (pnpm --version 2>$null)
        mysql = ((& $mysql --version) -join ' ')
    }
    $results.checks.evidence = [ordered]@{
        evidenceDirectory = $evidencePath
        note = 'No password, token or captcha value is written to this file.'
    }
    $results.problems = $problems
    $results.conclusion = if ($problems.Count -eq 0) { 'PASS' } else { 'FAIL' }
    $results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidenceFile -Encoding utf8

    $lines = @(
        '# P1 写入前环境核验',
        '',
        "核验时间：$($results.checkedAt)（Asia/Shanghai）",
        "测试库：``$databaseName``；前端：$PageBase；后端：127.0.0.1:18080。",
        '',
        '## 1. 进程与运行版本',
        '',
        "- 监听 PID：$pid18080；仅 loopback：$($identity.loopback)；命令行含运行 JAR：$($identity.commandHasJar)；含 ``--server.port=18080``：$($identity.commandHasPort)；含精确测试库 URL：$($identity.commandHasTestDatabase)。",
        "- 运行 JAR SHA256：``$($identity.runningJarSha256)``；本次 target JAR SHA256：``$($identity.targetJarSha256)``；一致：$($identity.runningJarMatchesBuild)。",
        '',
        '## 2. 数据库实际连接',
        '',
        "- 应用账号会话身份：``$($dbIdentity[0])``；应用连接池会话数：$appSessions。",
        "- 授权仅测试 schema：$($results.checks.database.grantScopeOnlyTestSchema)。",
        '',
        '## 3. 页面到后端链路',
        '',
        "- $PageBase 首页 HTTP：$($page.StatusCode)；包含应用挂载点：$($results.checks.pageProxy.pageHasApp)。",
        "- 前端监听 PID：$frontendPid；命令行匹配本项目 Vite/预览入口：$frontendMatches。",
        "- 经前端 ``/jeecgboot`` 访问后端健康检查 HTTP：$($proxy403.StatusCode)；经代理登录成功：$($loginPayload.success)。",
        "- 经代理查询 P0 专用单据 ``OBD202611170001``：返回 $($orderRows.Count) 行；测试库 SQL 计数：$p0OrderCount；状态/来源匹配：$($results.checks.pageProxy.p0OrderSourceMatches)。",
        '',
        '## 4. 工具版本',
        '',
        "- $(($results.checks.versions.GetEnumerator() | ForEach-Object { "$($_.Key)：$($_.Value)" }) -join '；')",
        '',
        '## 结论',
        '',
        "环境核验：$($results.conclusion)。" + $(if ($problems.Count) { ' 问题：' + ($problems -join '；') } else { ' 四项均满足，可继续迁移和业务写入测试。' }),
        '',
        '本文件不包含数据库密码、登录密码、token 或验证码值。'
    )
    $lines | Set-Content -LiteralPath (Join-Path $evidencePath 'environment.md') -Encoding utf8
    if ($problems.Count -gt 0) { throw ('Environment verification failed: ' + ($problems -join '; ')) }
    Write-Output "P1 environment PASS; evidence: $evidencePath"
}
finally {
    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
}
