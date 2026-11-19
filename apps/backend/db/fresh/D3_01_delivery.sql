-- D3 delivery record. Outbound rows and items are created by the same transaction.
SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS `fresh_delivery` (
  `id` varchar(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '主键',
  `outbound_id` varchar(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '出库单ID',
  `outbound_number` varchar(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '出库单号快照',
  `store_id` varchar(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '门店ID快照',
  `store_name` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '门店名称快照',
  `store_address` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL COMMENT '配送地址快照',
  `status` varchar(16) NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING/IN_TRANSIT/DELIVERED',
  `driver_name` varchar(64) DEFAULT NULL COMMENT '配送员',
  `driver_phone` varchar(32) DEFAULT NULL COMMENT '配送员联系方式',
  `remark` varchar(255) DEFAULT NULL COMMENT '配送备注',
  `created_by` varchar(100) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `dispatch_by` varchar(100) DEFAULT NULL,
  `dispatch_at` datetime DEFAULT NULL,
  `delivered_by` varchar(100) DEFAULT NULL,
  `delivered_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_fresh_delivery_outbound` (`outbound_id`),
  KEY `ix_fresh_delivery_store_created` (`store_id`, `created_at`),
  KEY `ix_fresh_delivery_status_created` (`status`, `created_at`),
  CONSTRAINT `chk_fresh_delivery_status` CHECK (`status` IN ('PENDING', 'IN_TRANSIT', 'DELIVERED')),
  CONSTRAINT `fk_fresh_delivery_outbound` FOREIGN KEY (`outbound_id`) REFERENCES `fresh_outbound` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='生鲜配送单';

INSERT INTO `fresh_schema_migration` (`version`, `description`, `checksum`, `applied_at`)
VALUES ('D3.01', 'delivery snapshot and lifecycle', 'D3_01_delivery.sql', NOW())
ON DUPLICATE KEY UPDATE `description` = VALUES(`description`);
