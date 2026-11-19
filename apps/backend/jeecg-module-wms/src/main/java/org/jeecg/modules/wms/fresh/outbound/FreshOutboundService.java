package org.jeecg.modules.wms.fresh.outbound;

import com.fasterxml.jackson.databind.JsonNode;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.fresh.access.FreshAccessService;
import org.jeecg.modules.wms.fresh.delivery.FreshDeliveryService;
import org.jeecg.modules.wms.inventory.entity.WmsInventory;
import org.jeecg.modules.wms.inventory.service.FreshOutboundInventory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Date;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;

@Service
public class FreshOutboundService {
    private static final String DRAFT = "DRAFT";
    private static final String CONFIRMED = "CONFIRMED";
    private static final int MAX_LINES = 100;
    private static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Shanghai");
    private static final RowMapper<Outbound> ORDER_ROW = (rs, row) -> new Outbound(
            rs.getString("id"), rs.getString("order_number"), rs.getString("store_id"),
            rs.getString("store_name"), rs.getString("status"), rs.getString("created_by"),
            rs.getObject("created_at", LocalDateTime.class), rs.getString("confirmed_by"),
            rs.getObject("confirmed_at", LocalDateTime.class));
    private static final RowMapper<OutboundLine> LINE_ROW = (rs, row) -> new OutboundLine(
            rs.getString("id"), rs.getString("inventory_id"), rs.getString("stock_batch_key"),
            rs.getString("product_id"), rs.getString("product_name"), rs.getString("product_spec"),
            rs.getString("unit"), rs.getString("supplier_id"), rs.getString("supplier_name"),
            rs.getString("batch_number"), rs.getString("location_code"),
            rs.getObject("expiry_date", LocalDate.class), rs.getInt("quantity"));

    private final JdbcTemplate jdbc;
    private final FreshAccessService access;
    private final FreshOutboundInventory inventory;
    private final FreshDeliveryService delivery;

    public FreshOutboundService(JdbcTemplate jdbc, FreshAccessService access,
                                FreshOutboundInventory inventory, FreshDeliveryService delivery) {
        this.jdbc = jdbc;
        this.access = access;
        this.inventory = inventory;
        this.delivery = delivery;
    }

    @Transactional(readOnly = true)
    public OutboundPage list(int pageNo, int pageSize, String storeId, String status, String stockBatchKey) {
        access.requireStaff();
        if (pageNo < 1 || pageSize < 1 || pageSize > 100) {
            throw new JeecgBootException("页码必须为正整数，每页支持 1 到 100 条");
        }
        if (status != null && !DRAFT.equals(status) && !CONFIRMED.equals(status)) {
            throw new JeecgBootException("出库状态不合法");
        }
        StringBuilder filter = new StringBuilder(" FROM fresh_outbound o WHERE 1 = 1");
        List<Object> args = new ArrayList<>();
        if (storeId != null) {
            filter.append(" AND o.store_id = ?");
            args.add(storeId);
        }
        if (status != null) {
            filter.append(" AND o.status = ?");
            args.add(status);
        }
        if (stockBatchKey != null) {
            filter.append(" AND EXISTS (SELECT 1 FROM fresh_outbound_item i WHERE i.outbound_id = o.id AND i.stock_batch_key = ?)");
            args.add(stockBatchKey);
        }
        long total = jdbc.queryForObject("SELECT COUNT(*)" + filter, Long.class, args.toArray());
        args.add(pageSize);
        args.add((pageNo - 1L) * pageSize);
        List<Outbound> records = jdbc.query("SELECT o.*" + filter + " ORDER BY o.created_at DESC, o.id DESC LIMIT ? OFFSET ?",
                ORDER_ROW, args.toArray());
        return new OutboundPage(records, total, pageNo, pageSize);
    }

    @Transactional(readOnly = true)
    public OutboundDetail detail(String id) {
        access.requireStaff();
        Outbound order = order(id, false);
        String deliveryId = CONFIRMED.equals(order.status()) ? delivery.findIdByOutbound(id) : null;
        return new OutboundDetail(order, lines(id), deliveryId);
    }

    @Transactional(isolation = Isolation.READ_COMMITTED, rollbackFor = Exception.class)
    public OutboundDetail createDraft(DraftRequest request) {
        access.requireStaff();
        Map<String, Selection> selections = selections(request);
        StoreSnapshot store = activeStore(request.storeId());
        String id = newId();
        String number = "FLO-" + id.substring(0, 28);
        jdbc.update("""
                INSERT INTO fresh_outbound (id, order_number, store_id, store_name, status, created_by, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, id, number, store.id(), store.name(), DRAFT, access.requireUser().getUsername(), now());
        saveDraftLines(id, selections);
        return detail(id);
    }

    @Transactional(isolation = Isolation.READ_COMMITTED, rollbackFor = Exception.class)
    public OutboundDetail editDraft(String id, DraftRequest request) {
        access.requireStaff();
        requireDraft(order(id, true));
        Map<String, Selection> selections = selections(request);
        StoreSnapshot store = activeStore(request.storeId());
        jdbc.update("UPDATE fresh_outbound SET store_id = ?, store_name = ? WHERE id = ?", store.id(), store.name(), id);
        jdbc.update("DELETE FROM fresh_outbound_item WHERE outbound_id = ?", id);
        saveDraftLines(id, selections);
        return detail(id);
    }

    @Transactional(isolation = Isolation.READ_COMMITTED, rollbackFor = Exception.class)
    public void deleteDraft(String id) {
        access.requireStaff();
        requireDraft(order(id, true));
        jdbc.update("DELETE FROM fresh_outbound_item WHERE outbound_id = ?", id);
        jdbc.update("DELETE FROM fresh_outbound WHERE id = ?", id);
    }

    @Transactional(isolation = Isolation.READ_COMMITTED, rollbackFor = Exception.class)
    public OutboundDetail confirm(String id) {
        access.requireStaff();
        Outbound order = order(id, true);
        // The order lock serializes confirmations and draft edits.
        if (CONFIRMED.equals(order.status())) {
            return new OutboundDetail(order, lines(id), delivery.findIdByOutbound(id));
        }
        requireDraft(order);
        StoreSnapshot store = activeStore(order.storeId());
        String operator = access.requireUser().getUsername();
        List<OutboundLine> items = lines(id);
        if (items.isEmpty()) {
            throw new JeecgBootException("出库单至少需要一条明细");
        }
        for (OutboundLine item : items) {
            WmsInventory stock = inventory.deduct(item.inventoryId(), item.stockBatchKey(),
                    item.quantity(), order.orderNumber(), operator);
            jdbc.update("""
                    UPDATE fresh_outbound_item
                    SET product_name = ?, product_spec = ?, unit = ?, supplier_name = ?,
                        batch_number = ?, location_code = ?, expiry_date = ?
                    WHERE id = ?
                    """, stock.getProductName(), stock.getProductSpec(), stock.getUnit(), stock.getSupplierName(),
                    stock.getBatchNumber(), stock.getLocationCode(), expiryDate(stock), item.id());
        }
        jdbc.update("""
                UPDATE fresh_outbound SET store_name = ?, status = ?, confirmed_by = ?, confirmed_at = ?
                WHERE id = ?
                """, store.name(), CONFIRMED, operator, now(), id);
        String deliveryId = delivery.createPending(id, order.orderNumber(), store.id(), store.name(), store.address());
        return new OutboundDetail(order(id, false), lines(id), deliveryId);
    }

    private void saveDraftLines(String id, Map<String, Selection> selections) {
        for (Map.Entry<String, Selection> entry : selections.entrySet()) {
            Selection line = entry.getValue();
            WmsInventory stock = inventory.requireEligible(entry.getKey(), line.stockBatchKey());
            jdbc.update("""
                    INSERT INTO fresh_outbound_item
                    (id, outbound_id, inventory_id, stock_batch_key, product_id, product_name, product_spec,
                     unit, supplier_id, supplier_name, batch_number, location_code, expiry_date, quantity)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, newId(), id, entry.getKey(), line.stockBatchKey(), stock.getProductId(), stock.getProductName(),
                    stock.getProductSpec(), stock.getUnit(), stock.getSupplierId(), stock.getSupplierName(),
                    stock.getBatchNumber(), stock.getLocationCode(), expiryDate(stock), line.quantity());
        }
    }

    private static Date expiryDate(WmsInventory stock) {
        return new Date(stock.getExpiryDate().getTime());
    }

    static Map<String, Selection> selections(DraftRequest request) {
        if (request == null || request.lines() == null || request.lines().isEmpty() || request.lines().size() > MAX_LINES) {
            throw new JeecgBootException("出库单须填写 1 到 100 条明细");
        }
        Map<String, Selection> selections = new TreeMap<>();
        for (DraftLine line : request.lines()) {
            if (line == null || !validKey(line.inventoryId(), 36) || !validKey(line.stockBatchKey(), 64)) {
                throw new JeecgBootException("请选择有效的库存行和内部批次");
            }
            JsonNode quantity = line.quantity();
            if (quantity == null || !quantity.isIntegralNumber() || !quantity.canConvertToInt() || quantity.intValue() <= 0) {
                throw new JeecgBootException("出库数量必须为 1 到 2147483647 的整数");
            }
            Selection previous = selections.get(line.inventoryId());
            if (previous == null) {
                selections.put(line.inventoryId(), new Selection(line.stockBatchKey(), quantity.intValue()));
                continue;
            }
            long total = (long) previous.quantity() + quantity.intValue();
            if (!previous.stockBatchKey().equals(line.stockBatchKey()) || total > Integer.MAX_VALUE) {
                throw new JeecgBootException("同一库存行的内部批次须一致，合计数量不得超出整数范围");
            }
            selections.put(line.inventoryId(), new Selection(line.stockBatchKey(), (int) total));
        }
        return selections;
    }

    private StoreSnapshot activeStore(String id) {
        if (!validKey(id, 36)) {
            throw new JeecgBootException("请选择启用门店");
        }
        List<StoreSnapshot> stores = jdbc.query("""
                SELECT id, store_name, address FROM fresh_store WHERE id = ? AND status = 'ACTIVE' FOR SHARE
                """, (rs, row) -> new StoreSnapshot(rs.getString(1), rs.getString(2), rs.getString(3)), id);
        if (stores.isEmpty()) {
            throw new JeecgBootException("门店不存在或已禁用");
        }
        return stores.get(0);
    }

    private Outbound order(String id, boolean lock) {
        List<Outbound> rows = jdbc.query("SELECT * FROM fresh_outbound WHERE id = ?" + (lock ? " FOR UPDATE" : ""),
                ORDER_ROW, id);
        if (rows.isEmpty()) {
            throw new JeecgBootException("出库单不存在");
        }
        return rows.get(0);
    }

    private List<OutboundLine> lines(String id) {
        return jdbc.query("SELECT * FROM fresh_outbound_item WHERE outbound_id = ? ORDER BY inventory_id", LINE_ROW, id);
    }

    private static void requireDraft(Outbound order) {
        if (!DRAFT.equals(order.status())) {
            throw new JeecgBootException("仅草稿可修改或删除");
        }
    }

    private static boolean validKey(String value, int maxLength) {
        return value != null && !value.isBlank() && value.length() <= maxLength;
    }

    private static String newId() {
        return UUID.randomUUID().toString().replace("-", "");
    }

    private static LocalDateTime now() {
        return LocalDateTime.now(BUSINESS_ZONE);
    }

    public record DraftRequest(String storeId, List<DraftLine> lines) {}
    public record DraftLine(String inventoryId, String stockBatchKey, JsonNode quantity) {}
    public record Outbound(String id, String orderNumber, String storeId, String storeName, String status,
                           String createdBy, LocalDateTime createdAt, String confirmedBy, LocalDateTime confirmedAt) {}
    public record OutboundLine(String id, String inventoryId, String stockBatchKey, String productId,
                               String productName, String productSpec, String unit, String supplierId,
                               String supplierName, String batchNumber, String locationCode, LocalDate expiryDate, int quantity) {}
    public record OutboundDetail(Outbound order, List<OutboundLine> lines, String deliveryId) {}
    public record OutboundPage(List<Outbound> records, long total, int current, int size) {}
    record Selection(String stockBatchKey, int quantity) {}
    private record StoreSnapshot(String id, String name, String address) {}
}
