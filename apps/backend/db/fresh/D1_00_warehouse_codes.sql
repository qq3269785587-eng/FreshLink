-- D1 master-data keys. Existing duplicate codes cause a migration error.
-- Resolve any duplicate records and their references explicitly before rerunning.
SET NAMES utf8mb4;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_warehouses` ADD UNIQUE KEY `uk_d1_warehouse_code` (`warehouse_code`)',
  'SELECT 1') FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 'wms_warehouses' AND index_name = 'uk_d1_warehouse_code');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_storage_zones` ADD UNIQUE KEY `uk_d1_zone_code` (`zone_code`)',
  'SELECT 1') FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 'wms_storage_zones' AND index_name = 'uk_d1_zone_code');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE `wms_storage_locations` ADD UNIQUE KEY `uk_d1_location_code` (`location_code`)',
  'SELECT 1') FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 'wms_storage_locations' AND index_name = 'uk_d1_location_code');
PREPARE fresh_stmt FROM @ddl; EXECUTE fresh_stmt; DEALLOCATE PREPARE fresh_stmt;

INSERT INTO `fresh_schema_migration` (`version`, `description`, `checksum`, `applied_at`)
VALUES ('D1.00', 'warehouse, zone and location code uniqueness', 'D1_00_warehouse_codes.sql', NOW())
ON DUPLICATE KEY UPDATE `description` = VALUES(`description`);
