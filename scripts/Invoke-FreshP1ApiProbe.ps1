param(
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')

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

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$tempSupplierCode = "FRESH-P1-TMP-$timestamp"
$tempStoreCode = "FRESH-P1-TMP-STORE-$timestamp"
$tempSupplier2 = "FRESH-P1-TMP2-$timestamp"
$tempStore2 = "FRESH-P1-TMP-STORE2-$timestamp"
$tempStore3 = "FRESH-P1-TMP-STORE3-$timestamp"
$createdSupplierIds = @()
$createdStoreIds = @()

try {
    $countsBefore = Invoke-Db "SELECT CONCAT('suppliers=',COUNT(*)) FROM fresh_supplier UNION ALL SELECT CONCAT('stores=',COUNT(*)) FROM fresh_store UNION ALL SELECT CONCAT('bindings=',COUNT(*)) FROM fresh_user_store UNION ALL SELECT CONCAT('products=',COUNT(*)) FROM wms_products;"
    $hq = Get-Login 'fresh_hq'
    $warehouse = Get-Login 'fresh_wh'
    $storeA = Get-Login 'fresh_store_a'
    $storeB = Get-Login 'fresh_store_b'
    $storeList = Invoke-Api 'GET' '/fresh/stores/list?pageNo=1&pageSize=50' $hq.token
    $storeCodes = @($storeList.body.result.records | ForEach-Object { $_.storeCode }) -join ','
    Assert-True 'P1-01' 'HQ门店列表包含门店A/B' ($storeCodes -match '(^|,)A(,|$)' -and $storeCodes -match '(^|,)B(,|$)') $storeCodes
    $supplierList = Invoke-Api 'GET' '/fresh/suppliers/list?pageNo=1&pageSize=50' $hq.token
    $supplierCodes = @($supplierList.body.result.records | ForEach-Object { $_.supplierCode }) -join ','
    Assert-True 'P1-01' 'HQ供应商列表包含S1/S2' ($supplierCodes -match '(^|,)S1(,|$)' -and $supplierCodes -match '(^|,)S2(,|$)') $supplierCodes

    $warehouseList = Invoke-Api 'GET' '/warehouse/wmsWarehouses/list?pageNo=1&pageSize=100' $hq.token
    $hasW1 = @($warehouseList.body.result.records | Where-Object { $_.warehouseCode -eq 'W1' }).Count -eq 1
    Assert-True 'P1-01' '仓库W1存在且可查询' $hasW1
    $zoneList = Invoke-Api 'GET' '/warehouse/wmsStorageZones/list?pageNo=1&pageSize=100' $hq.token
    $coldZone = @($zoneList.body.result.records | Where-Object { $_.zoneCode -eq 'COLD' })[0]
    Assert-Equal 'P1-01' '冷藏库区温区为CHILLED' 'CHILLED' $coldZone.storageType
    $locationList = Invoke-Api 'GET' '/warehouse/wmsStorageLocations/list?pageNo=1&pageSize=100' $hq.token
    $locationCodes = @($locationList.body.result.records | Where-Object { $_.locationCode -in @('R1','C1','C2','N1','P1','Q1') } | ForEach-Object { $_.locationCode }) -join ','
    Assert-Equal 'P1-01' 'P1所需库位R1/C1/C2/N1/P1/Q1均存在' 'C1,C2,N1,P1,Q1,R1' ((($locationCodes -split ',') | Sort-Object) -join ',')

    $productList = Invoke-Api 'GET' '/goods/wmsProducts/list?pageNo=1&pageSize=100' $hq.token
    $productX = @($productList.body.result.records | Where-Object { $_.productCode -eq 'FRESH-X' })[0]
    $productY = @($productList.body.result.records | Where-Object { $_.productCode -eq 'FRESH-Y' })[0]
    Assert-Equal 'P1-01' '食材X温区为CHILLED' 'CHILLED' $productX.storageType
    Assert-Equal 'P1-01' '食材X临期阈值为3天' '3' $productX.nearExpiryDays
    Assert-Equal 'P1-01' '食材Y温区为NORMAL' 'NORMAL' $productY.storageType

    # Create + refresh + delete proves the page/API persistence path (not only seeded rows).
    $supplierBody = @{ supplierCode = $tempSupplierCode; supplierName = 'P1临时供应商'; contactName = '测试'; contactPhone = '13800009999'; status = 'ACTIVE'; remark = 'P1 API probe' }
    $supplierAdd = Invoke-Api 'POST' '/fresh/suppliers/add' $hq.token $supplierBody
    Save-Exchange 'supplier-add' $supplierBody $supplierAdd
    Assert-True 'P1-01' '通过真实接口新增供应商成功' ($supplierAdd.body.success -eq $true) $supplierAdd.body.message
    $tempSupplierId = [string]$supplierAdd.body.result.id
    if ($tempSupplierId) { $createdSupplierIds += $tempSupplierId }
    $supplierRead = Invoke-Api 'GET' ("/fresh/suppliers/queryById?id=" + [uri]::EscapeDataString($tempSupplierId)) $hq.token
    Assert-Equal 'P1-01' '刷新后读取到新增供应商名称' 'P1临时供应商' $supplierRead.body.result.supplierName

    $storeBody = @{ storeCode = $tempStoreCode; storeName = 'P1临时门店'; address = '上海市测试路9号'; contactName = '测试'; contactPhone = '13900009999'; status = 'ACTIVE'; remark = 'P1 API probe' }
    $storeAdd = Invoke-Api 'POST' '/fresh/stores/add' $hq.token $storeBody
    Save-Exchange 'store-add' $storeBody $storeAdd
    Assert-True 'P1-01' '通过真实接口新增门店成功' ($storeAdd.body.success -eq $true) $storeAdd.body.message
    $tempStoreId = [string]$storeAdd.body.result.id
    if ($tempStoreId) { $createdStoreIds += $tempStoreId }
    $storeRead = Invoke-Api 'GET' ("/fresh/stores/queryById?id=" + [uri]::EscapeDataString($tempStoreId)) $hq.token
    Assert-Equal 'P1-01' '刷新后读取到新增门店地址' '上海市测试路9号' $storeRead.body.result.address

    # ------------------------------ P1-02 validation ------------------------------
    $countsP102Before = Invoke-Db "SELECT CONCAT('suppliers=',COUNT(*)) FROM fresh_supplier UNION ALL SELECT CONCAT('stores=',COUNT(*)) FROM fresh_store UNION ALL SELECT CONCAT('products=',COUNT(*)) FROM wms_products;"
    $duplicateSupplier = Invoke-Api 'POST' '/fresh/suppliers/add' $hq.token @{ supplierCode = 'S1'; supplierName = '重复编码'; status = 'ACTIVE' }
    Save-Exchange 'supplier-duplicate' @{ supplierCode = 'S1'; supplierName = '重复编码'; status = 'ACTIVE' } $duplicateSupplier
    Assert-True 'P1-02' '重复供应商编码被拒绝' ($duplicateSupplier.body.success -eq $false) $duplicateSupplier.body.message
    $missingSupplier = Invoke-Api 'POST' '/fresh/suppliers/add' $hq.token @{ supplierCode = "FRESH-P1-NONAME-$timestamp"; supplierName = ''; status = 'ACTIVE' }
    Assert-True 'P1-02' '缺少供应商名称被拒绝' ($missingSupplier.body.success -eq $false) $missingSupplier.body.message
    $badCodeSupplier = Invoke-Api 'POST' '/fresh/suppliers/add' $hq.token @{ supplierCode = 'S 1'; supplierName = '非法编码'; status = 'ACTIVE' }
    Assert-True 'P1-02' '非法供应商编码被拒绝' ($badCodeSupplier.body.success -eq $false) $badCodeSupplier.body.message
    $missingStoreAddress = Invoke-Api 'POST' '/fresh/stores/add' $hq.token @{ storeCode = "FRESH-P1-NOADDR-$timestamp"; storeName = '无地址门店'; address = ''; status = 'ACTIVE' }
    Assert-True 'P1-02' '缺少门店地址被拒绝' ($missingStoreAddress.body.success -eq $false) $missingStoreAddress.body.message

    $badProductBase = @{ productName = 'P1非法食材'; productCode = "FRESH-P1-BAD-$timestamp"; ownerId = 'fresh_p1_owner'; categoryId = '0'; productSpec = '1kg/袋'; unit = '袋'; shelfLife = 7; storageType = 'CHILLED'; nearExpiryDays = 3; status = 'ACTIVE'; isExpiryControlled = 1 }
    $negativeBody = $badProductBase.Clone()
    $negativeBody['nearExpiryDays'] = -1
    $negativeNearExpiry = Invoke-Api 'POST' '/goods/wmsProducts/add' $hq.token $negativeBody
    Save-Exchange 'product-negative-near-expiry' $negativeBody $negativeNearExpiry
    Assert-True 'P1-02' '负临期阈值被后端拒绝' ($negativeNearExpiry.body.success -eq $false) $negativeNearExpiry.body.message
    $missingStorageBody = $badProductBase.Clone()
    $missingStorageBody['storageType'] = $null
    $missingStorage = Invoke-Api 'POST' '/goods/wmsProducts/add' $hq.token $missingStorageBody
    Assert-True 'P1-02' '缺少温区被后端拒绝' ($missingStorage.body.success -eq $false) $missingStorage.body.message
    $duplicateProductBody = $badProductBase.Clone()
    $duplicateProductBody['productCode'] = 'FRESH-X'
    $duplicateProductBody['productName'] = '重复食材'
    $duplicateProduct = Invoke-Api 'POST' '/goods/wmsProducts/add' $hq.token $duplicateProductBody
    Save-Exchange 'product-duplicate' $duplicateProductBody $duplicateProduct
    Assert-True 'P1-02' '重复食材编码被拒绝' ($duplicateProduct.body.success -eq $false) $duplicateProduct.body.message

    $countsP102After = Invoke-Db "SELECT CONCAT('suppliers=',COUNT(*)) FROM fresh_supplier UNION ALL SELECT CONCAT('stores=',COUNT(*)) FROM fresh_store UNION ALL SELECT CONCAT('products=',COUNT(*)) FROM wms_products;"
    Assert-Equal 'P1-02' '非法请求未新增脏数据' ($countsP102Before -join ';') ($countsP102After -join ';')

    $uniqueIndexCount = [string](Invoke-Db "SELECT COUNT(DISTINCT CONCAT(table_name,'.',index_name)) FROM information_schema.statistics WHERE table_schema=DATABASE() AND ((table_name='fresh_supplier' AND index_name='uk_fresh_supplier_code') OR (table_name='fresh_store' AND index_name='uk_fresh_store_code') OR (table_name='fresh_user_store' AND index_name='uk_fresh_user_store_user') OR (table_name='wms_products' AND index_name='wms_products__uindex01'));")[0]
    Assert-Equal 'P1-02' '供应商/门店/用户绑定/食材编码均有数据库唯一索引' '4' $uniqueIndexCount
    $productUniqueColumns = [string](Invoke-Db "SELECT GROUP_CONCAT(column_name ORDER BY seq_in_index) FROM information_schema.statistics WHERE table_schema=DATABASE() AND table_name='wms_products' AND index_name='wms_products__uindex01';")[0]
    Assert-Equal 'P1-02' '食材唯一键为owner_id+product_code' 'owner_id,product_code' $productUniqueColumns
    $checkCount = [string](Invoke-Db "SELECT COUNT(*) FROM information_schema.table_constraints WHERE constraint_schema=DATABASE() AND constraint_name IN ('chk_fresh_near_expiry','chk_fresh_storage_type','chk_fresh_zone_storage_type');")[0]
    Assert-Equal 'P1-02' '临期阈值/温区CHECK约束已建立' '3' $checkCount
    & $mysql --no-defaults --host=127.0.0.1 --port=3306 "--user=$($dbConfig.username)" "--database=$databaseName" -e "INSERT INTO fresh_supplier (id,supplier_code,supplier_name,status) VALUES ('probe-dup-$timestamp','S1','数据库重复','ACTIVE');" 2>&1 | Out-Null
    $directDuplicateExit = $LASTEXITCODE
    Assert-True 'P1-02' '直接SQL插入重复编码被数据库唯一约束拒绝' ($directDuplicateExit -ne 0) "exit=$directDuplicateExit"
    $probeDupRows = [string](Invoke-Db "SELECT COUNT(*) FROM fresh_supplier WHERE id='probe-dup-$timestamp';")[0]
    Assert-Equal 'P1-02' '数据库拒绝后无残留行' '0' $probeDupRows

    # ------------------------------ P1-03 disable / reference protection ------------------------------
    $supplier2Body = @{ supplierCode = $tempSupplier2; supplierName = 'P1禁用供应商'; status = 'ACTIVE' }
    $supplier2Add = Invoke-Api 'POST' '/fresh/suppliers/add' $hq.token $supplier2Body
    $supplier2Id = [string]$supplier2Add.body.result.id
    if ($supplier2Id) { $createdSupplierIds += $supplier2Id }
    $supplier2Edit = Invoke-Api 'POST' '/fresh/suppliers/edit' $hq.token @{ id = $supplier2Id; supplierCode = $tempSupplier2; supplierName = 'P1禁用供应商'; status = 'INACTIVE' }
    Assert-True 'P1-03' '供应商可禁用' ($supplier2Edit.body.success -eq $true) $supplier2Edit.body.message
    $supplier2Read = Invoke-Api 'GET' ("/fresh/suppliers/queryById?id=" + [uri]::EscapeDataString($supplier2Id)) $hq.token
    Assert-Equal 'P1-03' '禁用后旧供应商仍可查询' 'INACTIVE' $supplier2Read.body.result.status
    $supplier2Delete = Invoke-Api 'DELETE' ("/fresh/suppliers/delete?id=" + [uri]::EscapeDataString($supplier2Id)) $hq.token
    Assert-True 'P1-03' '未被引用的禁用供应商可删除' ($supplier2Delete.body.success -eq $true) $supplier2Delete.body.message
    $createdSupplierIds = @($createdSupplierIds | Where-Object { $_ -ne $supplier2Id })

    $store2Body = @{ storeCode = $tempStore2; storeName = 'P1禁用门店'; address = '上海市测试路10号'; status = 'ACTIVE' }
    $store2Add = Invoke-Api 'POST' '/fresh/stores/add' $hq.token $store2Body
    $store2Id = [string]$store2Add.body.result.id
    if ($store2Id) { $createdStoreIds += $store2Id }
    $store2Edit = Invoke-Api 'POST' '/fresh/stores/edit' $hq.token @{ id = $store2Id; storeCode = $tempStore2; storeName = 'P1禁用门店'; address = '上海市测试路10号'; status = 'INACTIVE' }
    Assert-True 'P1-03' '门店可禁用' ($store2Edit.body.success -eq $true) $store2Edit.body.message
    $bindingBefore = [string](Invoke-Db "SELECT IFNULL(MAX(s.store_code),'') FROM fresh_user_store f JOIN fresh_store s ON s.id=f.store_id JOIN sys_user u ON u.id=f.user_id WHERE u.username='fresh_store_b';")[0]
    $bindDisabled = Invoke-Api 'POST' '/fresh/userStores/bind' $hq.token @{ userId = $storeB.userId; storeId = $store2Id }
    Save-Exchange 'binding-disabled-store' @{ userId = $storeB.userId; storeId = $store2Id } $bindDisabled
    Assert-True 'P1-03' '禁用门店不能用于新绑定' ($bindDisabled.body.success -eq $false) $bindDisabled.body.message
    $bindingAfter = [string](Invoke-Db "SELECT IFNULL(MAX(s.store_code),'') FROM fresh_user_store f JOIN fresh_store s ON s.id=f.store_id JOIN sys_user u ON u.id=f.user_id WHERE u.username='fresh_store_b';")[0]
    Assert-Equal 'P1-03' '禁用绑定失败后既有绑定未改变' $bindingBefore $bindingAfter

    $productXFull = (Invoke-Api 'GET' ("/goods/wmsProducts/queryById?id=fresh_p1_product_x") $hq.token).body.result
    $productXFull.status = 'INACTIVE'
    $productDisable = Invoke-Api 'POST' '/goods/wmsProducts/edit' $hq.token $productXFull
    Assert-True 'P1-03' '食材可禁用' ($productDisable.body.success -eq $true) $productDisable.body.message
    $productXDisabled = (Invoke-Api 'GET' '/goods/wmsProducts/queryById?id=fresh_p1_product_x' $hq.token).body.result
    Assert-Equal 'P1-03' '禁用后食材仍可查询' 'INACTIVE' $productXDisabled.status
    $productXDisabled.status = 'ACTIVE'
    $productEnable = Invoke-Api 'POST' '/goods/wmsProducts/edit' $hq.token $productXDisabled
    Assert-True 'P1-03' '演示食材恢复启用' ($productEnable.body.success -eq $true) $productEnable.body.message

    $referencedProductId = [string](Invoke-Db "SELECT product_id FROM wms_inventory GROUP BY product_id HAVING SUM(stock_quantity)>0 ORDER BY product_id LIMIT 1;")[0]
    $deleteReferencedProduct = Invoke-Api 'DELETE' ("/goods/wmsProducts/delete?id=" + [uri]::EscapeDataString($referencedProductId)) $hq.token
    Save-Exchange 'delete-referenced-product' @{ id = $referencedProductId } $deleteReferencedProduct
    Assert-True 'P1-03' '被库存引用的食材不能删除' ($deleteReferencedProduct.body.success -eq $false) $deleteReferencedProduct.body.message
    $referencedStillThere = [string](Invoke-Db "SELECT COUNT(*) FROM wms_products WHERE id='$referencedProductId';")[0]
    Assert-Equal 'P1-03' '引用保护失败后食材行仍在' '1' $referencedStillThere

    $deleteBoundStore = Invoke-Api 'DELETE' '/fresh/stores/delete?id=fresh_p1_store_a' $hq.token
    Assert-True 'P1-03' '被用户绑定的门店不能删除' ($deleteBoundStore.body.success -eq $false) $deleteBoundStore.body.message
    $storeAStillThere = [string](Invoke-Db "SELECT COUNT(*) FROM fresh_store WHERE id='fresh_p1_store_a';")[0]
    Assert-Equal 'P1-03' '门店引用保护失败后门店行仍在' '1' $storeAStillThere

    # ------------------------------ P1-04 role isolation ------------------------------
    $storeAList = Invoke-Api 'GET' '/fresh/stores/list?pageNo=1&pageSize=50' $storeA.token
    $storeARecords = @($storeAList.body.result.records)
    Assert-Equal 'P1-04' '门店A只能看到1条本店记录' '1' $storeARecords.Count
    Assert-Equal 'P1-04' '门店A看到的是A店' 'A' $storeARecords[0].storeCode
    $storeBList = Invoke-Api 'GET' '/fresh/stores/list?pageNo=1&pageSize=50' $storeB.token
    Assert-Equal 'P1-04' '门店B只看到B店' 'B' @($storeBList.body.result.records)[0].storeCode

    $storeACross = Invoke-Api 'GET' '/fresh/stores/queryById?id=fresh_p1_store_b' $storeA.token
    Assert-True 'P1-04' '门店A直接查询B店被拒绝' ($storeACross.http -eq 403 -or $storeACross.body.success -eq $false) "http=$($storeACross.http) message=$($storeACross.body.message)"
    $storeAOwn = Invoke-Api 'GET' '/fresh/stores/queryById?id=fresh_p1_store_a' $storeA.token
    Assert-True 'P1-04' '门店A可查询本店' ($storeAOwn.body.success -eq $true) $storeAOwn.body.message

    $storeAEdit = Invoke-Api 'POST' '/fresh/stores/edit' $storeA.token @{ id = 'fresh_p1_store_a'; storeCode = 'A'; storeName = '被篡改'; address = 'x'; status = 'ACTIVE' }
    Assert-True 'P1-04' '门店A直接调用门店编辑被拒绝' ($storeAEdit.http -eq 403 -or $storeAEdit.body.success -eq $false) "http=$($storeAEdit.http)"
    $storeANameAfter = [string](Invoke-Db "SELECT store_name FROM fresh_store WHERE id='fresh_p1_store_a';")[0]
    Assert-Equal 'P1-04' '越权编辑失败后门店名未改变' '门店A' $storeANameAfter

    $storeAProductAdd = Invoke-Api 'POST' '/goods/wmsProducts/add' $storeA.token @{ productName = '越权食材'; productCode = "FRESH-P1-HACK-$timestamp"; ownerId = 'fresh_p1_owner'; productSpec = 'x'; unit = '袋'; shelfLife = 7; storageType = 'CHILLED'; nearExpiryDays = 1; status = 'ACTIVE' }
    Assert-True 'P1-04' '门店A调用旧商品新增接口被拒绝' ($storeAProductAdd.http -eq 403 -or $storeAProductAdd.body.success -eq $false) "http=$($storeAProductAdd.http)"
    $storeAInventory = Invoke-Api 'GET' '/inventory/wmsInventory/list?pageNo=1&pageSize=5' $storeA.token
    Assert-True 'P1-04' '门店A调用旧库存查询接口被拒绝' ($storeAInventory.http -eq 403 -or $storeAInventory.body.success -eq $false) "http=$($storeAInventory.http)"
    $storeAWarehouseEdit = Invoke-Api 'POST' '/warehouse/wmsWarehouses/edit' $storeA.token @{ id = '1910288755375820801'; warehouseCode = 'A1'; warehouseName = '被篡改仓库'; warehouseAttr = 'RAW_MATERIAL'; status = 'ACTIVE' }
    Assert-True 'P1-04' '门店A直接调用仓库编辑接口被拒绝' ($storeAWarehouseEdit.http -eq 403 -or $storeAWarehouseEdit.body.success -eq $false) "http=$($storeAWarehouseEdit.http)"
    $storeAImport = Invoke-Api 'POST' '/goods/wmsProducts/importExcel' $storeA.token @{ }
    Assert-True 'P1-04' '门店A调用旧导入接口被拒绝' ($storeAImport.http -eq 403 -or $storeAImport.body.success -eq $false) "http=$($storeAImport.http)"
    $storeAUserEdit = Invoke-Api 'PUT' '/sys/user/edit' $storeA.token @{ id = $storeA.userId; username = 'fresh_store_a'; realname = '门店A用户' }
    Assert-True 'P1-04' '门店A直接调用系统用户编辑被拒绝' ($storeAUserEdit.http -eq 403 -or $storeAUserEdit.body.success -eq $false) "http=$($storeAUserEdit.http)"
    $storeAUserList = Invoke-Api 'GET' '/sys/user/list?pageNo=1&pageSize=5' $storeA.token
    Assert-True 'P1-04' '门店A调用系统用户列表被拒绝' ($storeAUserList.http -eq 403 -or $storeAUserList.body.success -eq $false) "http=$($storeAUserList.http)"
    $storeASelfBind = Invoke-Api 'POST' '/fresh/userStores/bind' $storeA.token @{ userId = $storeA.userId; storeId = 'fresh_p1_store_b' }
    Save-Exchange 'store-self-bind-attempt' @{ userId = $storeA.userId; storeId = 'fresh_p1_store_b' } $storeASelfBind
    Assert-True 'P1-04' '门店A不能自改绑定门店' ($storeASelfBind.http -eq 403 -or $storeASelfBind.body.success -eq $false) "http=$($storeASelfBind.http)"
    $storeABinding = [string](Invoke-Db "SELECT s.store_code FROM fresh_user_store f JOIN fresh_store s ON s.id=f.store_id WHERE f.user_id='$($storeA.userId)';")[0]
    Assert-Equal 'P1-04' '越权自改失败后绑定仍为A' 'A' $storeABinding
    $storeASupplier = Invoke-Api 'GET' '/fresh/suppliers/list?pageNo=1&pageSize=5' $storeA.token
    Assert-True 'P1-04' '门店A不能读取供应商基础资料' ($storeASupplier.http -eq 403 -or $storeASupplier.body.success -eq $false) "http=$($storeASupplier.http)"

    $menuCall = Invoke-Api 'GET' '/sys/permission/getUserPermissionByToken' $storeA.token
    $menuJson = $menuCall.raw
    Assert-True 'P1-04' '门店菜单包含我的门店' ($menuJson -match '/fresh/my-store') 'menu contains /fresh/my-store'
    Assert-True 'P1-04' '门店菜单不包含旧商品管理' ($menuJson -notmatch '/goods/wmsProductsList') 'menu excludes /goods/wmsProductsList'

    $warehouseUserList = Invoke-Api 'GET' '/sys/user/list?pageNo=1&pageSize=5' $warehouse.token
    Assert-True 'P1-04' '仓管不能访问系统用户管理' ($warehouseUserList.http -eq 403 -or $warehouseUserList.body.success -eq $false) "http=$($warehouseUserList.http)"
    $warehouseSupplierList = Invoke-Api 'GET' '/fresh/suppliers/list?pageNo=1&pageSize=5' $warehouse.token
    Assert-True 'P1-04' '仓管可维护基础资料' ($warehouseSupplierList.body.success -eq $true) $warehouseSupplierList.body.message

    # HQ can change a binding; the store user cannot. Restore it afterwards.
    $store3Body = @{ storeCode = $tempStore3; storeName = 'P1临时改绑门店'; address = '上海市测试路11号'; status = 'ACTIVE' }
    $store3Add = Invoke-Api 'POST' '/fresh/stores/add' $hq.token $store3Body
    $store3Id = [string]$store3Add.body.result.id
    if ($store3Id) { $createdStoreIds += $store3Id }
    $hqRebind = Invoke-Api 'POST' '/fresh/userStores/bind' $hq.token @{ userId = $storeB.userId; storeId = $store3Id }
    Assert-True 'P1-04' '总部可改绑门店用户' ($hqRebind.body.success -eq $true) $hqRebind.body.message
    $reboundCode = [string](Invoke-Db "SELECT s.store_code FROM fresh_user_store f JOIN fresh_store s ON s.id=f.store_id WHERE f.user_id='$($storeB.userId)';")[0]
    Assert-Equal 'P1-04' '总部改绑后数据库为新门店' $tempStore3 $reboundCode
    $restoreBind = Invoke-Api 'POST' '/fresh/userStores/bind' $hq.token @{ userId = $storeB.userId; storeId = 'fresh_p1_store_b' }
    Assert-True 'P1-04' '总部恢复门店B绑定' ($restoreBind.body.success -eq $true) $restoreBind.body.message

    # ------------------------------ P1-05 migration/menu consistency ------------------------------
    $menuRows = [string](Invoke-Db "SELECT COUNT(*) FROM sys_permission WHERE id LIKE 'fresh_p1_%' AND del_flag=0;")[0]
    Assert-Equal 'P1-05' 'P1菜单/按钮共17条且无重复' '17' $menuRows
    $roleRows = [string](Invoke-Db "SELECT COUNT(*) FROM sys_role WHERE id LIKE 'fresh_p1_role_%';")[0]
    Assert-Equal 'P1-05' 'P1角色共3条' '3' $roleRows
    $dictRows = [string](Invoke-Db "SELECT COUNT(*) FROM sys_dict_item WHERE id LIKE 'fresh_p1_di_%';")[0]
    Assert-Equal 'P1-05' 'P1字典项共5条' '5' $dictRows
    $grantDupes = [string](Invoke-Db "SELECT COUNT(*) FROM (SELECT role_id, permission_id FROM sys_role_permission WHERE role_id LIKE 'fresh_p1_role_%' GROUP BY role_id, permission_id HAVING COUNT(*)>1) d;")[0]
    Assert-Equal 'P1-05' 'FreshLink角色授权无重复' '0' $grantDupes
    $ledger = [string](Invoke-Db "SELECT COUNT(*) FROM fresh_schema_migration WHERE version IN ('P1.00','P1.10','P1.20');")[0]
    Assert-Equal 'P1-05' '迁移账本记录3个P1版本' '3' $ledger
    $oldOutorderMenu = [string](Invoke-Db "SELECT COUNT(*) FROM sys_permission WHERE url LIKE '/outorder%' AND del_flag=0;")[0]
    Assert-True 'P1-05' '旧出库菜单仍存在' ([int]$oldOutorderMenu -gt 0) $oldOutorderMenu
    $oldOutorderApi = Invoke-Api 'GET' '/outorder/wmsOutOrders/list?pageNo=1&pageSize=5' $hq.token
    Assert-True 'P1-05' '旧出库页面接口仍可读' ($oldOutorderApi.body.success -eq $true) $oldOutorderApi.body.message

    # Temp supplier/store rows are cleaned up in finally; compare final counts there.
} catch {
    $script:probeError = $_.Exception.Message
    throw
} finally {
    if ($hq) {
        if ($storeB) {
            Invoke-Api 'POST' '/fresh/userStores/bind' $hq.token @{ userId = $storeB.userId; storeId = 'fresh_p1_store_b' } | Out-Null
        }
        foreach ($id in $createdSupplierIds) {
            if ($id) { Invoke-Api 'DELETE' ("/fresh/suppliers/delete?id=" + [uri]::EscapeDataString($id)) $hq.token | Out-Null }
        }
        foreach ($id in $createdStoreIds) {
            if ($id) { Invoke-Api 'DELETE' ("/fresh/stores/delete?id=" + [uri]::EscapeDataString($id)) $hq.token | Out-Null }
        }
    }
    $cleanupCounts = Invoke-Db "SELECT CONCAT('suppliers=',COUNT(*)) FROM fresh_supplier UNION ALL SELECT CONCAT('stores=',COUNT(*)) FROM fresh_store UNION ALL SELECT CONCAT('bindings=',COUNT(*)) FROM fresh_user_store UNION ALL SELECT CONCAT('products=',COUNT(*)) FROM wms_products;"
    if ($countsBefore) {
        Assert-Equal 'P1-03' '清理临时数据后基础资料计数恢复' ($countsBefore -join ';') ($cleanupCounts -join ';')
    }

    $script:assertions | Export-Csv -LiteralPath (Join-Path $evidencePath 'assertions.tsv') -NoTypeInformation -Delimiter "`t" -Encoding utf8
    $summary = [ordered]@{
        executedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        apiRoot = $apiRoot
        database = $databaseName
        totalAssertions = $script:total
        passed = $script:passed
        failed = $script:total - $script:passed
        abortedWithError = $script:probeError
        failures = $script:failures
        conclusion = if (!$script:probeError -and $script:total -eq $script:passed) { 'PASS' } else { 'FAIL' }
    }
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $evidencePath 'api-probe-summary.json') -Encoding utf8
    $lines = @(
        '# P1 API / database probe',
        '',
        "- Endpoint: ``$apiRoot``",
        "- Isolated database: ``$databaseName``",
        "- Time: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) (Asia/Shanghai)",
        "- Assertions executed: $($script:total); passed: $($script:passed); failed: $($script:total - $script:passed)",
        "- Conclusion: $($summary.conclusion)",
        '',
        'Per-case results are in `assertions.tsv`; key request/response exchanges are saved as `*.json` with tokens and passwords excluded.'
    )
    if ($script:failures.Count -gt 0) {
        $lines += ''
        $lines += '## Failures'
        foreach ($failure in $script:failures) {
            $lines += "- $($failure.id) $($failure.assertion): expected ``$($failure.expected)``, actual ``$($failure.actual)``"
        }
    }
    if ($script:probeError) {
        $lines += ''
        $lines += "## Aborted"
        $lines += "- $($script:probeError)"
    }
    $lines | Set-Content -LiteralPath (Join-Path $evidencePath 'api-probe.md') -Encoding utf8
    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
    if (!$script:probeError -and $script:total -ne $script:passed) { throw "P1 API probe failed: $($script:total - $script:passed) of $($script:total) assertions failed." }
    Write-Output "P1 API probe PASS: $($script:passed)/$($script:total) assertions. Evidence: $evidencePath"
}
