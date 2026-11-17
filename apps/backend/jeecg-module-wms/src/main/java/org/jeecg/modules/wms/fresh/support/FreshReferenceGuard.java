package org.jeecg.modules.wms.fresh.support;

import org.jeecg.common.exception.JeecgBootException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import jakarta.annotation.Resource;
import java.util.List;

/**
 * Reference protection for master data deletion. Rules are evaluated against the live schema so
 * later phases (batch/requisition tables) automatically become protected once those tables exist.
 */
@Component
public class FreshReferenceGuard {

    @Resource
    private JdbcTemplate jdbcTemplate;

    public void assertSupplierDeletable(String supplierId) {
        long references = countIfTable("fresh_batch", "supplier_id", supplierId);
        if (references > 0) {
            throw new JeecgBootException("供应商已被批次引用，不能删除；请改为禁用");
        }
    }

    public void assertStoreDeletable(String storeId) {
        long references = countIfTable("fresh_user_store", "store_id", storeId)
                + countIfTable("fresh_requisition", "store_id", storeId)
                + countIfTable("fresh_delivery", "store_id", storeId);
        if (references > 0) {
            throw new JeecgBootException("门店已被用户或业务单据引用，不能删除；请改为禁用");
        }
    }

    public void assertProductDeletable(String productId) {
        long references = countIfTable("wms_inventory", "product_id", productId)
                + countIfTable("wms_stock_in_order_items", "product_id", productId)
                + countIfTable("wms_out_orders_items", "product_id", productId)
                + countIfTable("wms_out_orders_allocation", "product_id", productId)
                + countIfTable("wms_tasks_records", "product_id", productId);
        if (references > 0) {
            throw new JeecgBootException("食材已被库存或业务单据引用，不能删除；请改为禁用");
        }
    }

    public void assertSupplierCodeUnique(String code, String excludeId) {
        long count = countByCode("fresh_supplier", "supplier_code", code, excludeId);
        if (count > 0) {
            throw new JeecgBootException("供应商编码已存在");
        }
    }

    public void assertStoreCodeUnique(String code, String excludeId) {
        long count = countByCode("fresh_store", "store_code", code, excludeId);
        if (count > 0) {
            throw new JeecgBootException("门店编码已存在");
        }
    }

    private long countByCode(String table, String column, String code, String excludeId) {
        if (!tableExists(table)) {
            return 0;
        }
        String sql = "SELECT COUNT(*) FROM `" + table + "` WHERE `" + column + "` = ?";
        if (excludeId != null && !excludeId.isEmpty()) {
            sql += " AND `id` <> ?";
            return number(jdbcTemplate.queryForObject(sql, Long.class, code, excludeId));
        }
        return number(jdbcTemplate.queryForObject(sql, Long.class, code));
    }

    private long countIfTable(String table, String column, String value) {
        if (!tableExists(table) || !columnExists(table, column)) {
            return 0;
        }
        Long count = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM `" + table + "` WHERE `" + column + "` = ?", Long.class, value);
        return number(count);
    }

    private boolean tableExists(String table) {
        Integer count = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?",
                Integer.class, table);
        return count != null && count > 0;
    }

    private boolean columnExists(String table, String column) {
        Integer count = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?",
                Integer.class, table, column);
        return count != null && count > 0;
    }

    private long number(Long value) {
        return value == null ? 0L : value;
    }

    /** Used by the delete endpoints to report a deterministic, testable reason. */
    public List<String> describeReferences(String table, String column, String value) {
        if (!tableExists(table) || !columnExists(table, column)) {
            return List.of();
        }
        return jdbcTemplate.queryForList(
                "SELECT `id` FROM `" + table + "` WHERE `" + column + "` = ? LIMIT 5", String.class, value);
    }
}
