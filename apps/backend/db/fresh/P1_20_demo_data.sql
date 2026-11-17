-- FreshLink P1 demo master data (idempotent; migration-owned rows, rerun is a no-op for values).
SET NAMES utf8mb4;

INSERT INTO `wms_cargo_owners` (`id`,`owner_code`,`owner_name`,`status`,`tenant_id`,`create_by`,`create_time`)
VALUES ('fresh_p1_owner','FRESH','生鲜配送中心','ACTIVE',0,'fresh_p1',NOW())
ON DUPLICATE KEY UPDATE `id`=`id`;

INSERT INTO `wms_warehouses` (`id`,`warehouse_code`,`warehouse_name`,`warehouse_attr`,`status`,`tenant_id`,`create_by`,`create_time`)
VALUES ('fresh_p1_wh_w1','W1','生鲜配送中心','RAW_MATERIAL','ACTIVE',0,'fresh_p1',NOW())
ON DUPLICATE KEY UPDATE `warehouse_code`=VALUES(`warehouse_code`),`warehouse_name`=VALUES(`warehouse_name`),
`warehouse_attr`=VALUES(`warehouse_attr`),`status`=VALUES(`status`);

INSERT INTO `wms_storage_zones` (`id`,`zone_code`,`zone_name`,`zone_type`,`storage_type`,`status`,`is_sellable`,`warehouse_id`,`tenant_id`,`create_by`,`create_time`)
VALUES
('fresh_p1_zone_norm','NORM','常温区','STORAGE_AREA','NORMAL','ACTIVE','1','fresh_p1_wh_w1',0,'fresh_p1',NOW()),
('fresh_p1_zone_cold','COLD','冷藏区','STORAGE_AREA','CHILLED','ACTIVE','1','fresh_p1_wh_w1',0,'fresh_p1',NOW()),
('fresh_p1_zone_frozen','FROZEN','冷冻区','STORAGE_AREA','FROZEN','ACTIVE','1','fresh_p1_wh_w1',0,'fresh_p1',NOW()),
('fresh_p1_zone_recv','RECV','收货暂存区','TEMPORARY_AREA','NORMAL','ACTIVE','0','fresh_p1_wh_w1',0,'fresh_p1',NOW()),
('fresh_p1_zone_quar','QUAR','隔离区','TEMPORARY_AREA','NORMAL','ACTIVE','0','fresh_p1_wh_w1',0,'fresh_p1',NOW())
ON DUPLICATE KEY UPDATE `zone_code`=VALUES(`zone_code`),`zone_name`=VALUES(`zone_name`),`zone_type`=VALUES(`zone_type`),
`storage_type`=VALUES(`storage_type`),`status`=VALUES(`status`),`is_sellable`=VALUES(`is_sellable`),`warehouse_id`=VALUES(`warehouse_id`);

INSERT INTO `wms_storage_locations` (`id`,`location_code`,`location_category`,`location_type`,`status`,`zone_id`,`warehouse_id`,`is_sellable`,`tenant_id`,`create_by`,`create_time`)
VALUES
('fresh_p1_loc_r1','R1','生鲜收货','RECEIVING_LOC','ACTIVE','fresh_p1_zone_recv','fresh_p1_wh_w1','0',0,'fresh_p1',NOW()),
('fresh_p1_loc_c1','C1','生鲜冷藏','STORAGE_LOC','ACTIVE','fresh_p1_zone_cold','fresh_p1_wh_w1','1',0,'fresh_p1',NOW()),
('fresh_p1_loc_c2','C2','生鲜冷藏','STORAGE_LOC','ACTIVE','fresh_p1_zone_cold','fresh_p1_wh_w1','1',0,'fresh_p1',NOW()),
('fresh_p1_loc_n1','N1','生鲜常温','STORAGE_LOC','ACTIVE','fresh_p1_zone_norm','fresh_p1_wh_w1','1',0,'fresh_p1',NOW()),
('fresh_p1_loc_p1','P1','生鲜拣货暂存','PICKING_LOC','ACTIVE','fresh_p1_zone_cold','fresh_p1_wh_w1','0',0,'fresh_p1',NOW()),
('fresh_p1_loc_q1','Q1','生鲜隔离','EXCEPTION_LOC','ACTIVE','fresh_p1_zone_quar','fresh_p1_wh_w1','0',0,'fresh_p1',NOW())
ON DUPLICATE KEY UPDATE `location_code`=VALUES(`location_code`),`location_category`=VALUES(`location_category`),
`location_type`=VALUES(`location_type`),`status`=VALUES(`status`),`zone_id`=VALUES(`zone_id`),
`warehouse_id`=VALUES(`warehouse_id`),`is_sellable`=VALUES(`is_sellable`);

INSERT INTO `fresh_supplier` (`id`,`supplier_code`,`supplier_name`,`contact_name`,`contact_phone`,`status`,`remark`,`create_by`,`create_time`)
VALUES
('fresh_p1_sup_s1','S1','生鲜供应商一','张一','13800000001','ACTIVE','P1 演示供应商 S1','fresh_p1',NOW()),
('fresh_p1_sup_s2','S2','生鲜供应商二','李二','13800000002','ACTIVE','P1 演示供应商 S2','fresh_p1',NOW())
ON DUPLICATE KEY UPDATE `id`=`id`;

INSERT INTO `fresh_store` (`id`,`store_code`,`store_name`,`address`,`contact_name`,`contact_phone`,`status`,`remark`,`create_by`,`create_time`)
VALUES
('fresh_p1_store_a','A','门店A','上海市杨浦区A路1号','店长A','13900000001','ACTIVE','P1 演示门店 A','fresh_p1',NOW()),
('fresh_p1_store_b','B','门店B','上海市浦东新区B路2号','店长B','13900000002','ACTIVE','P1 演示门店 B','fresh_p1',NOW())
ON DUPLICATE KEY UPDATE `id`=`id`;

INSERT INTO `wms_products`
(`id`,`product_name`,`owner_id`,`product_code`,`product_barcode`,`category_id`,`product_spec`,`packaging_spec`,`shelf_life`,
 `maintenance_cycle`,`unit`,`is_expiry_controlled`,`status`,`storage_type`,`near_expiry_days`,`tenant_id`,`create_by`,`create_time`)
VALUES
('fresh_p1_product_x','鸡胸肉 1kg/袋','fresh_p1_owner','FRESH-X','FRESH-BC-X','0','1kg/袋','1kg/袋',7,0,'袋',1,'ACTIVE','CHILLED',3,0,'fresh_p1',NOW()),
('fresh_p1_product_y','土豆 5kg/袋','fresh_p1_owner','FRESH-Y','FRESH-BC-Y','0','5kg/袋','5kg/袋',30,0,'袋',1,'ACTIVE','NORMAL',5,0,'fresh_p1',NOW())
ON DUPLICATE KEY UPDATE `id`=`id`;

INSERT INTO `fresh_schema_migration` (`version`,`description`,`checksum`,`applied_at`)
VALUES ('P1.20','fresh demo master data W1/S1/S2/A/B/X/Y','P1_20_demo_data.sql',NOW())
ON DUPLICATE KEY UPDATE `description`=VALUES(`description`);
