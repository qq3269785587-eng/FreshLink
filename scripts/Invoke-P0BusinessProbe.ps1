param([string]$EvidenceDirectory)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')

$databaseName = 'freshlink_p0_codex_20261117_b'
$apiRoot = 'http://127.0.0.1:18080/jeecg-boot'
$loginConfigPath = Join-Path $FreshLinkConfig 'p0-test-login.json'
$rootConfigPath = Join-Path $FreshLinkConfig 'mysql-local-credentials.txt'
$mysqlExe = 'D:\Yuki\MySQL\bin\mysql.exe'
$redisCli = Join-Path $FreshLinkRuntime 'redis\bin\Redis-7.4.11-Windows-x64-msys2\redis-cli.exe'
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path (Join-Path $FreshLinkRoot 'work\fresh-acceptance\P0\attempt-01\api') ('run-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$evidenceDirectory = if ([IO.Path]::IsPathRooted($EvidenceDirectory)) { [IO.Path]::GetFullPath($EvidenceDirectory) } else { [IO.Path]::GetFullPath((Join-Path $FreshLinkRoot $EvidenceDirectory)) }
$allowedEvidenceRoot = [IO.Path]::GetFullPath((Join-Path $FreshLinkRoot 'work')) + [IO.Path]::DirectorySeparatorChar
if (!$evidenceDirectory.StartsWith($allowedEvidenceRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'API evidence must remain inside project work/.' }
New-Item -ItemType Directory -Force -Path $evidenceDirectory | Out-Null
$stepLogPath = Join-Path $evidenceDirectory 'business-probe-steps.tsv'

if (!(Test-Path -LiteralPath $loginConfigPath) -or !(Test-Path -LiteralPath $rootConfigPath)) { throw 'P0 local test credentials are missing.' }
$loginConfig = Get-Content -LiteralPath $loginConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
$rootConfig = Get-Content -LiteralPath $rootConfigPath
$rootUserLine = $rootConfig | Where-Object { $_.StartsWith('username=') } | Select-Object -First 1
$rootPasswordLine = $rootConfig | Where-Object { $_.StartsWith('password=') } | Select-Object -First 1
if (!$rootUserLine -or !$rootPasswordLine) { throw 'Local MySQL configuration is incomplete.' }
$rootUsername = $rootUserLine.Substring(9)

function Invoke-RootQuery([string]$Sql) {
    $env:MYSQL_PWD = $rootPasswordLine.Substring(9)
    try {
        $output = & $mysqlExe --no-defaults --host=127.0.0.1 --user=$rootUsername --database=$databaseName --batch --raw --skip-column-names -e $Sql 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'Isolated database query failed.' }
        return $output
    }
    finally { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }
}

function Get-TableCounts {
    $query = "SELECT CONCAT('wms_products=',COUNT(*)) FROM wms_products UNION ALL SELECT CONCAT('wms_stock_in_orders=',COUNT(*)) FROM wms_stock_in_orders UNION ALL SELECT CONCAT('wms_stock_in_order_items=',COUNT(*)) FROM wms_stock_in_order_items UNION ALL SELECT CONCAT('wms_tasks=',COUNT(*)) FROM wms_tasks UNION ALL SELECT CONCAT('wms_tasks_records=',COUNT(*)) FROM wms_tasks_records UNION ALL SELECT CONCAT('wms_inventory=',COUNT(*)) FROM wms_inventory UNION ALL SELECT CONCAT('wms_inventory_trans=',COUNT(*)) FROM wms_inventory_trans UNION ALL SELECT CONCAT('wms_out_orders=',COUNT(*)) FROM wms_out_orders UNION ALL SELECT CONCAT('wms_out_orders_items=',COUNT(*)) FROM wms_out_orders_items UNION ALL SELECT CONCAT('wms_out_orders_allocation=',COUNT(*)) FROM wms_out_orders_allocation UNION ALL SELECT CONCAT('wms_wave_master=',COUNT(*)) FROM wms_wave_master UNION ALL SELECT CONCAT('wms_wave_sku_summary=',COUNT(*)) FROM wms_wave_sku_summary UNION ALL SELECT CONCAT('wms_shipment=',COUNT(*)) FROM wms_shipment UNION ALL SELECT CONCAT('wms_shipment_detail=',COUNT(*)) FROM wms_shipment_detail;"
    return @(Invoke-RootQuery $query)
}

function Write-Step([string]$Step, [string]$Method, [string]$Path, [bool]$Success, [string]$Code, [string]$Message, [string]$Detail = '') {
    $safeMessage = ($Message -replace '[\r\n\t]+',' ').Trim()
    $safeDetail = ($Detail -replace '[\r\n\t]+',' ').Trim()
    [pscustomobject]@{ step = $Step; method = $Method; path = $Path; success = $Success; code = $Code; message = $safeMessage; detail = $safeDetail } |
        Export-Csv -LiteralPath $stepLogPath -NoTypeInformation -Append -Delimiter "`t" -Encoding utf8
}

function Save-DemoExchange([string]$Name, $Request, $Call) {
    $payload = [ordered]@{ request = $Request; http = $Call.http; response = $Call.response; error = $Call.error }
    $payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $evidenceDirectory ($Name + '.json')) -Encoding utf8
}

function Invoke-FreshApi([string]$Method, [string]$Path, [hashtable]$Headers, $Body = $null, [string]$ContentType = 'application/json') {
    $uri = "$apiRoot$Path"
    try {
        if ($null -eq $Body) {
            $response = Invoke-RestMethod -Uri $uri -Method $Method -Headers $Headers -TimeoutSec 30
        } elseif ($ContentType -eq 'application/json') {
            $response = Invoke-RestMethod -Uri $uri -Method $Method -Headers $Headers -ContentType $ContentType -Body ($Body | ConvertTo-Json -Depth 12 -Compress) -TimeoutSec 30
        } else {
            $response = Invoke-RestMethod -Uri $uri -Method $Method -Headers $Headers -ContentType $ContentType -Body $Body -TimeoutSec 30
        }
        return [pscustomobject]@{ http = 200; response = $response; error = '' }
    }
    catch {
        $httpStatus = 0
        $errorBody = ''
        if ($_.Exception.Response) {
            try { $httpStatus = [int]$_.Exception.Response.StatusCode } catch {}
            try {
                $reader = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errorBody = $reader.ReadToEnd()
            } catch {}
        }
        $message = $_.Exception.Message
        if ($errorBody) {
            try { $parsed = $errorBody | ConvertFrom-Json; $message = [string]$parsed.message } catch {}
        }
        return [pscustomobject]@{ http = $httpStatus; response = $null; error = $message }
    }
}

function Stop-OnFailure([string]$Step, [string]$Method, [string]$Path, $Call, [string]$Details = '') {
    $ok = $Call.http -ge 200 -and $Call.http -lt 300 -and $Call.response -and $Call.response.success -eq $true
    $code = if ($Call.response) { [string]$Call.response.code } else { [string]$Call.http }
    $message = if ($Call.response) { [string]$Call.response.message } else { [string]$Call.error }
    Write-Step $Step $Method $Path $ok $code $message $Details
    if (!$ok) {
        $script:FirstFailure = [pscustomobject]@{ step = $Step; method = $Method; path = $Path; http = $Call.http; code = $code; message = $message }
        throw "P0 business probe first failure: $Step — $message"
    }
    return $Call.response
}

if (Test-Path -LiteralPath $stepLogPath) { throw 'Refusing to overwrite prior P0 API evidence; use a new attempt directory.' }
$initialCounts = Get-TableCounts
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$demoPrefix = "FRESH_DEMO_P0_$timestamp"
$productCode = $demoPrefix
$productName = "$demoPrefix 鸡胸肉 1kg/袋"
$orderMarker = $demoPrefix
$dateToday = Get-Date -Format 'yyyy-MM-dd'
$arrivalTime = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$expiryDate = (Get-Date).AddDays(7).ToString('yyyy-MM-dd')
$steps = [System.Collections.Generic.List[object]]::new()
$script:FirstFailure = $null

try {
    $configPath = Join-Path $FreshLinkBackend 'jeecg-module-system\jeecg-system-start\src\main\resources\application-dev.yml'
    $yaml = Get-Content -LiteralPath $configPath -Raw -Encoding utf8
    $secretMatch = [regex]::Match($yaml, '(?m)^\s*signatureSecret:\s*(\S+)')
    if (!$secretMatch.Success) { throw 'P0 test profile signature secret is unavailable.' }
    $captcha = 'P0A7'
    $checkKey = [Guid]::NewGuid().ToString('N')
    $prefixBytes = [Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($checkKey + $secretMatch.Groups[1].Value))
    $prefix = [BitConverter]::ToString($prefixBytes).Replace('-', '').ToLowerInvariant()
    $captchaKey = $prefix + $captcha.ToLowerInvariant()
    $captchaJson = ConvertTo-Json -InputObject $captcha.ToLowerInvariant() -Compress
    $redisOutput = & $redisCli -h 127.0.0.1 -p 6379 -n 15 SET $captchaKey $captchaJson EX 60
    if ($LASTEXITCODE -ne 0 -or $redisOutput -ne 'OK') { throw 'Could not install one-use captcha fixture in isolated Redis DB 15.' }
    $loginBody = @{ username = $loginConfig.username; password = $loginConfig.password; captcha = $captcha; checkKey = $checkKey }
    $loginCall = Invoke-FreshApi 'POST' '/sys/login' @{ Version = 'v3' } $loginBody
    $login = Stop-OnFailure 'test-auth-with-one-use-Redis-captcha-fixture' 'POST' '/sys/login' $loginCall 'captcha stored as a JSON-serialized string in DB 15; token kept in memory only'
    $token = [string]$login.result.token
    $userId = [string]$login.result.userInfo.id
    if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($userId)) { throw 'Login succeeded but token/user id fields were missing.' }
    $headers = @{ Authorization = $token; 'X-Access-Token' = $token; Version = 'v3' }

    $ownersCall = Invoke-FreshApi 'GET' '/goods/wmsCargoOwners/list?pageNo=1&pageSize=100' $headers
    $ownersPage = Stop-OnFailure 'read-existing-cargo-owners' 'GET' '/goods/wmsCargoOwners/list' $ownersCall
    $owners = @($ownersPage.result.records | Where-Object { $_.id })
    if (!$owners.Count) { throw 'No existing cargo owner is available for the P0 demo SKU.' }
    $owner = $owners[0]

    $categoriesCall = Invoke-FreshApi 'GET' '/goods/wmsProductCategories/rootList?pageNo=1&pageSize=100' $headers
    $categoriesPage = Stop-OnFailure 'read-existing-product-categories' 'GET' '/goods/wmsProductCategories/rootList' $categoriesCall
    $categories = @($categoriesPage.result.records | Where-Object { $_.id -and $_.categoryCode })
    if (!$categories.Count) { throw 'No existing product category with a category code is available.' }
    $category = $categories[0]

    $warehouseCall = Invoke-FreshApi 'GET' '/warehouse/wmsWarehouses/list?pageNo=1&pageSize=100' $headers
    $warehousesPage = Stop-OnFailure 'read-existing-warehouses' 'GET' '/warehouse/wmsWarehouses/list' $warehouseCall
    $warehouses = @($warehousesPage.result.records | Where-Object { $_.id -and $_.status -eq 'ACTIVE' })
    if (!$warehouses.Count) { throw 'No active warehouse is available for the P0 demo inbound order.' }
    $warehouse = $warehouses[0]

    $skuBody = @{
        productName = $productName; productCode = $productCode; productSpec = '1kg/袋'; packagingSpec = '1kg/袋'
        unit = '袋'; ownerId = [string]$owner.id; categoryId = [string]$category.id
        shelfLife = 7; maintenanceCycle = 0; isExpiryControlled = 1; status = 'ACTIVE'
    }
    $skuPath = '/goods/wmsProducts/add'
    $skuCall = Invoke-FreshApi 'POST' $skuPath $headers $skuBody
    Save-DemoExchange 'sku-add-exchange' $skuBody $skuCall
    $skuResponse = Stop-OnFailure 'create-FRESH_DEMO_P0-SKU' 'POST' $skuPath $skuCall 'owner and SKU supplied through existing WMS API'
    $skuLookupPath = '/goods/wmsProducts/list?pageNo=1&pageSize=100'
    $skuLookup = Invoke-FreshApi 'GET' $skuLookupPath $headers
    $skuPage = Stop-OnFailure 'confirm-FRESH_DEMO_P0-SKU' 'GET' '/goods/wmsProducts/list' $skuLookup
    $skuRows = @($skuPage.result.records | Where-Object { $_.productCode -eq $productCode })
    if ($skuRows.Count -ne 1) { throw ('P0 SKU add returned success but exact lookup yielded ' + $skuRows.Count + ' rows.') }
    $product = $skuRows[0]

    $inboundBody = @{
        orderType = 'OTHER_IN'; sourceNumber = $orderMarker; ownerId = [string]$owner.id; warehouseId = [string]$warehouse.id
        expectedArrivalTime = $arrivalTime; remarks = $orderMarker; totalExpectedQuantity = 3
    }
    $inboundAddPath = '/inorder/wmsStockInOrders/add'
    $inboundAddCall = Invoke-FreshApi 'POST' $inboundAddPath $headers $inboundBody
    Save-DemoExchange 'inbound-add-exchange' $inboundBody $inboundAddCall
    $inboundAdded = Stop-OnFailure 'create-FRESH_DEMO_P0-inbound-main' 'POST' $inboundAddPath $inboundAddCall 'controller returns generic success; detail persistence is verified separately'
    $inboundLookupPath = '/inorder/wmsStockInOrders/list?pageNo=1&pageSize=100'
    $inboundLookup = Invoke-FreshApi 'GET' $inboundLookupPath $headers
    $inboundPage = Stop-OnFailure 'lookup-FRESH_DEMO_P0-inbound' 'GET' '/inorder/wmsStockInOrders/list' $inboundLookup
    $inboundRows = @($inboundPage.result.records | Where-Object { $_.sourceNumber -eq $orderMarker })
    if ($inboundRows.Count -ne 1) { throw "Inbound add returned success but exact lookup yielded $($inboundRows.Count) rows." }
    $inbound = $inboundRows[0]

    $inboundEditPath = '/inorder/wmsStockInOrders/edit'
    $inboundEditBody = @{
        id = [string]$inbound.id; orderType = 'OTHER_IN'; sourceNumber = $orderMarker; ownerId = [string]$owner.id
        warehouseId = [string]$warehouse.id; expectedArrivalTime = $arrivalTime; status = 'INITIAL'; remarks = $orderMarker
        totalExpectedQuantity = 3; wmsStockInOrderItemsList = @(@{ productId = [string]$product.id; expectedQuantity = 3; receivedQuantity = 0; shelvedQuantity = 0; defectiveQuantity = 0; remarks = $orderMarker })
    }
    $inboundEditCall = Invoke-FreshApi 'POST' $inboundEditPath $headers $inboundEditBody
    Save-DemoExchange 'inbound-edit-exchange' $inboundEditBody $inboundEditCall
    $null = Stop-OnFailure 'add-FRESH_DEMO_P0-inbound-detail-through-normal-edit' 'POST' $inboundEditPath $inboundEditCall 'add endpoint is main-row-only; populated detail by normal edit API'
    $detailsCall = Invoke-FreshApi 'GET' "/inorder/wmsStockInOrders/queryWmsStockInOrderItemsByMainId?id=$([uri]::EscapeDataString([string]$inbound.id))" $headers
    $detailsResponse = Stop-OnFailure 'verify-inbound-detail' 'GET' '/inorder/wmsStockInOrders/queryWmsStockInOrderItemsByMainId' $detailsCall
    $details = @($detailsResponse.result)
    if ($details.Count -ne 1 -or [string]$details[0].productId -ne [string]$product.id -or [int]$details[0].expectedQuantity -ne 3) { throw 'Inbound detail API readback did not match the submitted SKU and quantity.' }

    $submitPath = '/inorder/wmsStockInOrders/submitAudit'
    $submitCall = Invoke-FreshApi 'POST' $submitPath $headers @{ id = [string]$inbound.id }
    $null = Stop-OnFailure 'submit-FRESH_DEMO_P0-inbound' 'POST' $submitPath $submitCall
    $auditPath = '/inorder/wmsStockInOrders/audit'
    $auditCall = Invoke-FreshApi 'POST' $auditPath $headers @{ id = [string]$inbound.id; status = 'APPROVED' }
    $null = Stop-OnFailure 'approve-FRESH_DEMO_P0-inbound' 'POST' $auditPath $auditCall
    $orderStateCall = Invoke-FreshApi 'GET' "/inorder/wmsStockInOrders/queryById?id=$([uri]::EscapeDataString([string]$inbound.id))" $headers
    $orderState = Stop-OnFailure 'verify-approved-inbound-state' 'GET' '/inorder/wmsStockInOrders/queryById' $orderStateCall

    $receiveTaskPath = '/inorder/receiveTasks/add'
    $receiveTaskUri = $receiveTaskPath + '?orderIds=' + [uri]::EscapeDataString([string]$inbound.id) + '&operator=' + [uri]::EscapeDataString($userId)
    $receiveTaskCall = Invoke-FreshApi 'POST' $receiveTaskUri $headers @{} 'application/x-www-form-urlencoded'
    $null = Stop-OnFailure 'create-receive-task-for-FRESH_DEMO_P0-inbound' 'POST' $receiveTaskPath $receiveTaskCall
    $taskLookupPath = '/inorder/receiveTasks/list?pageNo=1&pageSize=100'
    $taskLookup = Invoke-FreshApi 'GET' $taskLookupPath $headers
    $taskPage = Stop-OnFailure 'lookup-receive-task' 'GET' '/inorder/receiveTasks/list' $taskLookup
    $tasks = @($taskPage.result.records | Where-Object { [string]$_.stockInOrderId -eq [string]$inbound.id })
    if (!$tasks.Count) { throw 'Receive-task creation returned success but no task was found for the inbound order.' }

    $locationsPath = '/warehouse/wmsStorageLocations/list?pageNo=1&pageSize=100'
    $locationsCall = Invoke-FreshApi 'GET' $locationsPath $headers
    $locationsPage = Stop-OnFailure 'read-storage-locations-for-inbound' 'GET' '/warehouse/wmsStorageLocations/list' $locationsCall
    $locations = @($locationsPage.result.records | Where-Object { $_.locationCode -and [string]$_.warehouseId -eq [string]$warehouse.id })
    $locations | ForEach-Object { [pscustomobject]@{ locationCode = $_.locationCode; warehouseId = $_.warehouseId; isSellable = $_.isSellable; status = $_.status } } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'candidate-locations.json') -Encoding utf8
    if (!$locations.Count) { throw 'No storage location was returned for the chosen warehouse.' }
    $receivingLocation = $locations | Where-Object { [string]$_.isSellable -eq '1' } | Select-Object -First 1
    if (!$receivingLocation) { throw 'No sellable storage location is available for the GOOD receive item.' }

    $receivePath = '/inorder/receiveTasks/addRecords'
    $receiveBody = @{
        id = [string]$tasks[0].id; execQuantity = 3; targetLocationCode = [string]$receivingLocation.locationCode
        inventoryAttribute = 'GOOD_PRODUCT'; batchNumber = "$demoPrefix`_B1"; expiryDate = $expiryDate
    }
    $receiveCall = Invoke-FreshApi 'POST' $receivePath $headers $receiveBody
    Save-DemoExchange 'receive-add-record-exchange' $receiveBody $receiveCall
    $null = Stop-OnFailure 'receive-FRESH_DEMO_P0-batch' 'POST' $receivePath $receiveCall 'batch and expiry supplied through the existing receive-task API'

    $putawayTasksCall = Invoke-FreshApi 'GET' '/inorder/putawayTasks/list?pageNo=1&pageSize=100' $headers
    $putawayTasksPage = Stop-OnFailure 'lookup-putaway-task-created-by-receive' 'GET' '/inorder/putawayTasks/list' $putawayTasksCall
    $putawayTasks = @($putawayTasksPage.result.records | Where-Object {
        [string]$_.stockInOrderId -eq [string]$inbound.id -and [string]$_.taskType -eq 'PUTAWAY_TASK'
    })
    if (!$putawayTasks.Count) { throw 'Receive succeeded but did not create a putaway task for the completed inbound order.' }
    $putawayTask = $putawayTasks[0]
    $putawayLocation = $locations | Where-Object { [string]$_.isSellable -eq '1' -and $_.locationCode -ne $receivingLocation.locationCode } | Select-Object -First 1
    if (!$putawayLocation) { throw 'No second sellable location is available to test putaway.' }
    $putawayPath = '/inorder/putawayTasks/addRecords'
    $putawayBody = @{
        id = [string]$putawayTask.id; execQuantity = 3; sourceLocationCode = [string]$putawayTask.sourceLocationCode
        targetLocationCode = [string]$putawayLocation.locationCode; targetWarehouseId = [string]$warehouse.id
        productId = [string]$product.id; batchNumber = "$demoPrefix`_B1"; expiryDate = $expiryDate
    }
    $putawayCall = Invoke-FreshApi 'POST' $putawayPath $headers $putawayBody
    Save-DemoExchange 'putaway-add-record-exchange' $putawayBody $putawayCall
    $null = Stop-OnFailure 'putaway-FRESH_DEMO_P0-batch' 'POST' $putawayPath $putawayCall 'source task was generated by successful full receipt; target is a second sellable location'

    $outboundBody = @{
        orderType = 'NORMAL'; orderSource = $demoPrefix; orderSourceNo = $demoPrefix
        warehouseId = [string]$warehouse.id; ownerId = [string]$owner.id
        expectedShipTime = (Get-Date).AddHours(1).ToString('yyyy-MM-dd HH:mm:ss')
        consignee = 'FRESH_DEMO_P0'; shippingAddress = 'P0 isolation test'
        remark = $demoPrefix
    }
    $outboundAddPath = '/outorder/wmsOutOrders/add'
    $outboundAddCall = Invoke-FreshApi 'POST' $outboundAddPath $headers $outboundBody
    Save-DemoExchange 'outbound-add-exchange' $outboundBody $outboundAddCall
    $null = Stop-OnFailure 'create-FRESH_DEMO_P0-outbound-main' 'POST' $outboundAddPath $outboundAddCall
    $outboundLookup = Invoke-FreshApi 'GET' '/outorder/wmsOutOrders/list?pageNo=1&pageSize=200' $headers
    $outboundPage = Stop-OnFailure 'lookup-FRESH_DEMO_P0-outbound' 'GET' '/outorder/wmsOutOrders/list' $outboundLookup
    $outboundRows = @($outboundPage.result.records | Where-Object { $_.orderSourceNo -eq $demoPrefix })
    if ($outboundRows.Count -ne 1) { throw ('Expected one demo outbound order, found ' + $outboundRows.Count) }
    $outbound = $outboundRows[0]
    $outboundEditBody = @{
        id = [string]$outbound.id; orderType = 'NORMAL'; orderSource = $demoPrefix; orderSourceNo = $demoPrefix
        warehouseId = [string]$warehouse.id; ownerId = [string]$owner.id; status = 'CREATED'
        expectedShipTime = $outboundBody.expectedShipTime; consignee = 'FRESH_DEMO_P0'
        shippingAddress = 'P0 isolation test'; remark = $demoPrefix
        wmsOutOrdersItemsList = @(@{ skuId = [string]$product.id; expectedQuantity = 1; remarks = $demoPrefix })
    }
    $outboundEditPath = '/outorder/wmsOutOrders/edit'
    $outboundEditCall = Invoke-FreshApi 'POST' $outboundEditPath $headers $outboundEditBody
    Save-DemoExchange 'outbound-edit-exchange' $outboundEditBody $outboundEditCall
    $null = Stop-OnFailure 'add-FRESH_DEMO_P0-outbound-detail-through-normal-edit' 'POST' $outboundEditPath $outboundEditCall
    $outboundSubmitPath = '/outorder/wmsOutOrders/submitAudit?id=' + [uri]::EscapeDataString([string]$outbound.id)
    $outboundSubmitCall = Invoke-FreshApi 'POST' $outboundSubmitPath $headers
    Save-DemoExchange 'outbound-submit-exchange' @{ id = [string]$outbound.id } $outboundSubmitCall
    $null = Stop-OnFailure 'submit-FRESH_DEMO_P0-outbound' 'POST' '/outorder/wmsOutOrders/submitAudit' $outboundSubmitCall
    $outboundAuditPath = '/outorder/wmsOutOrders/audit'
    $outboundAuditBody = @{ id = [string]$outbound.id; status = 'APPROVED' }
    $outboundAuditCall = Invoke-FreshApi 'POST' $outboundAuditPath $headers $outboundAuditBody
    Save-DemoExchange 'outbound-audit-exchange' $outboundAuditBody $outboundAuditCall
    $null = Stop-OnFailure 'approve-FRESH_DEMO_P0-outbound' 'POST' $outboundAuditPath $outboundAuditCall
    $outboundStateCall = Invoke-FreshApi 'GET' ('/outorder/wmsOutOrders/queryById?id=' + [uri]::EscapeDataString([string]$outbound.id)) $headers
    $outboundState = Stop-OnFailure 'verify-approved-outbound-state' 'GET' '/outorder/wmsOutOrders/queryById' $outboundStateCall
    $allocatePath = '/outorder/wmsOutOrders/allocateStock?ids=' + [uri]::EscapeDataString([string]$outbound.id)
    $allocateCall = Invoke-FreshApi 'POST' $allocatePath $headers
    Save-DemoExchange 'outbound-allocation-exchange' @{ id = [string]$outbound.id; skuId = [string]$product.id; expectedQuantity = 1 } $allocateCall
    $allocationResult = if ($allocateCall.response) { [string]$allocateCall.response.result } else { [string]$allocateCall.error }
    $allocated = $allocationResult -match '分配库存成功\s*1条,失败0条'
    Write-Step 'allocate-FRESH_DEMO_P0-outbound-stock' 'POST' '/outorder/wmsOutOrders/allocateStock' $allocated ([string]$allocateCall.response.code) ([string]$allocateCall.response.message) $allocationResult
    if (!$allocated) { $script:FirstFailure = [pscustomobject]@{ step = 'allocate-FRESH_DEMO_P0-outbound-stock'; method = 'POST'; path = '/outorder/wmsOutOrders/allocateStock'; http = $allocateCall.http; code = [string]$allocateCall.response.code; message = $allocationResult } }
}
catch {
    if (!$script:FirstFailure) {
        $script:FirstFailure = [pscustomobject]@{ step = 'probe-setup-or-postcondition'; method = ''; path = ''; http = 0; code = 'LOCAL'; message = $_.Exception.Message }
        Write-Step 'probe-setup-or-postcondition' '' '' $false 'LOCAL' $_.Exception.Message
    }
}

$finalCounts = Get-TableCounts
$inventorySql = 'SELECT CONCAT_WS(CHAR(61),COUNT(*),COALESCE(SUM(stock_quantity),0),COALESCE(SUM(allocated_quantity),0),COALESCE(SUM(available_quantity),0),SUM(batch_number IS NULL OR batch_number=CHAR(0)),COALESCE(SUM(stock_quantity*(batch_number IS NULL OR batch_number=CHAR(0))),0)) FROM wms_inventory; SELECT CONCAT_WS(CHAR(61),COUNT(*),SUM(batch_number IS NOT NULL)) FROM wms_inventory_trans;'
$inventoryTotals = Invoke-RootQuery $inventorySql
$demoInventorySql = "SELECT CONCAT('inventory',CHAR(9),p.product_code,CHAR(9),i.product_id,CHAR(9),i.location_code,CHAR(9),i.batch_number,CHAR(9),i.stock_quantity,CHAR(9),COALESCE(i.allocated_quantity,'NULL'),CHAR(9),COALESCE(i.available_quantity,'NULL'),CHAR(9),'',CHAR(9),'') FROM wms_inventory i JOIN wms_products p ON p.id=i.product_id WHERE p.product_code='$productCode' UNION ALL SELECT CONCAT('transaction',CHAR(9),p.product_code,CHAR(9),t.product_id,CHAR(9),t.location_code,CHAR(9),COALESCE(t.batch_number,''),CHAR(9),'',CHAR(9),'',CHAR(9),'',CHAR(9),t.transaction_type,CHAR(9),t.change_quantity) FROM wms_inventory_trans t JOIN wms_products p ON p.id=t.product_id WHERE p.product_code='$productCode' ORDER BY 1,4;"
$demoInventoryRows = @(Invoke-RootQuery $demoInventorySql)
$demoInventoryHeader = @('record_type','product_code','product_id','location_code','batch_number','stock_quantity','allocated_quantity','available_quantity','transaction_type','change_quantity') -join "`t"
$demoInventoryEvidence = @($demoInventoryHeader) + $demoInventoryRows
$firstFailureLine = if ($script:FirstFailure) {
    "- 首失败：$($script:FirstFailure.step)；HTTP $($script:FirstFailure.http)；业务码 $($script:FirstFailure.code)；$($script:FirstFailure.message)"
} else { '- 首失败：本次探测范围内未发现失败。' }
$report = @(
    '# P0 原有 WMS 链路 API 探测',
    '',
    "- 时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')",
    "- 活动实例：$apiRoot（PID/JAR 与 P0 launcher 记录核对）",
    "- 数据库：$databaseName；仅通过受限 P0 应用账号写入该克隆库。",
    '- 登录：POST /sys/login；用一次性验证码 fixture 写入隔离 Redis DB15，fixture 由应用当前测试 profile 的公开配置算法生成；验证码、签名串、密码和 token 均未落盘。此方式仅用于 API 集成探测，UI 登录另有人工验证。',
    "- 唯一 SKU 标记：$productCode；入库来源标记：$orderMarker。",
    $firstFailureLine,
    '',
    '## 关键业务表前后计数',
    '',
    '```text',
    'Before:',
    ($initialCounts -join "`n"),
    'After:',
    ($finalCounts -join "`n"),
    '```',
    '',
    '## 库存汇总（克隆库）',
    '',
    '```text',
    ($inventoryTotals -join "`n"),
    '```',
    '',
    '- 逐步脱敏结果见 business-probe-steps.tsv。请求/响应中未保存密码、验证码、token、个人联系方式或原始完整登录响应。',
    '- 仅通过业务 API 创建 FRESH_DEMO_P0 SKU、入库主单、明细、审批及任务；任何 SQL 查询仅为前后计数和核验，不直接伪造/修改业务单据。',
    '- 发现的数据/状态缺口不在 P0 修复；按原有阶段归属后交 Codex 独立验收。'
)
$report | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'business-probe.md') -Encoding utf8
$initialCounts | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'business-tables-before.tsv') -Encoding utf8
$finalCounts | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'business-tables-after.tsv') -Encoding utf8
$inventoryTotals | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'inventory-after-api-probe.txt') -Encoding utf8
$demoInventoryEvidence | Set-Content -LiteralPath (Join-Path $evidenceDirectory 'fresh-demo-inventory-and-transactions.tsv') -Encoding utf8
if ($script:FirstFailure) {
    Write-Output "First business-chain failure at $($script:FirstFailure.step): HTTP $($script:FirstFailure.http), code $($script:FirstFailure.code). Evidence: $evidenceDirectory"
    exit 2
}
Write-Output "Inbound receipt API probe completed for marker $orderMarker. Evidence: $evidenceDirectory"

