-- Isolated D2/D3 probe setup only. The probe performs all positive stock movements via HTTP.
-- Apply once to an empty test schema named freshlink_d2_* or freshlink_d3_* after D2_00_inbound_lots.sql.
SET @d2_is_isolated = DATABASE() REGEXP '^freshlink_d[23]_[A-Za-z0-9_]+$';
SET @business_day = DATE(DATE_ADD(UTC_TIMESTAMP(), INTERVAL 8 HOUR));

START TRANSACTION;
INSERT INTO wms_stock_in_orders (id, order_number, order_type, owner_id, status, warehouse_id, supplier_id, total_expected_quantity, total_received_quantity, total_shelved_quantity, total_defective_quantity)
SELECT 'd2_expiry_test_order', 'D2-DB-EXPIRED-ORDER', 'PURCHASE_IN', 'fresh_p1_owner', 'PUTAWAYED', 'fresh_p1_wh_w1', 'fresh_p1_sup_s1', 2, 2, 2, 0
WHERE @d2_is_isolated;
INSERT INTO wms_stock_in_order_items (id, order_id, product_id, batch_number, production_date, expiry_date, expected_quantity, received_quantity, shelved_quantity, defective_quantity, status)
SELECT 'd2_expiry_test_item', 'd2_expiry_test_order', 'fresh_p1_product_x', 'D2-DB-EXPIRED-BOUNDARY', DATE_SUB(@business_day, INTERVAL 5 DAY), @business_day, 2, 2, 2, 0, 'PUTAWAYED'
WHERE @d2_is_isolated;
INSERT INTO wms_inventory (id, product_id, location_code, stock_quantity, allocated_quantity, available_quantity, batch_number, stock_in_time, expiry_date, owner_id, is_sellable, warehouse_id)
SELECT 'd2_expiry_test_stock', 'fresh_p1_product_x', 'C1', 2, 0, 2, 'FL:d2_expiry_test_item', DATE_SUB(@business_day, INTERVAL 3 DAY), @business_day, 'fresh_p1_owner', '1', 'fresh_p1_wh_w1'
WHERE @d2_is_isolated;
INSERT INTO wms_inventory (id, product_id, location_code, stock_quantity, allocated_quantity, available_quantity, batch_number, stock_in_time, expiry_date, owner_id, is_sellable, warehouse_id)
SELECT 'd2_legacy_test_stock', 'fresh_p1_product_x', 'C1', 3, 1, 2, 'D2-DB-HISTORY-NO-SOURCE', DATE_SUB(@business_day, INTERVAL 3 DAY), DATE_ADD(@business_day, INTERVAL 7 DAY), 'fresh_p1_owner', '1', 'fresh_p1_wh_w1'
WHERE @d2_is_isolated;
COMMIT;
