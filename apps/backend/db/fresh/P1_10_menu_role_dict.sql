-- FreshLink P1 menus, roles, dictionaries and grants (idempotent).
SET NAMES utf8mb4;

-- ----------------------------- menus -----------------------------
INSERT INTO `sys_permission`
(`id`,`parent_id`,`name`,`url`,`component`,`is_route`,`component_name`,`redirect`,`menu_type`,`perms`,`perms_type`,`sort_no`,`always_show`,`icon`,`is_leaf`,`keep_alive`,`hidden`,`hide_tab`,`description`,`create_by`,`create_time`,`update_by`,`update_time`,`del_flag`,`rule_flag`,`status`,`internal_or_external`)
VALUES
('fresh_p1_menu_root','','生鲜基础资料','/fresh','layouts/default/index',1,NULL,NULL,0,NULL,'1',2.00,0,'ant-design:shop-outlined',0,0,0,0,'生鲜基础资料菜单','fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_menu_product','fresh_p1_menu_root','食材资料','/fresh/products','goods/WmsProductsList',1,NULL,NULL,1,NULL,'1',1.00,0,'ant-design:coffee-outlined',1,0,0,0,'复用商品资料页面并扩展温区/临期阈值','fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_menu_supplier','fresh_p1_menu_root','供应商','/fresh/suppliers','fresh/suppliers/FreshSupplierList',1,NULL,NULL,1,NULL,'1',2.00,0,'ant-design:team-outlined',1,0,0,0,'生鲜供应商维护','fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_menu_store','fresh_p1_menu_root','门店','/fresh/stores','fresh/stores/FreshStoreList',1,NULL,NULL,1,NULL,'1',3.00,0,'ant-design:home-outlined',1,0,0,0,'门店维护','fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_menu_userstore','fresh_p1_menu_root','用户门店绑定','/fresh/user-stores','fresh/userstores/FreshUserStoreList',1,NULL,NULL,1,NULL,'1',4.00,0,'ant-design:link-outlined',1,0,0,0,'总部维护用户与门店绑定','fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_menu_zone','fresh_p1_menu_root','温区与库位','/fresh/zones','warehouse/WmsStorageZonesList',1,NULL,NULL,1,NULL,'1',5.00,0,'ant-design:appstore-outlined',1,0,0,0,'复用库区资料页面并扩展温区标签','fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_menu_mystore','','我的门店','/fresh/my-store','fresh/stores/FreshStoreList',1,NULL,NULL,1,NULL,'1',3.00,0,'ant-design:shop-outlined',1,0,0,0,'门店账号查看本店资料','fresh_p1',NOW(),NULL,NULL,0,0,'1',0)
ON DUPLICATE KEY UPDATE
`parent_id`=VALUES(`parent_id`),`name`=VALUES(`name`),`url`=VALUES(`url`),`component`=VALUES(`component`),
`is_route`=VALUES(`is_route`),`menu_type`=VALUES(`menu_type`),`perms`=VALUES(`perms`),`sort_no`=VALUES(`sort_no`),
`icon`=VALUES(`icon`),`is_leaf`=VALUES(`is_leaf`),`hidden`=VALUES(`hidden`),`del_flag`=0,`status`='1';

-- ----------------------------- button permissions -----------------------------
INSERT INTO `sys_permission`
(`id`,`parent_id`,`name`,`url`,`component`,`is_route`,`component_name`,`redirect`,`menu_type`,`perms`,`perms_type`,`sort_no`,`always_show`,`icon`,`is_leaf`,`keep_alive`,`hidden`,`hide_tab`,`description`,`create_by`,`create_time`,`update_by`,`update_time`,`del_flag`,`rule_flag`,`status`,`internal_or_external`)
VALUES
('fresh_p1_btn_supplier_add','fresh_p1_menu_supplier','新增供应商','','',0,NULL,NULL,2,'fresh:supplier:add','1',1.00,0,NULL,1,0,0,0,NULL,'fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_btn_supplier_edit','fresh_p1_menu_supplier','编辑供应商','','',0,NULL,NULL,2,'fresh:supplier:edit','1',2.00,0,NULL,1,0,0,0,NULL,'fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_btn_supplier_del','fresh_p1_menu_supplier','删除供应商','','',0,NULL,NULL,2,'fresh:supplier:delete','1',3.00,0,NULL,1,0,0,0,NULL,'fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_btn_supplier_bdel','fresh_p1_menu_supplier','批量删除供应商','','',0,NULL,NULL,2,'fresh:supplier:deleteBatch','1',4.00,0,NULL,1,0,0,0,NULL,'fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_btn_supplier_exp','fresh_p1_menu_supplier','导出供应商','','',0,NULL,NULL,2,'fresh:supplier:exportXls','1',5.00,0,NULL,1,0,0,0,NULL,'fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_btn_store_add','fresh_p1_menu_store','新增门店','','',0,NULL,NULL,2,'fresh:store:add','1',1.00,0,NULL,1,0,0,0,NULL,'fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_btn_store_edit','fresh_p1_menu_store','编辑门店','','',0,NULL,NULL,2,'fresh:store:edit','1',2.00,0,NULL,1,0,0,0,NULL,'fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_btn_store_del','fresh_p1_menu_store','删除门店','','',0,NULL,NULL,2,'fresh:store:delete','1',3.00,0,NULL,1,0,0,0,NULL,'fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_btn_store_bdel','fresh_p1_menu_store','批量删除门店','','',0,NULL,NULL,2,'fresh:store:deleteBatch','1',4.00,0,NULL,1,0,0,0,NULL,'fresh_p1',NOW(),NULL,NULL,0,0,'1',0),
('fresh_p1_btn_userstore_edit','fresh_p1_menu_userstore','维护用户门店绑定','','',0,NULL,NULL,2,'fresh:userstore:edit','1',1.00,0,NULL,1,0,0,0,NULL,'fresh_p1',NOW(),NULL,NULL,0,0,'1',0)
ON DUPLICATE KEY UPDATE
`parent_id`=VALUES(`parent_id`),`name`=VALUES(`name`),`menu_type`=VALUES(`menu_type`),`perms`=VALUES(`perms`),
`sort_no`=VALUES(`sort_no`),`del_flag`=0,`status`='1';

-- ----------------------------- roles -----------------------------
INSERT INTO `sys_role` (`id`,`role_name`,`role_code`,`description`,`create_by`,`create_time`,`update_by`,`update_time`,`tenant_id`)
VALUES
('fresh_p1_role_hq','生鲜总部管理员','fresh_hq','总部：基础资料、用户门店绑定、仓储业务与全部查询','fresh_p1',NOW(),NULL,NULL,0),
('fresh_p1_role_warehouse','生鲜仓管/配送调度','fresh_warehouse','仓管：基础资料维护、仓储作业；无系统用户管理权限','fresh_p1',NOW(),NULL,NULL,0),
('fresh_p1_role_store','生鲜门店用户','fresh_store','门店：仅本店资料与后续本店申领/配送；不可自改绑定','fresh_p1',NOW(),NULL,NULL,0)
ON DUPLICATE KEY UPDATE `role_name`=VALUES(`role_name`),`description`=VALUES(`description`);

-- ----------------------------- dictionaries -----------------------------
INSERT INTO `sys_dict` (`id`,`dict_name`,`dict_code`,`description`,`del_flag`,`create_by`,`create_time`,`type`,`tenant_id`)
VALUES
('fresh_p1_dict_storage','生鲜温区','fresh_storage_type','常温/冷藏/冷冻','0','fresh_p1',NOW(),0,0),
('fresh_p1_dict_status','生鲜启用状态','fresh_enabled_status','启用/禁用','0','fresh_p1',NOW(),0,0)
ON DUPLICATE KEY UPDATE `dict_name`=VALUES(`dict_name`),`description`=VALUES(`description`),`del_flag`=0;

INSERT INTO `sys_dict_item` (`id`,`dict_id`,`item_text`,`item_value`,`item_color`,`description`,`sort_order`,`status`,`create_by`,`create_time`,`update_by`,`update_time`)
VALUES
('fresh_p1_di_storage_norm','fresh_p1_dict_storage','常温','NORMAL',NULL,NULL,1,1,'fresh_p1',NOW(),NULL,NULL),
('fresh_p1_di_storage_chill','fresh_p1_dict_storage','冷藏','CHILLED',NULL,NULL,2,1,'fresh_p1',NOW(),NULL,NULL),
('fresh_p1_di_storage_frozen','fresh_p1_dict_storage','冷冻','FROZEN',NULL,NULL,3,1,'fresh_p1',NOW(),NULL,NULL),
('fresh_p1_di_status_active','fresh_p1_dict_status','启用','ACTIVE',NULL,NULL,1,1,'fresh_p1',NOW(),NULL,NULL),
('fresh_p1_di_status_inactive','fresh_p1_dict_status','禁用','INACTIVE',NULL,NULL,2,1,'fresh_p1',NOW(),NULL,NULL)
ON DUPLICATE KEY UPDATE `item_text`=VALUES(`item_text`),`item_value`=VALUES(`item_value`),`sort_order`=VALUES(`sort_order`),`status`=1;

-- ----------------------------- grants -----------------------------
-- HQ: every current menu/button permission (the role is purpose-built, not the framework admin bypass).
INSERT IGNORE INTO `sys_role_permission` (`id`,`role_id`,`permission_id`,`operate_date`)
SELECT CONCAT('frp', SUBSTRING(MD5(CONCAT('fresh_p1_role_hq','|',p.`id`)),1,29)), 'fresh_p1_role_hq', p.`id`, NOW()
FROM `sys_permission` p WHERE p.`del_flag` = 0;

-- Warehouse: fresh master data + legacy warehouse/order menus and buttons, without system administration.
INSERT IGNORE INTO `sys_role_permission` (`id`,`role_id`,`permission_id`,`operate_date`)
SELECT CONCAT('frp', SUBSTRING(MD5(CONCAT('fresh_p1_role_warehouse','|',p.`id`)),1,29)), 'fresh_p1_role_warehouse', p.`id`, NOW()
FROM `sys_permission` p
WHERE p.`del_flag` = 0 AND (
  p.`id` IN ('fresh_p1_menu_root','fresh_p1_menu_product','fresh_p1_menu_supplier','fresh_p1_menu_store','fresh_p1_menu_zone',
             'fresh_p1_btn_supplier_add','fresh_p1_btn_supplier_edit','fresh_p1_btn_supplier_del',
             'fresh_p1_btn_supplier_bdel','fresh_p1_btn_supplier_exp','1438108176273760258')
  OR p.`url` LIKE '/warehouse%' OR p.`url` LIKE '/inorder%' OR p.`url` LIKE '/outorder%'
  OR p.`url` LIKE '/inventory%' OR p.`url` LIKE '/wave%' OR p.`url` LIKE '/shipment%'
  OR p.`perms` LIKE 'goods:wms_products:%'
  OR p.`perms` LIKE 'warehouse:%' OR p.`perms` LIKE 'inorder:%' OR p.`perms` LIKE 'outorder:%'
  OR p.`perms` LIKE 'inventory:%' OR p.`perms` LIKE 'wave:%' OR p.`perms` LIKE 'shipment:%'
);

-- Store: own store page only. No legacy WMS, no supplier/user-binding, no product maintenance.
INSERT IGNORE INTO `sys_role_permission` (`id`,`role_id`,`permission_id`,`operate_date`)
SELECT CONCAT('frp', SUBSTRING(MD5(CONCAT('fresh_p1_role_store','|',p.`id`)),1,29)), 'fresh_p1_role_store', p.`id`, NOW()
FROM `sys_permission` p
WHERE p.`del_flag` = 0 AND p.`id` IN ('fresh_p1_menu_mystore','1438108176273760258');

INSERT INTO `fresh_schema_migration` (`version`,`description`,`checksum`,`applied_at`)
VALUES ('P1.10','fresh menus, roles, dicts and role grants','P1_10_menu_role_dict.sql',NOW())
ON DUPLICATE KEY UPDATE `description`=VALUES(`description`);
