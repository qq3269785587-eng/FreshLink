param(
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path (Get-Location) 'scripts/Paths.ps1')

$databaseName = 'freshlink_p0_codex_20261117_b'
$apiRoot = 'http://127.0.0.1:18080/jeecg-boot'
$evidencePath = if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { $EvidenceDirectory } else { Join-Path $FreshLinkRoot $EvidenceDirectory }
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $FreshLinkRoot 'work')) + [IO.Path]::DirectorySeparatorChar
if (!([IO.Path]::GetFullPath($evidencePath) + [IO.Path]::DirectorySeparatorChar).StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'API evidence must remain inside project work/.'
}
if (Test-Path -LiteralPath (Join-Path $evidencePath 'assertions.tsv')) {
    throw 'Refusing to overwrite prior API evidence; use a new attempt directory.'
}
New-Item -ItemType Directory -Force -Path $evidencePath | Out-Null

$dbConfig = Get-Content -LiteralPath (Join-Path $FreshLinkConfig 'p0-db-credentials.json') -Raw | ConvertFrom-Json
if ($dbConfig.schema -cne $databaseName -or $dbConfig.host -cne '127.0.0.1' -or $dbConfig.username -cne 'freshlink_p0_app_b') {
    throw 'Isolated database configuration does not match the allowed test schema/account.'
}
$loginConfig = Get-Content -LiteralPath (Join-Path $FreshLinkConfig 'fresh-p1-demo-accounts.json') -Raw | ConvertFrom-Json
$mysql = 'D:\Yuki\MySQL\bin\mysql.exe'
$redisCli = Join-Path $FreshLinkRuntime 'redis\bin\Redis-7.4.11-Windows-x64-msys2\redis-cli.exe'
if (!(Test-Path -LiteralPath $redisCli)) { throw 'Redis CLI is missing.' }

$env:MYSQL_PWD = [string]$dbConfig.password
$script:assertions = [System.Collections.Generic.List[object]]::new()
$script:total = 0
$script:passed = 0
$script:failures = [System.Collections.Generic.List[object]]::new()
$script:probeError = $null

function Invoke-Db([string]$sql) {
    $output = & $mysql --no-defaults --host=127.0.0.1 --port=3306 "--user=$($dbConfig.username)" "--database=$databaseName" --default-character-set=utf8mb4 --batch --raw --skip-column-names -e $sql 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Database assertion query failed.' }
    return ,@($output)
}

function Invoke-Api([string]$method, [string]$path, [string]$token, $body = $null) {
    $headers = @{}
    if ($token) { $headers['X-Access-Token'] = $token; $headers['Authorization'] = $token }
    $headers['Version'] = 'v3'
    $uri = "$apiRoot$path"
    $parameters = @{ Uri = $uri; Method = $method; Headers = $headers; SkipHttpErrorCheck = $true; TimeoutSec = 60 }
    if ($null -ne $body) {
        $parameters['ContentType'] = 'application/json'
        $parameters['Body'] = ($body | ConvertTo-Json -Depth 20 -Compress)
    }
    $response = Invoke-WebRequest @parameters
    $parsed = $null
    try { $parsed = $response.Content | ConvertFrom-Json } catch { }
    return [pscustomobject]@{ http = [int]$response.StatusCode; body = $parsed; raw = $response.Content }
}

function Assert-Equal([string]$id, [string]$description, $expected, $actual) {
    $script:total++
    $ok = ([string]$expected -eq [string]$actual)
    if ($ok) { $script:passed++ } else { $script:failures.Add([pscustomobject]@{ id = $id; assertion = $description; expected = $expected; actual = $actual }) }
    $script:assertions.Add([pscustomobject]@{
            id = $id; assertion = $description; expected = [string]$expected; actual = [string]$actual
            passed = $ok; checkedAt = (Get-Date).ToString('HH:mm:ss')
        })
}

function Assert-True([string]$id, [string]$description, [bool]$condition, [string]$actual = '') {
    $script:total++
    $ok = [bool]$condition
    if ($ok) { $script:passed++ } else { $script:failures.Add([pscustomobject]@{ id = $id; assertion = $description; expected = 'true'; actual = $actual }) }
    $script:assertions.Add([pscustomobject]@{
            id = $id; assertion = $description; expected = 'true'
            actual = $(if ($actual) { $actual } else { [string]$ok })
            passed = $ok; checkedAt = (Get-Date).ToString('HH:mm:ss')
        })
}

function Get-Login([string]$username) {
    $password = [string]($loginConfig.users.PSObject.Properties[$username].Value)
    if ([string]::IsNullOrWhiteSpace($password)) { throw "Demo password is missing for $username." }
    $yaml = Get-Content -LiteralPath (Join-Path $FreshLinkBackend 'jeecg-module-system\jeecg-system-start\src\main\resources\application-dev.yml') -Raw -Encoding utf8
    $secretMatch = [regex]::Match($yaml, '(?m)^\s*signatureSecret:\s*(\S+)')
    if (!$secretMatch.Success) { throw 'Test profile signature secret is unavailable.' }
    $captcha = ('p1' + [Guid]::NewGuid().ToString('N').Substring(0, 2)).ToLowerInvariant()
    $checkKey = [Guid]::NewGuid().ToString('N')
    $md5 = [Security.Cryptography.MD5]::Create()
    $prefix = [BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($checkKey + $secretMatch.Groups[1].Value))).Replace('-', '').ToLowerInvariant()
    $redisKey = $prefix + $captcha
    $captchaJson = ConvertTo-Json -InputObject $captcha -Compress
    $redisOutput = & $redisCli -h 127.0.0.1 -p 6379 -n 15 SET $redisKey $captchaJson EX 60
    if ($LASTEXITCODE -ne 0 -or $redisOutput -ne 'OK') { throw 'Could not install the one-use captcha fixture.' }
    $login = Invoke-Api 'POST' '/sys/login' $null @{ username = $username; password = $password; captcha = $captcha; checkKey = $checkKey }
    if ($login.http -ne 200 -or !$login.body -or $login.body.success -ne $true -or [string]::IsNullOrWhiteSpace([string]$login.body.result.token)) {
        throw "Login failed for $username (HTTP $($login.http)): $($login.body.message)"
    }
    return [pscustomobject]@{ token = [string]$login.body.result.token; userId = [string]$login.body.result.userInfo.id; username = $username }
}

function Save-Exchange([string]$name, $requestBody, $call) {
    $payload = [ordered]@{ request = $requestBody; http = $call.http; response = $call.body }
    $payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $evidencePath ($name + '.json')) -Encoding utf8
}


$environmentFile=Join-Path (Split-Path $evidencePath -Parent) 'environment.json'
if (!(Test-Path $environmentFile) -or (Get-Content $environmentFile -Raw | ConvertFrom-Json).conclusion -ne 'PASS') { throw 'Run Test-FreshP1Environment into the parent attempt directory before this write probe.' }
$createdProductId=$null; $orderIds=@(); $testUserId=$null
$originalStoreStatus=[string](Invoke-Db "SELECT status FROM fresh_store WHERE id='fresh_p1_store_a';")[0]
$code='FRESH-REPAIR-'+[Guid]::NewGuid().ToString('N').Substring(0,12)
function Check-Rejected($name,$request,$call,$beforeSql) {
 Save-Exchange $name $request $call
 Assert-True $name '业务必须明确拒绝' ($call.body.success -ne $true) "http=$($call.http); success=$($call.body.success)"
 if($beforeSql) { Assert-Equal $name '失败后数据库不变' $beforeSql (Product-State) }
}
function Product-State { return ((Invoke-Db "SELECT CONCAT_WS('|',product_spec,unit,status,near_expiry_days) FROM wms_products WHERE id='$createdProductId';") -join ';') }
function New-Order {
 $source=$code+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6)
 $request=@{orderType='PURCHASE';sourceNumber=$source;ownerId='fresh_p1_owner';warehouseId='fresh_p1_wh_w1';expectedArrivalTime='2026-11-18 10:00:00'}
 $call=Invoke-Api POST '/inorder/wmsStockInOrders/add' $hq.token $request
 $id=[string](Invoke-Db "SELECT id FROM wms_stock_in_orders WHERE source_number='$source';")[0]
 if(!$id){throw 'Failed to create disposable order'}
 $script:orderIds+= $id
 return $id
}
function Edit-Order($id,$product,$quantity,$itemId='') {
 $request=@{id=$id;ownerId='fresh_p1_owner';warehouseId='fresh_p1_wh_w1';status='INITIAL';wmsStockInOrderItemsList=@(@{id=$itemId;productId=$product;expectedQuantity=$quantity;receivedQuantity=0;shelvedQuantity=0;defectiveQuantity=0})}
 return (Invoke-Api POST '/inorder/wmsStockInOrders/edit' $hq.token $request)
}
try {
 $hq=Get-Login 'fresh_hq'
 $base=@{productName='P1修复隔离回归';productCode=$code;ownerId='fresh_p1_owner';categoryId='0';productSpec='1kg/袋';unit='袋';shelfLife=7;storageType='CHILLED';nearExpiryDays=3;status='ACTIVE';isExpiryControlled=1}
 foreach($value in @(1.5,-1,$null,36501,2147483648,'1.5')) {
  $input=$base.Clone(); $input.nearExpiryDays=$value
  $call=Invoke-Api POST '/goods/wmsProducts/add' $hq.token $input
  Check-Rejected ('threshold-add-'+$script:total) $input $call $null
  Assert-Equal 'threshold-add' '非法新增不落库' 0 ([string](Invoke-Db "SELECT COUNT(*) FROM wms_products WHERE product_code='$code';")[0])
 }
 $base.nearExpiryDays=0
 $add=Invoke-Api POST '/goods/wmsProducts/add' $hq.token $base
 Save-Exchange 'legal-zero-add' $base $add
 Assert-Equal 'threshold-zero' '合法0新增' True $add.body.success
 $createdProductId=[string](Invoke-Db "SELECT id FROM wms_products WHERE product_code='$code';")[0]
 if(!$createdProductId){throw 'Product setup failed'}
 Assert-Equal 'threshold-zero' '合法0落库' '1kg/袋|袋|ACTIVE|0' (Product-State)
 foreach($pair in @(@('productSpec',''),@('unit',''),@('status','BOGUS'),@('nearExpiryDays',1.5),@('nearExpiryDays',-1),@('nearExpiryDays',$null),@('nearExpiryDays',36501),@('nearExpiryDays',2147483648))) {
  $input=$base.Clone();$input.id=$createdProductId;$input[$pair[0]]=$pair[1]
  $before=Product-State
  Check-Rejected ('invalid-edit-'+$script:total) $input (Invoke-Api POST '/goods/wmsProducts/edit' $hq.token $input) $before
 }
 $order1=New-Order
 $legal=Edit-Order $order1 $createdProductId 2
 Save-Exchange 'active-product-new-item' @{order=$order1;quantity=2} $legal
 Assert-Equal 'inbound-active' '启用食材新增成功' True $legal.body.success
 $base.id=$createdProductId;$base.status='INACTIVE'
 $disable=Invoke-Api POST '/goods/wmsProducts/edit' $hq.token $base
 Assert-Equal 'disable' '禁用成功' True $disable.body.success
 $persistedItem=[string](Invoke-Db "SELECT id FROM wms_stock_in_order_items WHERE order_id='$order1';")[0]
 $order2=New-Order
 $beforeNew=(Invoke-Db "SELECT CONCAT(status,'|',IFNULL(total_expected_quantity,0)) FROM wms_stock_in_orders WHERE id='$order2';") -join ';'
 $blocked=Edit-Order $order2 $createdProductId 1 $persistedItem
 Check-Rejected 'disabled-new-forged-item-id' @{order=$order2;product=$createdProductId;forgedItemId=$persistedItem} $blocked $null
 Assert-Equal 'disabled-new' '新单未写明细' 0 ([string](Invoke-Db "SELECT COUNT(*) FROM wms_stock_in_order_items WHERE order_id='$order2';")[0])
 Assert-Equal 'disabled-new' '新单状态总量未变' $beforeNew ((Invoke-Db "SELECT CONCAT(status,'|',IFNULL(total_expected_quantity,0)) FROM wms_stock_in_orders WHERE id='$order2';") -join ';')
 $order3=New-Order
 $activeExisting=Edit-Order $order3 'fresh_p1_product_x' 1
 Assert-Equal 'replacement-setup' '建立原启用食材明细' True $activeExisting.body.success
 $beforeReplacement=(Invoke-Db "SELECT CONCAT(product_id,'|',expected_quantity) FROM wms_stock_in_order_items WHERE order_id='$order3';") -join ';'
 $replacement=Edit-Order $order3 $createdProductId 1
 Check-Rejected 'disabled-replacement' @{order=$order3;product=$createdProductId} $replacement $null
 Assert-Equal 'disabled-replacement' '替换失败原明细不变' $beforeReplacement ((Invoke-Db "SELECT CONCAT(product_id,'|',expected_quantity) FROM wms_stock_in_order_items WHERE order_id='$order3';") -join ';')
 $beforeOld=(Invoke-Db "SELECT CONCAT(product_id,'|',expected_quantity) FROM wms_stock_in_order_items WHERE order_id='$order1';") -join ';'
 $increase=Edit-Order $order1 $createdProductId 3
 Check-Rejected 'disabled-increase' @{order=$order1;quantity=3} $increase $null
 Assert-Equal 'disabled-increase' '既有明细未变' $beforeOld ((Invoke-Db "SELECT CONCAT(product_id,'|',expected_quantity) FROM wms_stock_in_order_items WHERE order_id='$order1';") -join ';')
 foreach($quantity in @(2,1)) {
  $retain=Edit-Order $order1 $createdProductId $quantity
  Save-Exchange "disabled-existing-$quantity" @{order=$order1;quantity=$quantity} $retain
  Assert-Equal 'disabled-existing' '禁用后保留或减少原承诺' True $retain.body.success
 }
 $missing=Edit-Order $order2 'missing-p1-product' 1
 Check-Rejected 'missing-product' @{product='missing-p1-product'} $missing $null
 # Existing disabled commitments can still move through the unchanged submission/approval path.
 $submit=Invoke-Api POST '/inorder/wmsStockInOrders/submitAudit' $hq.token @{id=$order1}
 Save-Exchange 'disabled-existing-submit' @{id=$order1} $submit
 Assert-Equal 'disabled-existing' '已存在禁用食材单可提交' True $submit.body.success
 $read=Invoke-Api GET "/inorder/wmsStockInOrders/queryById?id=$order1" $hq.token
 Assert-Equal 'disabled-existing' '旧单可读' True $read.body.success
 $forged=Edit-Order $order1 $createdProductId 1
 Check-Rejected 'forged-order-state' @{id=$order1;status='INITIAL'} $forged $null
 $approve=Invoke-Api POST '/inorder/wmsStockInOrders/audit' $hq.token @{id=$order1;status='APPROVED'}
 Save-Exchange 'disabled-existing-approve' @{id=$order1;status='APPROVED'} $approve
 Assert-Equal 'disabled-existing' '已承诺禁用食材单可审核' True $approve.body.success
 Assert-Equal 'disabled-existing' '审核状态真实落库' 'APPROVED' ([string](Invoke-Db "SELECT status FROM wms_stock_in_orders WHERE id='$order1';")[0])
 Invoke-Db "SELECT o.id,o.status,o.total_expected_quantity,i.product_id,i.expected_quantity,p.status FROM wms_stock_in_orders o LEFT JOIN wms_stock_in_order_items i ON i.order_id=o.id LEFT JOIN wms_products p ON p.id=i.product_id WHERE o.id IN ('$order1','$order2');" | Set-Content (Join-Path $evidencePath 'inbound-after.tsv')
 # Real user fixtures: zero roles/binding, unbound store role, dangling and inactive bindings.
 $testUserId='repair_p1_'+[Guid]::NewGuid().ToString('N').Substring(0,10)
 $username=$testUserId; $password=[Guid]::NewGuid().ToString('N')+'!aA9';$salt=[Guid]::NewGuid().ToString('N').Substring(0,8)
 $java=Join-Path $FreshLinkJavaHome 'bin/java.exe';$helper=Join-Path $FreshLinkRuntime 'tools/fresh-p1-password-hash'
 $hash=("$username`n$password`n$salt" | & $java -cp $helper FreshP1PasswordHash)
 if($LASTEXITCODE -ne 0 -or !$hash){throw 'Test user hash failed'}
 Invoke-Db "INSERT INTO sys_user(id,username,realname,password,salt,status,del_flag,activiti_sync,login_tenant_id,create_by,create_time) VALUES('$testUserId','$username','P1隔离权限回归','$hash','$salt',1,0,0,0,'p1_repair',NOW());" | Out-Null
 $loginConfig.users | Add-Member -NotePropertyName $username -NotePropertyValue $password
 $user=Get-Login $username
 foreach($fixture in @('no-role','binding-without-role','unbound-store','dangling-binding','inactive-binding')) {
  if($fixture -eq 'binding-without-role'){Invoke-Db "INSERT INTO fresh_user_store(id,user_id,store_id) VALUES('${testUserId}_bind','$testUserId','fresh_p1_store_a');"|Out-Null}
  if($fixture -eq 'unbound-store'){Invoke-Db "DELETE FROM fresh_user_store WHERE user_id='$testUserId';"|Out-Null}
  if($fixture -eq 'unbound-store'){Invoke-Db "INSERT INTO sys_user_role(id,user_id,role_id) VALUES('${testUserId}_role','$testUserId','fresh_p1_role_store');"|Out-Null}
  if($fixture -eq 'dangling-binding'){Invoke-Db "INSERT INTO fresh_user_store(id,user_id,store_id) VALUES('${testUserId}_bind','$testUserId','p1_missing_store');"|Out-Null}
  if($fixture -eq 'inactive-binding'){Invoke-Db "UPDATE fresh_user_store SET store_id='fresh_p1_store_a' WHERE user_id='$testUserId'; UPDATE fresh_store SET status='INACTIVE' WHERE id='fresh_p1_store_a';"|Out-Null}
  Invoke-Db "SELECT '$fixture',COUNT(*) FROM sys_user_role WHERE user_id='$testUserId'; SELECT '$fixture',COUNT(*) FROM fresh_user_store WHERE user_id='$testUserId';" | Add-Content (Join-Path $evidencePath 'role-binding-fixtures.tsv')
  foreach($path in @('/fresh/stores/list?pageNo=1&pageSize=100','/fresh/stores/queryById?id=fresh_p1_store_b','/fresh/stores/my')) {
   $call=Invoke-Api GET $path $user.token
   Check-Rejected ($fixture+'-'+$script:total) @{fixture=$fixture;path=$path} $call $null
  }
 }
 Invoke-Db "UPDATE fresh_store SET status='$originalStoreStatus' WHERE id='fresh_p1_store_a';"|Out-Null
 foreach($name in @('fresh_hq','fresh_wh','fresh_store_a','fresh_store_b')) {
  $actor=Get-Login $name
  $list=Invoke-Api GET '/fresh/stores/list?pageNo=1&pageSize=100' $actor.token
  Save-Exchange $name @{path='/fresh/stores/list'} $list
  Assert-Equal $name '授权列表成功' True $list.body.success
  $expected=if($name -in @('fresh_hq','fresh_wh')){2}else{1}
  Assert-Equal $name '授权数据范围' $expected @($list.body.result.records).Count
  if($name -eq 'fresh_store_a') {
   $cross=Invoke-Api GET '/fresh/stores/queryById?id=fresh_p1_store_b' $actor.token
   Check-Rejected 'store-a-cross-b' @{id='fresh_p1_store_b'} $cross $null
  }
 }
} catch { $script:probeError=$_.Exception.Message; throw }
finally {
 if($hq) {
  foreach($id in $orderIds){Save-Exchange ('cleanup-order-'+$id) @{id=$id} (Invoke-Api DELETE "/inorder/wmsStockInOrders/delete?id=$id" $hq.token)}
  if($createdProductId){Save-Exchange 'cleanup-product' @{id=$createdProductId} (Invoke-Api DELETE "/goods/wmsProducts/delete?id=$createdProductId" $hq.token)}
 }
 if($testUserId){Invoke-Db "DELETE FROM fresh_user_store WHERE user_id='$testUserId';DELETE FROM sys_user_role WHERE user_id='$testUserId';DELETE FROM sys_user WHERE id='$testUserId';UPDATE fresh_store SET status='$originalStoreStatus' WHERE id='fresh_p1_store_a';"|Out-Null}
 Invoke-Db "SELECT COUNT(*) FROM wms_products WHERE product_code='$code';SELECT COUNT(*) FROM wms_stock_in_orders WHERE source_number LIKE '$code%';SELECT COUNT(*) FROM sys_user WHERE id='$testUserId';" | Set-Content (Join-Path $evidencePath 'cleanup-counts.tsv')
 $script:assertions | Export-Csv -LiteralPath (Join-Path $evidencePath 'assertions.tsv') -NoTypeInformation -Delimiter "`t" -Encoding utf8
 @{total=$script:total;passed=$script:passed;failed=($script:total-$script:passed);error=$script:probeError;failures=@($script:failures)} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $evidencePath 'summary.json')
 Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
}
if($script:total -ne $script:passed){throw "Repair regression failed: $($script:passed)/$($script:total)"}
Write-Output "P1 repair regression PASS $($script:passed)/$($script:total)"

