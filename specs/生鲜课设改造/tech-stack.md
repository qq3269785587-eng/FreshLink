# 技术复用与实施边界

v2.1，2026-11-18。继续采用已验收 P1 的 JeecgBoot/Spring Boot Java17、Vue/Vite/Ant Design Vue、MySQL和Redis，保留锁文件，不升级依赖，不换框架。原机 apps/backend 与 apps/web 各保留Git；团队副本是单仓，以其README和scripts/team为准。

## 已知基线

P0确认收货上架局部可用；allocateStock 返回失败占位，createWave 有TODO。P1基础资料和权限通过；前端全量类型诊断存在2691条存量，后续要求无新增，不声称全量类型通过。原库历史库存差异不平账，不作为新演示库存。

后端业务根 B=apps/backend/jeecg-module-wms/src/main/java/org/jeecg/modules/wms，前端 F=apps/web/src/views。

| 能力 | 复用入口 | v2.1工作 |
|---|---|---|
| 基础资料 | B/goods、B/fresh、B/warehouse；F/goods、F/fresh、F/warehouse | 沿用P1，补新批次引用保护 |
| 入库任务 | B/inorder、B/wmstask/service/impl/WmsTasksServiceImpl.java；F/inorder | 接入批次来源日期，收货上架数量守恒 |
| 库存与流水 | B/inventory/entity/WmsInventory.java、WmsInventoryTrans.java | 延续原余额及批次流水，补查询与效期筛选 |
| 库存服务 | B/inventory/service/impl/WmsInventoryTransByReceiving.java、WmsInventoryTransByPutway.java 等 | 复用事务服务，不另造余额；确认出库支持按批原子扣减 |
| 出库单 | B/outorder/service/impl/WmsOutOrdersServiceImpl.java；F/outorder | 复用单据页面和结构，新增/调整人工选批确认动作；不依赖旧分配和波次 |
| 配送 | B/shipment、B/waybill 及可用界面 | 先判断复用成本；允许独立轻量内部配送表关联原出库，不接快递服务 |
| 菜单 | 前端src/api/sys/menu.ts与权限store，后端数据库菜单授权 | 新页要有SQL菜单权限，不只加路由 |

旧拣货和发货服务有空批次查询/流水丢批次风险。若简化流程复用相关函数，必须修复实际使用路径；未使用的复杂链不为本次补齐。新旧出库入口不得双扣库存。

## 最小数据和接口合同

批次事实保存supplierId、productId、批号、生产到期日期和入库引用；唯一键区分货主/供应商/食材/批号，映射以实际DDL核实，不能凭名字合批。库存定位保留原仓库、货主、食材、批次、库位和必要容器维度。

出库明细保存实际库存批次引用和数量。配送与出库唯一关联，含门店地址快照、状态、配送员、联系方式、操作人和时间；明细关联已锁定出库事实，避免重复维护两份可修改数量。

先写一份简短接口合同，约定查询批次、入库收货上架、保存出库草稿、确认出库、配送列表详情、登记配送员、开始配送和确认送达。路径沿用原风格，不强制全量重命名。动作接口与普通编辑分离，服务端只接收允许字段。

确认出库同事务完成扣在库及未分配、流水、出库状态和配送单；条件更新/行锁及唯一约束防重复和负数。已有分配占用保持不变。旧通用编辑/导入/发货对演示角色关闭或接入等价校验。权限在后端执行，旧门店隔离不退化。

## 迁移与验证

增量SQL放 apps/backend/db/fresh/，用D2/D3新命名，保留P1迁移不改写。新增表索引和必要唯一性；菜单权限随SQL交付。首次执行和重跑均验证，历史数据标待核验而非伪造来源。测试在隔离库，版本与运行实例匹配。

原机 scripts/Test-Fresh.ps1、Build-Backend.ps1、Build-Frontend.ps1 可沿用；团队使用 scripts/team/ 对应入口。默认Maven构建可能跳过测试，须记录实际执行数。小改只跑影响面，D4最终构建和本机重启彩排；不要求全新机器安装或复杂并发组合矩阵。
