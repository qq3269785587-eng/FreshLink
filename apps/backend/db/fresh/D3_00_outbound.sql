SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS fresh_outbound (
    id VARCHAR(36) NOT NULL,
    order_number VARCHAR(40) NOT NULL,
    store_id VARCHAR(36) NOT NULL,
    store_name VARCHAR(128) NOT NULL,
    status VARCHAR(16) NOT NULL,
    created_by VARCHAR(100) NOT NULL,
    created_at DATETIME(3) NOT NULL,
    confirmed_by VARCHAR(100) NULL,
    confirmed_at DATETIME(3) NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_fresh_outbound_number (order_number),
    KEY ix_fresh_outbound_store (store_id),
    KEY ix_fresh_outbound_created (created_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fresh_outbound_item (
    id VARCHAR(36) NOT NULL,
    outbound_id VARCHAR(36) NOT NULL,
    inventory_id VARCHAR(36) NOT NULL,
    stock_batch_key VARCHAR(64) NOT NULL,
    product_id VARCHAR(36) NOT NULL,
    product_name VARCHAR(128) NOT NULL,
    product_spec VARCHAR(128) NULL,
    unit VARCHAR(64) NULL,
    supplier_id VARCHAR(36) NOT NULL,
    supplier_name VARCHAR(128) NOT NULL,
    batch_number VARCHAR(32) NOT NULL,
    location_code VARCHAR(50) NOT NULL,
    expiry_date DATE NOT NULL,
    quantity INT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_fresh_outbound_item_stock (outbound_id, inventory_id),
    KEY ix_fresh_outbound_item_batch (stock_batch_key),
    CONSTRAINT fk_fresh_outbound_item_order FOREIGN KEY (outbound_id) REFERENCES fresh_outbound (id),
    CONSTRAINT ck_fresh_outbound_item_quantity CHECK (quantity > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO fresh_schema_migration (version, description, checksum, applied_at)
VALUES ('D3.00', 'manual lot outbound orders and stock snapshots', 'D3_00_outbound.sql', NOW())
ON DUPLICATE KEY UPDATE description = VALUES(description);
