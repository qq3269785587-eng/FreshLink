package org.jeecg.modules.wms.inventory.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import org.apache.commons.lang3.StringUtils;
import org.jeecg.modules.wms.goods.entity.WmsProducts;
import org.jeecg.modules.wms.goods.service.IWmsProductsService;
import org.jeecg.modules.wms.inventory.entity.WmsInventory;
import org.jeecg.modules.wms.inventory.entity.WmsInventoryTrans;
import org.jeecg.modules.wms.inventory.mapper.WmsInventoryTransMapper;
import org.jeecg.modules.wms.inventory.service.IWmsInventoryService;
import org.jeecg.modules.wms.inventory.service.IWmsInventoryTransService;
import org.jeecg.modules.wms.inventory.vo.WmsInventoryTransParam;
import org.jeecg.modules.wms.config.WarehouseDictEnum;
import org.jeecg.modules.wms.warehouse.entity.WmsStorageLocations;
import org.jeecg.modules.wms.warehouse.service.IWmsStorageLocationsService;
import org.springframework.beans.BeanUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Date;
import org.jeecg.common.exception.JeecgBootException;
import java.time.LocalDate;
import java.time.ZoneId;

/**
 * @Description: 收货时进行库存变更
 * @Author: jeecg-boot
 * @Date: 2025-08-30
 * @Version: V1.0
 */
@Service
public class WmsInventoryTransByReceiving extends ServiceImpl<WmsInventoryTransMapper, WmsInventoryTrans> implements IWmsInventoryTransService {

    @Autowired
    private IWmsProductsService wmsProductsService;

    @Autowired
    private IWmsStorageLocationsService wmsStorageLocationsService;

    @Autowired
    private IWmsInventoryService wmsInventoryService;


    @Transactional(rollbackFor = Exception.class)
    @Override
    public void transfer(WmsInventoryTransParam inventoryTransParam) {
        //非空判断，目标储位、商品id、执行数量,是否可售
        if (StringUtils.isEmpty(inventoryTransParam.getTargetLocationCode())
                || StringUtils.isEmpty(inventoryTransParam.getProductId())
                ||  inventoryTransParam.getExecQuantity() == null
                || StringUtils.isEmpty(inventoryTransParam.getWarehouseId())
                || StringUtils.isEmpty(inventoryTransParam.getIsSellable())) {
            throw new JeecgBootException("目标储位、食材、数量和库存属性不能为空");
        }
        int quantity = inventoryTransParam.getExecQuantity();
        boolean freshBatch = StringUtils.startsWith(inventoryTransParam.getBatchNumber(), "FL:");
        if (quantity < 1 || freshBatch && (inventoryTransParam.getExpiryDate() == null
                || inventoryTransParam.getOperationTime() == null || !"1".equals(inventoryTransParam.getIsSellable()))) {
            throw new JeecgBootException("生鲜收货必须关联有效批次、日期和正整数数量");
        }
        LocalDate expiryDate = null;
        if (freshBatch) {
            LocalDate receiveDate = inventoryTransParam.getOperationTime().toInstant()
                    .atZone(ZoneId.of("Asia/Shanghai")).toLocalDate();
            expiryDate = java.time.Instant.ofEpochMilli(inventoryTransParam.getExpiryDate().getTime())
                    .atZone(ZoneId.of("Asia/Shanghai")).toLocalDate();
            if (!expiryDate.isAfter(receiveDate)) {
                throw new JeecgBootException("到期日必须晚于收货日");
            }
        }

        //查询商品信息
        WmsProducts products = wmsProductsService.getById(inventoryTransParam.getProductId());
        if (products == null) {
            //抛出异常
            throw new RuntimeException("商品id在商品表中不存在");
        }
        //根据储位编码查询储位 信息
        LambdaQueryWrapper<WmsStorageLocations> eq = new LambdaQueryWrapper<WmsStorageLocations>().eq(WmsStorageLocations::getLocationCode, inventoryTransParam.getTargetLocationCode());
        WmsStorageLocations wmsStorageLocations = wmsStorageLocationsService.getBaseMapper().selectOne(eq);
        if (wmsStorageLocations == null) {
            //抛出异常
            throw new RuntimeException("储位编码在储位表中不存在");
        }
        if (!inventoryTransParam.getWarehouseId().equals(wmsStorageLocations.getWarehouseId())) {
            throw new JeecgBootException("收货储位不属于目标仓库");
        }
        if (freshBatch && !WarehouseDictEnum.LOCATION_TYPE_RECEIVING.getCode().equals(wmsStorageLocations.getLocationType())) {
            throw new JeecgBootException("生鲜收货库存必须先进入已启用的收货位");
        }
        String isSellable = wmsStorageLocations.getIsSellable();
        if (!freshBatch && !inventoryTransParam.getIsSellable().equals(isSellable)) {
            throw new JeecgBootException("良品放在可售储位，不良品放在不可售储位");
        }
        String inventorySellable = freshBatch ? "1" : isSellable;
        //根据唯一key获取库存
        WmsInventory wmsInventoryDb = wmsInventoryService.getInventoryByUniqueKey(inventoryTransParam.getProductId(), inventoryTransParam.getTargetLocationCode(), inventoryTransParam.getBatchNumber());
        //判断库存是否为空
        if (wmsInventoryDb == null) {

            //创建库存对象
            wmsInventoryDb = new WmsInventory();
            wmsInventoryDb.setOwnerId(products.getOwnerId());
            BeanUtils.copyProperties(inventoryTransParam,wmsInventoryDb);
            wmsInventoryDb.setStockQuantity(quantity);
            wmsInventoryDb.setLocationCode(inventoryTransParam.getTargetLocationCode());
            //如果储位是可售库存，则设置可用库存为数量
            wmsInventoryDb.setAvailableQuantity("1".equals(inventorySellable) ? quantity : 0);
            wmsInventoryDb.setAllocatedQuantity(0);
            //是否可售
            wmsInventoryDb.setIsSellable(inventorySellable);
            //入库时间
            wmsInventoryDb.setStockInTime(inventoryTransParam.getOperationTime());
            if (!wmsInventoryService.save(wmsInventoryDb)) {
                throw new JeecgBootException("收货库存写入失败");
            }
        }else{
            if (freshBatch && (wmsInventoryDb.getExpiryDate() == null || !expiryDate.equals(java.time.Instant.ofEpochMilli(wmsInventoryDb.getExpiryDate().getTime())
                    .atZone(ZoneId.of("Asia/Shanghai")).toLocalDate()))) {
                throw new JeecgBootException("同一入库批次的到期日不能变更");
            }
            LambdaUpdateWrapper<WmsInventory> wmsInventoryLambdaUpdateWrapper = new LambdaUpdateWrapper<WmsInventory>()
                    .eq(WmsInventory::getId, wmsInventoryDb.getId())
                    .setSql("stock_quantity=stock_quantity+{0}", quantity)
                    .setSql("1".equals(inventorySellable), "available_quantity=available_quantity+{0}", quantity)
                    .le(WmsInventory::getStockQuantity, Integer.MAX_VALUE - quantity)
                    .le("1".equals(inventorySellable), WmsInventory::getAvailableQuantity, Integer.MAX_VALUE - quantity);
            if (!wmsInventoryService.update(null, wmsInventoryLambdaUpdateWrapper)) {
                throw new JeecgBootException("库存数量超出系统上限，请拆分入库");
            }

        }
        //插入库存变更表
        WmsInventoryTrans wmsInventoryTrans = new WmsInventoryTrans();
        wmsInventoryTrans.setProductId(inventoryTransParam.getProductId());
        wmsInventoryTrans.setLocationCode(inventoryTransParam.getTargetLocationCode());
        wmsInventoryTrans.setBatchNumber(inventoryTransParam.getBatchNumber());
        wmsInventoryTrans.setChangeQuantity(inventoryTransParam.getExecQuantity());
        wmsInventoryTrans.setTransactionType(inventoryTransParam.getTransactionType());
        wmsInventoryTrans.setRemarks(inventoryTransParam.getRemarks());
        wmsInventoryTrans.setTransactionTime(new Date());
        if (!save(wmsInventoryTrans)) {
            throw new JeecgBootException("收货库存流水写入失败");
        }

    }
}
