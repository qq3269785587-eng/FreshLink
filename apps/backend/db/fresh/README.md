# FreshLink 增量迁移（P1）

本目录只保存 FreshLink 生鲜改造的增量 SQL，不覆盖 `db/xingchenwms-*.sql` 原初始化脚本。

## 执行顺序

1. `P1_00_schema.sql`：新增 `fresh_supplier`、`fresh_store`、`fresh_user_store`、`fresh_schema_migration`，为 `wms_products` 增加 `storage_type`、`near_expiry_days`，为 `wms_storage_zones` 增加 `storage_type`，并增加 CHECK 约束。
2. `P1_10_menu_role_dict.sql`：菜单、按钮权限、`fresh_hq`/`fresh_warehouse`/`fresh_store` 角色、字典及授权。
3. `P1_20_demo_data.sql`：W1 仓、常温/冷藏/冷冻/收货/隔离库区，R1/C1/C2/N1/P1/Q1 库位，S1/S2 供应商，A/B 门店，X/Y 食材，演示货主。

## 幂等与保护

- 所有脚本可重复执行；建表使用 `CREATE TABLE IF NOT EXISTS`，列/约束/索引先查 `information_schema` 再执行动态 DDL，菜单/角色/字典使用固定 ID + `ON DUPLICATE KEY UPDATE`，授权使用 `INSERT IGNORE`。
- 演示主数据使用固定 ID，重复执行不会生成第二份；迁移账本 `fresh_schema_migration` 记录 `P1.00/P1.10/P1.20`。
- 不删除、不 `DROP` 任何原表；不修改原 WMS 历史单据。旧出库菜单与页面保持可读。
- 只允许在隔离测试库执行：`freshlink_p0_codex_20261117_b`，应用账号 `freshlink_p0_app_b`。不得在原业务库 `xingchenwms` 执行。

## 执行入口

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-FreshP1Migration.ps1 -EvidenceDirectory work\fresh-acceptance\P1\attempt-01\migration
```

脚本会连续执行两遍并比较计数，输出 `migration.md`、`migration-summary.json` 和各遍日志。

## 回退

P1 只做增量：回退以恢复迁移前数据库备份为主，不通过 `DROP` 新表假装恢复数据。若只回退 P1 新增对象，需先确认没有下游阶段数据引用；原 WMS 表和旧单据不受影响。

## 与后续阶段的关系

`fresh_batch`、`fresh_requisition`、`fresh_delivery` 属于 P2/P3/P4，本阶段未创建。引用保护代码已按表存在性检查，后续表建立后自动生效。产品温区与库区温区字段供 P2 上架匹配使用。
