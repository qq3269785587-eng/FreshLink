package org.jeecg.modules.wms.inventory.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.PageDTO;
import com.github.pagehelper.Page;
import com.github.pagehelper.PageHelper;
import org.apache.commons.lang3.StringUtils;
import org.jeecg.modules.wms.inventory.entity.WmsInventory;
import org.jeecg.modules.wms.inventory.mapper.WmsInventoryMapper;
import org.jeecg.modules.wms.inventory.service.IWmsInventoryService;
import org.jeecg.modules.wms.config.WarehouseDictEnum;
import org.springframework.stereotype.Service;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;

import java.util.List;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;

/**
 * @Description: 库存表
 * @Author: jeecg-boot
 * @Date:   2025-08-30
 * @Version: V1.0
 */
@Service
public class WmsInventoryServiceImpl extends ServiceImpl<WmsInventoryMapper, WmsInventory> implements IWmsInventoryService {

    @Override
    public WmsInventory getInventoryByUniqueKey(String productId, String locationCode, String batchNumber) {
        LambdaQueryWrapper<WmsInventory> eq = new LambdaQueryWrapper<WmsInventory>()
                .eq(WmsInventory::getProductId, productId)
                .eq(WmsInventory::getLocationCode, locationCode)
                .eq(StringUtils.isNotEmpty(batchNumber),WmsInventory::getBatchNumber, batchNumber)
                .eq(StringUtils.isEmpty(batchNumber),WmsInventory::getBatchNumber,"");
        WmsInventory inventory = this.getOne(eq);

        return inventory;
    }

    @Override
    public IPage<WmsInventory> queryList(WmsInventory wmsInventory, Integer pageNo, Integer pageSize) {
        //开启分页查询,当执行查询时，插件进行相关的sql拦截进行分页操作，返回一个page对象
        Page<WmsInventory> page = PageHelper.startPage(pageNo, pageSize);
        List<WmsInventory> list = baseMapper.queryList(wmsInventory);
        LocalDate businessDate = LocalDate.now(ZoneId.of("Asia/Shanghai"));
        for (WmsInventory inventory : list) {
            if (inventory.getDisplayBatchNumber() != null) {
                inventory.setBatchNumber(inventory.getDisplayBatchNumber());
            }
            if (inventory.getSupplierId() == null || inventory.getSupplierName() == null
                    || inventory.getInboundOrderId() == null || inventory.getProductionDate() == null
                    || inventory.getSourceExpiryDate() == null || inventory.getExpiryDate() == null
                    || !toBusinessDate(inventory.getSourceExpiryDate()).equals(toBusinessDate(inventory.getExpiryDate()))) {
                inventory.setExpiryStatus("PENDING_VERIFICATION");
                inventory.setRemainingDays(null);
                inventory.setEligibleQuantity(0);
                continue;
            }
            LocalDate expiryDate = toBusinessDate(inventory.getSourceExpiryDate());
            long remainingDays = ChronoUnit.DAYS.between(businessDate, expiryDate);
            inventory.setRemainingDays(remainingDays);
            if (remainingDays <= 0) {
                inventory.setExpiryStatus("EXPIRED");
            } else {
                inventory.setExpiryStatus(remainingDays <= (inventory.getNearExpiryDays() == null ? 0 : inventory.getNearExpiryDays())
                        ? "NEAR_EXPIRY" : "NORMAL");
            }
            boolean formalLocation = WarehouseDictEnum.LOCATION_TYPE_STORAGE.getCode().equals(inventory.getLocationType())
                    || WarehouseDictEnum.LOCATION_TYPE_PICKING.getCode().equals(inventory.getLocationType());
            Integer allocatedQuantity = inventory.getAllocatedQuantity();
            Integer stockQuantity = inventory.getStockQuantity();
            boolean available = "1".equals(inventory.getIsSellable()) && formalLocation
                    && "ACTIVE".equals(inventory.getProductStatus()) && remainingDays > 0
                    && inventory.getAvailableQuantity() != null && inventory.getAvailableQuantity() > 0
                    && stockQuantity != null && allocatedQuantity != null && allocatedQuantity >= 0
                    && (long) inventory.getAvailableQuantity() + allocatedQuantity == stockQuantity;
            inventory.setEligibleQuantity(available ? inventory.getAvailableQuantity() : 0);
        }
        PageDTO<WmsInventory> wmsInventoryPageDTO = new PageDTO<>();
        wmsInventoryPageDTO.setRecords(list);
        wmsInventoryPageDTO.setTotal(page.getTotal());
        wmsInventoryPageDTO.setSize(page.getPageSize());
        wmsInventoryPageDTO.setCurrent(page.getPageNum());
        wmsInventoryPageDTO.setPages(page.getPages());
        return wmsInventoryPageDTO;
    }

    private LocalDate toBusinessDate(java.util.Date date) {
        if (date instanceof java.sql.Date sqlDate) {
            return sqlDate.toLocalDate();
        }
        return java.time.Instant.ofEpochMilli(date.getTime()).atZone(ZoneId.of("Asia/Shanghai")).toLocalDate();
    }

}
