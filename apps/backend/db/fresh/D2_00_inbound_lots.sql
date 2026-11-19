-- Existing stock remains unchanged and is pending verification until a real source exists.
-- NULL request keys preserve all legacy task history.
SET NAMES utf8mb4;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_stock_in_orders` ADD COLUMN `supplier_id` VARCHAR(36) NULL',
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'wms_stock_in_orders' AND column_name = 'supplier_id');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

-- The WMS and FreshLink tables can inherit different MySQL utf8mb4 defaults.
SET @supplier_collation = (SELECT collation_name FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'fresh_supplier' AND column_name = 'id');
SET @ddl = (SELECT IF(collation_name = @supplier_collation,
  'SELECT 1',
  CONCAT('ALTER TABLE `wms_stock_in_orders` MODIFY COLUMN `supplier_id` VARCHAR(36) CHARACTER SET utf8mb4 COLLATE ',
    @supplier_collation, ' NULL'))
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'wms_stock_in_orders' AND column_name = 'supplier_id');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_stock_in_order_items` ADD COLUMN `batch_number` VARCHAR(32) NULL',
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'wms_stock_in_order_items' AND column_name = 'batch_number');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_stock_in_order_items` ADD COLUMN `production_date` DATE NULL',
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'wms_stock_in_order_items' AND column_name = 'production_date');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_stock_in_order_items` ADD COLUMN `expiry_date` DATE NULL',
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'wms_stock_in_order_items' AND column_name = 'expiry_date');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_tasks_records` ADD COLUMN `request_key` VARCHAR(64) NULL',
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'wms_tasks_records' AND column_name = 'request_key');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_inventory` MODIFY COLUMN `batch_number` VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT ''''',
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'wms_inventory' AND column_name = 'batch_number'
  AND character_maximum_length >= 64);
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_inventory_trans` MODIFY COLUMN `batch_number` VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL',
  'SELECT 1') FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'wms_inventory_trans' AND column_name = 'batch_number'
  AND character_maximum_length >= 64);
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_tasks_records` ADD UNIQUE KEY `uk_d2_task_request` (`task_id`, `request_key`)',
  'SELECT 1') FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 'wms_tasks_records' AND index_name = 'uk_d2_task_request');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_stock_in_orders` ADD KEY `ix_d2_supplier` (`supplier_id`)',
  'SELECT 1') FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 'wms_stock_in_orders' AND index_name = 'ix_d2_supplier');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_stock_in_orders` ADD CONSTRAINT `fk_d2_inbound_supplier` FOREIGN KEY (`supplier_id`) REFERENCES `fresh_supplier` (`id`)',
  'SELECT 1') FROM information_schema.referential_constraints
  WHERE constraint_schema = DATABASE() AND table_name = 'wms_stock_in_orders'
  AND constraint_name = 'fk_d2_inbound_supplier');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

-- One plan may contain multiple lots of the same product. Existing rows have NULL lot labels.
SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_stock_in_order_items` ADD UNIQUE KEY `uk_d2_order_product_batch` (`order_id`, `product_id`, `batch_number`)',
  'SELECT 1') FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 'wms_stock_in_order_items'
  AND index_name = 'uk_d2_order_product_batch');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) > 0,
  'ALTER TABLE `wms_stock_in_order_items` DROP INDEX `wms_stock_in_inorder_uindex`',
  'SELECT 1') FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 'wms_stock_in_order_items'
  AND index_name = 'wms_stock_in_inorder_uindex');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

INSERT INTO `fresh_schema_migration` (`version`, `description`, `checksum`, `applied_at`)
VALUES ('D2.00', 'inbound supplier and lot facts, stock keys and request idempotency', 'D2_00_inbound_lots.sql', NOW())
ON DUPLICATE KEY UPDATE `description` = VALUES(`description`);
