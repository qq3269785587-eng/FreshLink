package org.jeecg.modules.wms.inventory.mapper;

import java.util.List;

import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.jeecg.modules.wms.inventory.entity.WmsInventory;
import com.baomidou.mybatisplus.core.mapper.BaseMapper;

/**
 * @Description: 库存表
 * @Author: jeecg-boot
 * @Date:   2025-08-30
 * @Version: V1.0
 */
public interface WmsInventoryMapper extends BaseMapper<WmsInventory> {
    String FRESH_OUTBOUND_SQL = "SELECT a.*, b.product_name, b.status AS product_status, "
            + "b.near_expiry_days, b.product_spec, b.unit, d.location_type, "
            + "d.is_sellable AS location_sellable, a.batch_number AS stock_batch_key, "
            + "si.id AS inbound_order_item_id, si.order_id AS inbound_order_id, "
            + "si.production_date AS production_date, si.expiry_date AS source_expiry_date, "
            + "si.batch_number AS display_batch_number, sio.supplier_id AS supplier_id, "
            + "fs.supplier_name AS supplier_name FROM wms_inventory a "
            + "LEFT JOIN wms_products b ON b.id = a.product_id "
            + "LEFT JOIN wms_storage_locations d ON d.location_code = a.location_code "
            + "LEFT JOIN wms_storage_zones e ON e.id = d.zone_id "
            + "LEFT JOIN wms_stock_in_order_items si ON a.batch_number LIKE 'FL:%' "
            + "AND si.id = SUBSTRING(a.batch_number, 4) AND si.product_id = a.product_id "
            + "LEFT JOIN wms_stock_in_orders sio ON sio.id = si.order_id "
            + "LEFT JOIN fresh_supplier fs ON fs.id = sio.supplier_id "
            + "WHERE a.id = #{inventoryId} AND a.batch_number = #{stockBatchKey}";

    /**
     * 综合查询库存列表
     */
    public List<WmsInventory> queryList(WmsInventory wmsInventory);

    /** Loads the authoritative fresh-batch and location facts used to validate outbound stock. */
    @Select(FRESH_OUTBOUND_SQL)
    WmsInventory findFreshOutboundStock(@Param("inventoryId") String inventoryId,
                                        @Param("stockBatchKey") String stockBatchKey);

    /** Locks a single inventory row during the caller's outbound transaction. */
    @Select(FRESH_OUTBOUND_SQL + " FOR UPDATE")
    WmsInventory lockFreshOutboundStock(@Param("inventoryId") String inventoryId,
                                        @Param("stockBatchKey") String stockBatchKey);
}
