package org.jeecg.modules.wms.fresh.delivery;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.fresh.access.FreshAccessService;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import jakarta.annotation.Resource;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;
import java.util.UUID;

@Service
public class FreshDeliveryService {
    private static final String PENDING = "PENDING";
    private static final String IN_TRANSIT = "IN_TRANSIT";
    private static final String DELIVERED = "DELIVERED";
    private static final String DELIVERY_SELECT = "SELECT id, outbound_id, outbound_number, store_id, store_name, "
            + "store_address, status, driver_name, driver_phone, remark, created_by, created_at, "
            + "dispatch_by, dispatch_at, delivered_by, delivered_at FROM fresh_delivery";

    private static final RowMapper<FreshDelivery> DELIVERY_ROW = (rs, rowNum) -> mapDelivery(rs);

    @Resource
    private JdbcTemplate jdbcTemplate;

    @Resource
    private FreshAccessService accessService;

    /** Called from outbound confirmation while its transaction is active. */
    @Transactional(propagation = Propagation.MANDATORY)
    public String createPending(String outboundId, String outboundNumber, String storeId,
                                String storeName, String address) {
        String existing = findIdByOutbound(outboundId);
        if (existing != null) {
            return existing;
        }
        String id = UUID.randomUUID().toString().replace("-", "");
        String actor = currentActor();
        try {
            jdbcTemplate.update("INSERT INTO fresh_delivery "
                            + "(id, outbound_id, outbound_number, store_id, store_name, store_address, status, created_by, created_at) "
                            + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())",
                    id, outboundId, outboundNumber, storeId, storeName, address, PENDING, actor);
            return id;
        } catch (DuplicateKeyException duplicate) {
            existing = findIdByOutbound(outboundId);
            if (existing != null) {
                return existing;
            }
            throw duplicate;
        }
    }

    public String findIdByOutbound(String outboundId) {
        List<String> ids = jdbcTemplate.query("SELECT id FROM fresh_delivery WHERE outbound_id = ?", (rs, rowNum) -> rs.getString(1), outboundId);
        return ids.isEmpty() ? null : ids.get(0);
    }

    public IPage<FreshDelivery> page(int pageNo, int pageSize, String storeScope) {
        long current = Math.max(1, pageNo);
        long size = Math.max(1, Math.min(pageSize, 100));
        String where = storeScope == null ? "" : " WHERE store_id = ?";
        Long total = storeScope == null
                ? jdbcTemplate.queryForObject("SELECT COUNT(*) FROM fresh_delivery", Long.class)
                : jdbcTemplate.queryForObject("SELECT COUNT(*) FROM fresh_delivery WHERE store_id = ?", Long.class, storeScope);
        String sql = DELIVERY_SELECT + where + " ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?";
        List<FreshDelivery> records = storeScope == null
                ? jdbcTemplate.query(sql, DELIVERY_ROW, size, (current - 1) * size)
                : jdbcTemplate.query(sql, DELIVERY_ROW, storeScope, size, (current - 1) * size);
        Page<FreshDelivery> page = new Page<>(current, size, total == null ? 0 : total);
        page.setRecords(records);
        return page;
    }

    public FreshDelivery detail(String id, String storeScope) {
        String scope = storeScope == null ? "" : " AND store_id = ?";
        List<FreshDelivery> deliveries = storeScope == null
                ? jdbcTemplate.query(DELIVERY_SELECT + " WHERE id = ?", DELIVERY_ROW, id)
                : jdbcTemplate.query(DELIVERY_SELECT + " WHERE id = ?" + scope, DELIVERY_ROW, id, storeScope);
        if (deliveries.isEmpty()) {
            throw new JeecgBootException("配送单不存在或无权查看");
        }
        FreshDelivery delivery = deliveries.get(0);
        delivery.setItems(jdbcTemplate.query("SELECT id, inventory_id, stock_batch_key, product_id, product_name, "
                        + "product_spec, unit, supplier_id, supplier_name, batch_number, location_code, expiry_date, quantity "
                        + "FROM fresh_outbound_item WHERE outbound_id = ? ORDER BY id ASC",
                (rs, rowNum) -> mapItem(rs), delivery.getOutboundId()));
        return delivery;
    }

    @Transactional(isolation = Isolation.READ_COMMITTED, rollbackFor = Exception.class)
    public FreshDelivery updateDispatchInfo(String id, FreshDeliveryDispatchInfo info) {
        requireStaff();
        if (info == null) {
            throw new JeecgBootException("配送员信息不能为空");
        }
        String driverName = requiredText(info.getDriverName(), "配送员", 64);
        String driverPhone = requiredText(info.getDriverPhone(), "配送员联系方式", 32);
        String remark = optionalText(info.getRemark(), "配送备注", 255);
        int updated = jdbcTemplate.update("UPDATE fresh_delivery SET driver_name = ?, driver_phone = ?, remark = ? "
                        + "WHERE id = ? AND status = ?", driverName, driverPhone, remark, id, PENDING);
        if (updated == 0) {
            FreshDelivery existing = detailForStaff(id);
            if (IN_TRANSIT.equals(existing.getStatus()) || DELIVERED.equals(existing.getStatus())) {
                throw new JeecgBootException("配送已开始，资料不可修改");
            }
        }
        return detailForStaff(id);
    }

    @Transactional(isolation = Isolation.READ_COMMITTED, rollbackFor = Exception.class)
    public FreshDelivery start(String id) {
        return transition(id, PENDING, IN_TRANSIT, true);
    }

    @Transactional(isolation = Isolation.READ_COMMITTED, rollbackFor = Exception.class)
    public FreshDelivery deliver(String id) {
        return transition(id, IN_TRANSIT, DELIVERED, false);
    }

    private FreshDelivery transition(String id, String from, String to, boolean dispatch) {
        requireStaff();
        String set = dispatch ? "status = ?, dispatch_by = ?, dispatch_at = NOW()"
                : "status = ?, delivered_by = ?, delivered_at = NOW()";
        int updated;
        if (dispatch) {
            updated = jdbcTemplate.update("UPDATE fresh_delivery SET " + set
                    + " WHERE id = ? AND status = ? AND driver_name IS NOT NULL AND driver_phone IS NOT NULL",
                    to, currentActor(), id, from);
        } else {
            updated = jdbcTemplate.update("UPDATE fresh_delivery SET " + set + " WHERE id = ? AND status = ?",
                    to, currentActor(), id, from);
        }
        FreshDelivery delivery = detailForStaff(id);
        if (updated == 0 && !to.equals(delivery.getStatus())) {
            if (dispatch && from.equals(delivery.getStatus())) {
                throw new JeecgBootException("请先填写配送员及联系方式");
            }
            throw new JeecgBootException("配送状态已变化，当前状态为" + delivery.getStatus());
        }
        return delivery;
    }

    private FreshDelivery detailForStaff(String id) {
        return detail(id, null);
    }

    private void requireStaff() {
        accessService.requireStaff();
    }

    private String currentActor() {
        return accessService.requireUser().getUsername();
    }

    private static String requiredText(String value, String label, int maxLength) {
        if (value == null || value.trim().isEmpty()) {
            throw new JeecgBootException(label + "不能为空");
        }
        String normalized = value.trim();
        if (normalized.length() > maxLength) {
            throw new JeecgBootException(label + "长度不能超过" + maxLength + "个字符");
        }
        return normalized;
    }

    private static String optionalText(String value, String label, int maxLength) {
        if (value == null || value.trim().isEmpty()) {
            return null;
        }
        return requiredText(value, label, maxLength);
    }

    private static FreshDelivery mapDelivery(ResultSet rs) throws SQLException {
        FreshDelivery delivery = new FreshDelivery();
        delivery.setId(rs.getString("id"));
        delivery.setOutboundId(rs.getString("outbound_id"));
        delivery.setOutboundNumber(rs.getString("outbound_number"));
        delivery.setStoreId(rs.getString("store_id"));
        delivery.setStoreName(rs.getString("store_name"));
        delivery.setStoreAddress(rs.getString("store_address"));
        delivery.setStatus(rs.getString("status"));
        delivery.setDriverName(rs.getString("driver_name"));
        delivery.setDriverPhone(rs.getString("driver_phone"));
        delivery.setRemark(rs.getString("remark"));
        delivery.setCreatedBy(rs.getString("created_by"));
        delivery.setCreatedAt(rs.getTimestamp("created_at"));
        delivery.setDispatchBy(rs.getString("dispatch_by"));
        delivery.setDispatchAt(rs.getTimestamp("dispatch_at"));
        delivery.setDeliveredBy(rs.getString("delivered_by"));
        delivery.setDeliveredAt(rs.getTimestamp("delivered_at"));
        return delivery;
    }

    private static FreshDeliveryItem mapItem(ResultSet rs) throws SQLException {
        FreshDeliveryItem item = new FreshDeliveryItem();
        item.setId(rs.getString("id"));
        item.setInventoryId(rs.getString("inventory_id"));
        item.setStockBatchKey(rs.getString("stock_batch_key"));
        item.setProductId(rs.getString("product_id"));
        item.setProductName(rs.getString("product_name"));
        item.setProductSpec(rs.getString("product_spec"));
        item.setUnit(rs.getString("unit"));
        item.setSupplierId(rs.getString("supplier_id"));
        item.setSupplierName(rs.getString("supplier_name"));
        item.setBatchNumber(rs.getString("batch_number"));
        item.setLocationCode(rs.getString("location_code"));
        java.sql.Date expiryDate = rs.getDate("expiry_date");
        item.setExpiryDate(expiryDate == null ? null : expiryDate.toLocalDate());
        item.setQuantity(rs.getInt("quantity"));
        return item;
    }
}
