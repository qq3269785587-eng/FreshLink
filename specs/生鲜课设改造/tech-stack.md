# 技术实现与现有基线

## P0 本轮实施补充（2026-11-17）

当前有效证据为 `work/fresh-acceptance/P0/attempt-01/delivery.md` 与 manifest。下述初始源码判断需结合本轮结果阅读：真实入库、收货、上架可用，但订单allocateStock仍为失败占位、createWave仍为TODO。P3采用单单拣货任务路线并补齐真实整单FEFO，不依赖未完成的复杂波次。具体状态与数据映射见本次docs/state-map.md、data-contract.md。

P0已提供opt-in `p0-tests` profile与`scripts/Test-Fresh.ps1`，实际后端2/2、前端2/2；默认package仍跳过测试。前端生产构建与浏览器登录可用，全量vue-tsc尚有检查器/旧Vue语法阻塞，不能称为全量类型通过。pnpm元数据版本11.25.0已查官方registry确认存在，本轮保留依赖、未重装。

## 1. 活动目录与版本

项目根目录：`D:\Yuki\Codex\Project\FreshLink`。以下路径除说明外均相对此根目录。

| 项目 | 现状依据 | 决策与原因 |
|---|---|---|
| 后端 | `apps/backend/pom.xml`：JeecgBoot 3.8.1、Spring Boot 3.4.5、Java 17 | 保留 Java 单体模块与现有服务，避免三天内重写 |
| 前端 | `apps/web/package.json`：项目 3.8.0、Vue `^3.5.13`、Vite 6 系列、Ant Design Vue `^4.2.6` | 沿用现有 Vue 管理端，不新建 React/独立门店项目 |
| 数据库 | MySQL；启动脚本依赖本机 MySQL80 服务 | 延续现有表及增量迁移；P0 记录实际运行版本 |
| Redis | `runtime/redis/Start-Redis.ps1` 与 `scripts/Start-Project.ps1` 启动链 | 保留认证等既有依赖；不额外增加 MQ/调度集群 |
| 前端依赖 | `apps/web/pnpm-lock.yaml` 和已迁移的依赖 | 迁移清单确认 4,000 个 pnpm junction 均已指向新目录；本机 pnpm 命令为 10.34.9，而依赖元数据标记 11.25.0。保留现状；安装依赖前由 P0 明确可复现的 pnpm 版本，不在搬迁中升级 |
| 启动 | `Start-FreshLink.cmd → scripts/Start-Project.ps1`；`Start-WMS.cmd` 是兼容入口 | 前端 3100、后端 8080 `/jeecg-boot`；仅为当前本地默认，不假定端口服务就是新版本 |

迁移后唯一活动工程是 `apps/backend` 和 `apps/web`。原 `code/` 同名副本位于 `archive/original-code/`，仅供只读参考，禁止用它覆盖活动工程。迁移前后端 HEAD 分别为 `4c9b88fe5e2bb41d878551b7990b306e80aa50e2`、`82ecedc4c62c03b1de1e02164d24299610c1545d`；迁移前二者有未提交修改和未跟踪代码。**HEAD 不是完整可用基线**。本次迁移前的差异快照在 `work/migration-20261117/`。P0 必须保存已跟踪改动和未跟踪源码；不得 `reset --hard`、`clean` 或只按 HEAD 重建。

启动后端会把 `apps/backend` 的 target JAR 复制到 `runtime/run/jeecg-system-start.jar`，并把 `runtime/` 作为后端进程工作目录。现有 logback 使用 `../logs`，因此应用日志落在项目根目录 `logs/`。修改源码后必须重新构建并核对实际 JAR。端口校验会检查监听进程的命令路径；如果端口由 FreshLink 之外的进程占用，启动脚本会报错退出，不能把它当成当前项目。

迁移依赖修复记录在 `work/migration-20261117/dependency-relocation.json`：4,000 个前端 pnpm junction 的目标已更新并逐项核验。迁移后后端离线构建已有成功记录，但它只证明可打包，不代表 P0 基线或业务验收已通过。pnpm 命令 10.34.9 与现有模块元数据标记的 11.25.0 版本不一致；当前未做安装或升级，P0 需明确之后可复现的包管理器版本。

## 2. 已检查的复用入口

后端业务根记作 `B = apps/backend/jeecg-module-wms/src/main/java/org/jeecg/modules/wms`；前端页面根记作 `F = apps/web/src/views`。

| 能力 | 入口 | 已确认与待验证 |
|---|---|---|
| 食材资料 | `B/goods/entity/WmsProducts.java`；`F/goods/WmsProductsList.vue`、`WmsProducts.api.ts` | 有商品单位、保质期/效期字段；需要生鲜必填规则与温区 |
| 仓库/库位 | `B/warehouse/`；`F/warehouse/` | 有结构和接口，保留当前补全页面；增补温区约束 |
| 入库 | `B/inorder/`；`B/wmstask/service/impl/WmsTasksServiceImpl.java`；`F/inorder/` | 有单据、收货、上架入口，业务写入和重复提交需实测 |
| 库存 | `B/inventory/entity/WmsInventory.java`、`WmsInventoryTrans.java` | 整数数量、批号、效期、可售标记已存在 |
| 库存动作 | `B/inventory/service/impl/WmsInventoryTransByReceiving.java`、`ByPutway.java`、`ByAllocation.java`、`ByPick.java`、`ByDeliver.java`（后四者均带 `WmsInventoryTrans` 前缀） | 尽量改造统一库存动作服务，不在门店模块另造余额表 |
| 出库 | `B/outorder/service/impl/WmsOutOrdersServiceImpl.java`；`F/outorder/` | 保留已有按钮状态限制、仓库名称显示与空明细保护 |
| 拣货/发运 | `B/wave/`、`B/shipment/`、`B/waybill/`；`F/wave/`、`F/shipment/WmsShipment.api.ts` | 现有快递流程不等于门店配送；新增内部配送关联，避免依赖真实快递服务 |
| 菜单权限 | 前端 `src/api/sys/menu.ts`、`src/store/modules/permission.ts` | 菜单从 `/sys/permission/getUserPermissionByToken` 读取；必须交付数据库菜单与授权迁移，不能仅添加 Vue 路由 |
| AI | 后端 `jeecg-boot-module/jeecg-boot-module-airag/`；前端 `src/router/routes/staticRouter.ts` | 有框架入口，不代表已接真实库存。先评估最短只读接入路径 |
| IoT | 后端 `jeecg-module-iot/`；`F/iot/` | 存在源码，不纳入这次必过功能 |

静态发现：`WmsInventoryTransByPick.transfer` 用空批次查目标库存并将新目标库存批号设为 null；`WmsInventoryTransByDeliver.transfer` 用空批次定位并未写批次流水。这两条路径及其调用参数必须贯通修复，不能只给列表增加批号列。

归档历史 `archive/work-history/materials-merge-20261117/合并说明.md` 记录过前端补全及构建，`archive/work-history/运行问题检查-20261116.md` 记录过运行修复。二者不代表当前完整业务通过；P0 建立新的可重复基线，不重复恢复旧版页面。

## 3. 数据实现建议

以下是逻辑结构与建议命名，不代表表已经存在。P0/P1 检查实际 DDL 后确定映射，避免重复字段或无意义复制；确定后更新数据字典，字段名改变不应改变业务要求。

| 对象 | 最少字段/约束 | 实现方式 |
|---|---|---|
| 食材 | 原商品字段＋storageType、nearExpiryDays、固定计数单位/规格 | 扩展 `wms_products`，保留原 ownerId |
| 供应商 | id、唯一 code、name、contact、enabled | 优先核实是否已有适用供应商表，否则新增 `fresh_supplier` |
| 门店/绑定 | `fresh_store`、`fresh_user_store`；用户唯一绑定、门店唯一编码 | 复用系统用户和角色，不新造登录 |
| 批次 | `fresh_batch`：id、ownerId、supplierId、productId、batchNumber、productionDate、expiryDate、qualityStatus | 复合唯一约束；建立来源事实，不建立第二份余额 |
| 入库/库存关联 | supplierId、batchId；批次/库位唯一性；库存流水业务引用 | 在原表扩展或用确定一对一关联表，不留纯文本关联 |
| 申领主/明细 | `fresh_requisition` / `_item`：storeId、状态、期望送达日、productId、数量、审批信息 | `outOrderId` 唯一；数字与状态服务端校验 |
| 配送主/批次明细 | `fresh_delivery` / `_item`：outOrderId 唯一、storeId、地址快照、派单信息、状态；出库明细/分配明细 ID、batchId、发出量 | 优先在原 shipment 能满足时扩展，不能同时维护两个相互冲突的配送状态 |
| 签收/异常 | 每配送单唯一签收；逐批 A/R/M、原因、签收人时间；异常状态、处理记录 | 可与配送明细合表以降工作量，但签收原事实不可覆盖 |
| 动作去重/审计 | 业务动作 ID、请求幂等键、业务对象、操作者、前后状态、时间 | 复用现有框架日志；涉及库存的去重记录需与业务同事务持久化 |

所有新增表需主键、创建/更新时间及必要索引；门店/状态/计划日期、批次到期日、外键逻辑引用列需按查询补索引。重要唯一性由数据库保障，不仅先查再插。运行账号授权过滤必须同时覆盖列表、详情、增改、导出、统计、批量接口和 AI。

跨门店请求中的 storeId 不可信，后端用登录身份的绑定值确定；总部角色按授权指定门店。错误统一返回明确业务原因，不用 500 堆栈代替校验，也不把框架 HTTP 200 当业务成功，应检查 JSON 业务码。

## 4. 库存与事务实现原则

1. 分配、取消、拣货、发车均检查当前状态并以条件更新/必要锁保证并发；扣减 SQL 同时校验剩余数，不先查完后无条件覆盖余额。
2. 申领审批与关联出库创建同事务；分配多明细同事务；库存、流水、任务/订单状态同事务。异常抛出需实际回滚，注意类内部调用绕过事务代理的问题。
3. 操作幂等按“动作＋业务明细/任务＋请求键”设计。相同请求重试返回既有结果；换请求键也不能绕过状态/累计数量上限再收一次或再发一次。
4. 并发创建同一批次库存由唯一约束兜底；发生冲突重试或合并必须保持流水与余额一致。锁定顺序稳定，避免多商品相反顺序导致频繁死锁。
5. 库位变更携带 batchId；同批元数据从批次事实读取，客户端不能传入另一个到期日覆盖。已分配明细与拣货明细不能只剩 SKU 总量。
6. 查询实时判断效期，定时任务可作提醒但不能作为阻止过期发货的唯一手段。冻结已占用批次后阻止拣货/发车，按 mission 的终止隔离流程处理。
7. 旧生成式库存增删改、导入或通用单据 edit 接口如果能绕过规则，应关闭业务角色授权或补齐同等校验；不能只保护新页面、新接口。

## 5. 接口与页面交付

可采用 `/fresh/stores`、`/fresh/suppliers`、`/fresh/requisitions`、`/fresh/deliveries`、`/fresh/trace`、`/fresh/dashboard`、`/fresh/assistant/query`，最终以接口清单为准，不强制改旧 API 风格。

提交、审核、分配、取消、拣货、发车、签收、关闭异常应是明确动作，普通 edit 不能修改 status、库存和审计字段。新增页面复用 BasicTable/Modal、字典和鉴权方式，避免大规模视觉重构。

菜单推荐：工作台、基础资料（食材/供应商/门店/库位）、入库管理、库存与效期、门店申领、出库作业、配送与签收、批次追溯、AI 助手。门店账号只见本店申领、配送、受限 AI；无关旧菜单可从课设角色授权中隐藏，不删除原模块源码。

## 6. 迁移、构建与凭据

- 新增迁移保存在后端 `db/fresh/`（或 P0 确认的既有迁移目录）；按阶段编号，包含 schema、菜单/字典/角色、演示数据和迁移说明。不要直接覆盖原初始化 SQL。
- 在备份后的独立测试数据库演练：原数据库快照 → 升级 → 测试 → 再次运行应安全无重复（可由迁移账本跳过）。另外证明基线数据库导入后可完整升级。破坏性回滚优先恢复备份，不能假装 DROP 新表能恢复新增期间的数据。
- 演示数据使用 `FRESH_DEMO_` 标识或明确的专用测试库；重置只处理该批数据，不清空用户原有单据。历史无效库存不得自动伪造成合格新食材。
- 构建入口：从项目根运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Backend.ps1 -Offline`；确有缺失缓存依赖时核对报错后去掉 `-Offline`，脚本使用 `runtime/config/maven-report-settings.xml` 与 `runtime/cache/maven-repository`。前端运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-Frontend.ps1`；脚本调用现有 `npm run build`。本机覆盖项见 `docs/本机环境与启动.md`，不要为方便下载到 C 盘。
- 当前后端 POM 将 Surefire 的 `skipTests` 写为 true；仅 BUILD SUCCESS 不能证明跑了测试。P0 建立明确的测试 profile/配置，使新业务测试实际执行，并保留 Surefire 测试数量与结果。不得只加一个命令行标志就未经确认宣称覆盖了硬编码配置。
- 当前前端有 build，但没有可直接依赖的 `test` / `typecheck` 脚本。P0 查明测试工具后补最小可执行校验入口，不在报告里写不存在的 `pnpm test` 已通过。完整类型检查若有存量错误，建立具体基线，新增代码不得增加错误；业务阻断错误不能豁免。
- 后端密钥只读本机配置或环境变量，不打印本地凭据文件内容。迁移脚本/测试数据/截图不得包含数据库密码、Token、AI Key。外部模型只发送必要的演示业务字段。
- 新依赖下载及验收截图、日志、快照放在项目 `work/`；Maven/npm/pnpm 依赖缓存放 `runtime/cache/`；本机凭据配置放 `runtime/config/` 且不得交付。源文件与规格不放在临时目录；交付构建产物放 `outputs/fresh/`，不把 node_modules/Maven 缓存加入源码备份。
