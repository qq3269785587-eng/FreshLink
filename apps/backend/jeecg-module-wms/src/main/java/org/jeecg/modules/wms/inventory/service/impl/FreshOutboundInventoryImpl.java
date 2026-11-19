package org.jeecg.modules.wms.inventory.service.impl;

import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.config.WarehouseDictEnum;
import org.jeecg.modules.wms.inventory.entity.WmsInventory;
import org.jeecg.modules.wms.inventory.entity.WmsInventoryTrans;
import org.jeecg.modules.wms.inventory.mapper.WmsInventoryMapper;
import org.jeecg.modules.wms.inventory.mapper.WmsInventoryTransMapper;
import org.jeecg.modules.wms.inventory.service.FreshOutboundInventory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Date;
import java.util.Objects;

@Service
public class FreshOutboundInventoryImpl implements FreshOutboundInventory {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Shanghai");

    private final WmsInventoryMapper inventoryMapper;
    private final WmsInventoryTransMapper transactionMapper;

    public FreshOutboundInventoryImpl(WmsInventoryMapper inventoryMapper,
                                      WmsInventoryTransMapper transactionMapper) {
        this.inventoryMapper = inventoryMapper;
        this.transactionMapper = transactionMapper;
    }

    @Override
    public WmsInventory requireEligible(String inventoryId, String stockBatchKey) {
        return requireEligibleSnapshot(load(inventoryId, stockBatchKey));
    }

    @Override
    @Transactional(propagation = org.springframework.transaction.annotation.Propagation.MANDATORY,
            rollbackFor = Exception.class)
    public WmsInventory deduct(String inventoryId, String stockBatchKey, int quantity,
                               String outboundNumber, String operator) {
        if (quantity <= 0) {
            throw new JeecgBootException("出库数量必须为正整数");
        }
        if (outboundNumber == null || outboundNumber.isBlank()) {
            throw new JeecgBootException("出库单号不能为空");
        }

        WmsInventory inventory = inventoryMapper.lockFreshOutboundStock(inventoryId, stockBatchKey);
        requireExactKey(inventory, inventoryId, stockBatchKey);
        inventory = requireEligibleSnapshot(inventory);
        if (inventory.getAvailableQuantity() < quantity) {
            throw new JeecgBootException("批次可出库数量不足");
        }

        int stockQuantity = inventory.getStockQuantity();
        int availableQuantity = inventory.getAvailableQuantity();
        LambdaUpdateWrapper<WmsInventory> update = new LambdaUpdateWrapper<WmsInventory>()
                .eq(WmsInventory::getId, inventoryId)
                .eq(WmsInventory::getBatchNumber, stockBatchKey)
                .eq(WmsInventory::getStockQuantity, stockQuantity)
                .eq(WmsInventory::getAvailableQuantity, availableQuantity)
                .eq(WmsInventory::getAllocatedQuantity, inventory.getAllocatedQuantity())
                .ge(WmsInventory::getStockQuantity, quantity)
                .ge(WmsInventory::getAvailableQuantity, quantity)
                .setSql("stock_quantity=stock_quantity-{0}", quantity)
                .setSql("available_quantity=available_quantity-{0}", quantity);
        if (inventoryMapper.update(null, update) != 1) {
            throw new JeecgBootException("库存已变化，请刷新后重试");
        }

        WmsInventoryTrans transaction = new WmsInventoryTrans();
        transaction.setProductId(inventory.getProductId());
        transaction.setLocationCode(inventory.getLocationCode());
        transaction.setBatchNumber(stockBatchKey);
        transaction.setChangeQuantity(-quantity);
        transaction.setTransactionType(WarehouseDictEnum.INVENTORY_OUTBOUND.getCode());
        transaction.setReferenceNumber(outboundNumber);
        transaction.setRemarks("D3人工选批出库");
        transaction.setTransactionTime(new Date());
        transaction.setCreateBy(operator);
        if (transactionMapper.insert(transaction) != 1) {
            throw new JeecgBootException("出库库存流水写入失败");
        }

        return inventory;
    }

    private WmsInventory load(String inventoryId, String stockBatchKey) {
        if (inventoryId == null || inventoryId.isBlank()
                || stockBatchKey == null || stockBatchKey.isBlank()) {
            throw new JeecgBootException("库存行和库存批次不能为空");
        }
        WmsInventory inventory = inventoryMapper.findFreshOutboundStock(inventoryId, stockBatchKey);
        requireExactKey(inventory, inventoryId, stockBatchKey);
        return inventory;
    }

    private void requireExactKey(WmsInventory inventory, String inventoryId, String stockBatchKey) {
        if (inventory == null) {
            return;
        }
        if (!Objects.equals(inventoryId, inventory.getId())
                || !Objects.equals(stockBatchKey, inventory.getStockBatchKey())) {
            throw new JeecgBootException("库存行或库存批次标识不匹配");
        }
    }

    private WmsInventory requireEligibleSnapshot(WmsInventory inventory) {
        if (inventory == null) {
            throw new JeecgBootException("库存批次不存在或批次标识不匹配");
        }
        if (inventory.getStockBatchKey() == null || !inventory.getStockBatchKey().startsWith("FL:")) {
            throw new JeecgBootException("历史库存缺少可核验的入库来源");
        }
        if (inventory.getInboundOrderItemId() == null || inventory.getInboundOrderId() == null
                || inventory.getSupplierId() == null || inventory.getSupplierName() == null
                || inventory.getDisplayBatchNumber() == null
                || inventory.getProductionDate() == null || inventory.getSourceExpiryDate() == null
                || inventory.getExpiryDate() == null
                || !businessDate(inventory.getSourceExpiryDate()).equals(businessDate(inventory.getExpiryDate()))) {
            throw new JeecgBootException("库存批次来源或日期待核验，不能出库");
        }
        LocalDate productionDate = businessDate(inventory.getProductionDate());
        LocalDate expiryDate = businessDate(inventory.getSourceExpiryDate());
        LocalDate today = LocalDate.now(BUSINESS_ZONE);
        if (productionDate.isAfter(today) || !expiryDate.isAfter(productionDate) || !expiryDate.isAfter(today)) {
            throw new JeecgBootException("库存批次已过期或日期无效，不能出库");
        }
        if (!"ACTIVE".equals(inventory.getProductStatus())) {
            throw new JeecgBootException("商品已停用，不能出库");
        }
        if (!"1".equals(inventory.getIsSellable())
                || !(WarehouseDictEnum.LOCATION_TYPE_STORAGE.getCode().equals(inventory.getLocationType())
                || WarehouseDictEnum.LOCATION_TYPE_PICKING.getCode().equals(inventory.getLocationType()))) {
            throw new JeecgBootException("库存不是可出库的良品正式储位库存");
        }
        if (!"1".equals(inventory.getLocationSellable())) {
            throw new JeecgBootException("库存储位不可出库");
        }

        Integer stock = inventory.getStockQuantity();
        Integer available = inventory.getAvailableQuantity();
        Integer allocated = inventory.getAllocatedQuantity();
        if (stock == null || available == null || allocated == null || stock < 0 || available < 0 || allocated < 0
                || (long) available + allocated != stock) {
            throw new JeecgBootException("库存数量账目不一致，不能出库");
        }
        inventory.setExpiryStatus(expiryStatus(today, expiryDate, inventory.getNearExpiryDays()));
        inventory.setRemainingDays(java.time.temporal.ChronoUnit.DAYS.between(today, expiryDate));
        inventory.setEligibleQuantity(available);
        inventory.setBatchNumber(inventory.getDisplayBatchNumber());
        return inventory;
    }

    private String expiryStatus(LocalDate today, LocalDate expiry, Integer nearExpiryDays) {
        long remaining = java.time.temporal.ChronoUnit.DAYS.between(today, expiry);
        return remaining <= 0 ? "EXPIRED"
                : remaining <= (nearExpiryDays == null ? 0 : nearExpiryDays) ? "NEAR_EXPIRY" : "NORMAL";
    }

    private LocalDate businessDate(Date date) {
        if (date instanceof java.sql.Date sqlDate) {
            return sqlDate.toLocalDate();
        }
        return Instant.ofEpochMilli(date.getTime()).atZone(BUSINESS_ZONE).toLocalDate();
    }
}
