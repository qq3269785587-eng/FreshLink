-- FreshLink P1 schema migration (idempotent; safe to run repeatedly).
-- Target: isolated MySQL test schema only. No destructive statement is used.
SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS `fresh_supplier` (
  `id` varchar(32) NOT NULL COMMENT '主键',
  `supplier_code` varchar(64) NOT NULL COMMENT '供应商唯一编码',
  `supplier_name` varchar(128) NOT NULL COMMENT '供应商名称',
  `contact_name` varchar(64) DEFAULT NULL COMMENT '联系人',
  `contact_phone` varchar(32) DEFAULT NULL COMMENT '联系方式',
  `status` varchar(16) NOT NULL DEFAULT 'ACTIVE' COMMENT 'ACTIVE/INACTIVE',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注',
  `create_by` varchar(50) DEFAULT NULL,
  `create_time` datetime DEFAULT NULL,
  `update_by` varchar(50) DEFAULT NULL,
  `update_time` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_fresh_supplier_code` (`supplier_code`),
  KEY `idx_fresh_supplier_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='生鲜供应商';

CREATE TABLE IF NOT EXISTS `fresh_store` (
  `id` varchar(32) NOT NULL COMMENT '主键',
  `store_code` varchar(64) NOT NULL COMMENT '门店唯一编码',
  `store_name` varchar(128) NOT NULL COMMENT '门店名称',
  `address` varchar(255) NOT NULL COMMENT '门店地址',
  `contact_name` varchar(64) DEFAULT NULL COMMENT '联系人',
  `contact_phone` varchar(32) DEFAULT NULL COMMENT '联系方式',
  `status` varchar(16) NOT NULL DEFAULT 'ACTIVE' COMMENT 'ACTIVE/INACTIVE',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注',
  `create_by` varchar(50) DEFAULT NULL,
  `create_time` datetime DEFAULT NULL,
  `update_by` varchar(50) DEFAULT NULL,
  `update_time` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_fresh_store_code` (`store_code`),
  KEY `idx_fresh_store_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='生鲜门店';

CREATE TABLE IF NOT EXISTS `fresh_user_store` (
  `id` varchar(32) NOT NULL COMMENT '主键',
  `user_id` varchar(32) NOT NULL COMMENT '系统用户ID，一期唯一绑定一个门店',
  `store_id` varchar(32) NOT NULL COMMENT '门店ID',
  `create_by` varchar(50) DEFAULT NULL,
  `create_time` datetime DEFAULT NULL,
  `update_by` varchar(50) DEFAULT NULL,
  `update_time` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_fresh_user_store_user` (`user_id`),
  KEY `idx_fresh_user_store_store` (`store_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='用户-门店绑定';

CREATE TABLE IF NOT EXISTS `fresh_schema_migration` (
  `version` varchar(64) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `checksum` varchar(64) DEFAULT NULL,
  `applied_at` datetime NOT NULL,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='生鲜迁移账本';

-- wms_products: temperature zone + near-expiry threshold (fresh master data).
SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_products` ADD COLUMN `storage_type` varchar(16) NULL COMMENT ''温区 NORMAL/CHILLED/FROZEN'' AFTER `status`',
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'wms_products' AND column_name = 'storage_type');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_products` ADD COLUMN `near_expiry_days` int NULL COMMENT ''临期阈值天数'' AFTER `storage_type`',
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'wms_products' AND column_name = 'near_expiry_days');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

-- wms_storage_zones: temperature zone tag used for put-away matching in P2.
SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_storage_zones` ADD COLUMN `storage_type` varchar(16) NULL COMMENT ''温区 NORMAL/CHILLED/FROZEN'' AFTER `zone_type`',
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'wms_storage_zones' AND column_name = 'storage_type');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_products` ADD CONSTRAINT `chk_fresh_near_expiry` CHECK (`near_expiry_days` IS NULL OR `near_expiry_days` >= 0)',
  'SELECT 1') FROM information_schema.table_constraints
  WHERE constraint_schema = DATABASE() AND table_name = 'wms_products' AND constraint_name = 'chk_fresh_near_expiry');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_products` ADD CONSTRAINT `chk_fresh_storage_type` CHECK (`storage_type` IS NULL OR `storage_type` IN (''NORMAL'',''CHILLED'',''FROZEN''))',
  'SELECT 1') FROM information_schema.table_constraints
  WHERE constraint_schema = DATABASE() AND table_name = 'wms_products' AND constraint_name = 'chk_fresh_storage_type');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_storage_zones` ADD CONSTRAINT `chk_fresh_zone_storage_type` CHECK (`storage_type` IS NULL OR `storage_type` IN (''NORMAL'',''CHILLED'',''FROZEN''))',
  'SELECT 1') FROM information_schema.table_constraints
  WHERE constraint_schema = DATABASE() AND table_name = 'wms_storage_zones' AND constraint_name = 'chk_fresh_zone_storage_type');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

INSERT INTO `fresh_schema_migration` (`version`, `description`, `checksum`, `applied_at`)
VALUES ('P1.00', 'fresh master data schema, store binding, product/zone temperature fields', 'P1_00_schema.sql', NOW())
ON DUPLICATE KEY UPDATE `description` = VALUES(`description`);
