package org.jeecg.modules.wms.inventory.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import org.apache.commons.lang3.StringUtils;
import org.jeecg.modules.wms.config.WarehouseDictEnum;
import org.jeecg.modules.wms.goods.entity.WmsProducts;
import org.jeecg.modules.wms.goods.service.IWmsProductsService;
import org.jeecg.modules.wms.inventory.entity.WmsInventory;
import org.jeecg.modules.wms.inventory.entity.WmsInventoryTrans;
import org.jeecg.modules.wms.inventory.mapper.WmsInventoryTransMapper;
import org.jeecg.modules.wms.inventory.service.IWmsInventoryService;
import org.jeecg.modules.wms.inventory.service.IWmsInventoryTransService;
import org.jeecg.modules.wms.inventory.vo.WmsInventoryTransParam;
import org.jeecg.modules.wms.warehouse.entity.WmsStorageLocations;
import org.jeecg.modules.wms.warehouse.service.IWmsStorageLocationsService;
import org.jeecg.modules.wms.wmstask.entity.WmsTasksRecords;
import org.springframework.beans.BeanUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Date;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.config.WarehouseDictEnum;
import java.time.Instant;
import java.time.ZoneId;

/**
 * @author Mr.M
 * @version 1.0
 * @description 上架执行库存变更
 * @date 2025/7/19 16:23
 */
@Service
public class WmsInventoryTransByPutway extends ServiceImpl<WmsInventoryTransMapper, WmsInventoryTrans> implements IWmsInventoryTransService {

    //    @Autowired
//    public WmsInventoryTransByReceiving(IWmsInventoryService wmsInventoryService, IWmsInventoryTransService wmsInventoryTransService, IWmsStorageLocationsService wmsStorageLocationsService, IWmsStorageZonesService wmsStorageZonesService, IWmsProductsService wmsProductsService){
//        super(wmsInventoryService, wmsInventoryTransService, wmsStorageLocationsService, wmsStorageZonesService, wmsProductsService);
//    }
    @Autowired
    private IWmsInventoryService wmsInventoryService;

    //注入库存变更表service
//    @Autowired
//    private IWmsInventoryTransService wmsInventoryTransService;

    //注入储位表service
    @Autowired
    private IWmsStorageLocationsService wmsStorageLocationsService;

    //注入商品service
    @Autowired
    private IWmsProductsService wmsProductsService;
    @Override
    @Transactional(rollbackFor = Exception.class)
    public void transfer(WmsInventoryTransParam inventoryTransParam) {
        boolean freshBatch = StringUtils.startsWith(inventoryTransParam.getBatchNumber(), "FL:");
        //非空判断，商品id、原始储位编码、目标储位编码、数量不能为空
        if (StringUtils.isEmpty(inventoryTransParam.getProductId())
                || StringUtils.isEmpty(inventoryTransParam.getSourceLocationCode())
                || StringUtils.isEmpty(inventoryTransParam.getTargetLocationCode())
                || inventoryTransParam.getExecQuantity() == null
                || freshBatch && inventoryTransParam.getExpiryDate() == null) {
            //抛出异常
            throw new RuntimeException("请填写商品id、原始储位编码、目标储位编码、数量");
        }
        int quantity = inventoryTransParam.getExecQuantity();
        if (quantity < 1) {
            throw new JeecgBootException("上架数量必须为正整数");
        }

        //查询商品信息
        WmsProducts products = wmsProductsService.getById(inventoryTransParam.getProductId());
        if (products == null) {
            //抛出异常
            throw new RuntimeException("商品id在商品表中不存在");
        }
        //===================源储位扣减库存=====================
        //根据源储位编码、商品id、容器编码查询库存表
        WmsInventory wmsInventorySource = wmsInventoryService.getInventoryByUniqueKey(inventoryTransParam.getProductId(), inventoryTransParam.getSourceLocationCode(), inventoryTransParam.getBatchNumber());
        //如果wmsInventorySource为空则抛出异常
        if (wmsInventorySource == null) {
            //抛出异常
            throw new RuntimeException("源储位编码或商品id在库存中不存在");
        }
        WmsStorageLocations sourceLocation = wmsStorageLocationsService.lambdaQuery()
                .eq(WmsStorageLocations::getLocationCode, inventoryTransParam.getSourceLocationCode())
                .eq(WmsStorageLocations::getWarehouseId, inventoryTransParam.getWarehouseId()).one();
        if (freshBatch && (sourceLocation == null
                || !WarehouseDictEnum.LOCATION_TYPE_RECEIVING.getCode().equals(sourceLocation.getLocationType()))) {
            throw new JeecgBootException("来源库存不是该仓库的收货暂存库存");
        }
        if (freshBatch && (wmsInventorySource.getExpiryDate() == null
                || !Instant.ofEpochMilli(wmsInventorySource.getExpiryDate().getTime())
                .atZone(ZoneId.of("Asia/Shanghai")).toLocalDate().equals(
                        Instant.ofEpochMilli(inventoryTransParam.getExpiryDate().getTime())
                                .atZone(ZoneId.of("Asia/Shanghai")).toLocalDate()))) {
            throw new JeecgBootException("上架批次日期与收货库存不一致");
        }
        int sourceAvailable = wmsInventorySource.getAvailableQuantity() == null
                ? 0 : wmsInventorySource.getAvailableQuantity();
        int sourceAllocated = wmsInventorySource.getAllocatedQuantity() == null
                ? 0 : wmsInventorySource.getAllocatedQuantity();
        if (freshBatch && sourceAllocated != 0 || sourceAvailable < quantity) {
            throw new JeecgBootException("收货暂存库存不足或已被分配，不能上架");
        }
        int availableReduction = quantity;
        LambdaUpdateWrapper<WmsInventory> wmsInventoryLambdaUpdateWrapper = new LambdaUpdateWrapper<WmsInventory>()
                .eq(WmsInventory::getId, wmsInventorySource.getId())
                .setSql("stock_quantity=stock_quantity-{0}", quantity)
                .setSql("available_quantity=available_quantity-{0}", availableReduction)
                        .ge(WmsInventory::getStockQuantity, quantity)
                        .ge(WmsInventory::getAvailableQuantity, availableReduction);
        boolean update = wmsInventoryService.update(null, wmsInventoryLambdaUpdateWrapper);
        if (!update) {
            //抛出异常
            throw new RuntimeException("更新库存失败");
        }
        //插入库存变更表
        WmsInventoryTrans wmsInventoryTrans = new WmsInventoryTrans();
        wmsInventoryTrans.setProductId(inventoryTransParam.getProductId());
        wmsInventoryTrans.setLocationCode(inventoryTransParam.getSourceLocationCode());
        wmsInventoryTrans.setBatchNumber(inventoryTransParam.getBatchNumber());
        wmsInventoryTrans.setChangeQuantity(-quantity);
        wmsInventoryTrans.setTransactionType(inventoryTransParam.getTransactionType());
        wmsInventoryTrans.setRemarks(inventoryTransParam.getRemarks());
        wmsInventoryTrans.setTransactionTime(new Date());
        if (!save(wmsInventoryTrans)) {
            throw new JeecgBootException("上架来源库存流水写入失败");
        }
        //===================目标储位增加库存=====================

        LambdaQueryWrapper<WmsStorageLocations> targetQuery = new LambdaQueryWrapper<WmsStorageLocations>()
                .eq(WmsStorageLocations::getLocationCode, inventoryTransParam.getTargetLocationCode())
                .eq(WmsStorageLocations::getWarehouseId, inventoryTransParam.getWarehouseId());
        WmsStorageLocations targetLocation = wmsStorageLocationsService.getOne(targetQuery);
        if (targetLocation == null || freshBatch && (!"ACTIVE".equals(targetLocation.getStatus())
                || !WarehouseDictEnum.LOCATION_TYPE_STORAGE.getCode().equals(targetLocation.getLocationType())
                && !WarehouseDictEnum.LOCATION_TYPE_PICKING.getCode().equals(targetLocation.getLocationType())
                || !"1".equals(targetLocation.getIsSellable()))) {
            throw new JeecgBootException("目标位置不是当前仓库可用的正式储位");
        }

        //根据唯一key获取库存
        WmsInventory wmsInventoryDb = wmsInventoryService.getInventoryByUniqueKey(inventoryTransParam.getProductId(), inventoryTransParam.getTargetLocationCode(), inventoryTransParam.getBatchNumber());
        //判断库存是否为空
        if (wmsInventoryDb == null) {
            //根据储位编码查询储位 信息
            //是否可售库存
            String isSellable = targetLocation.getIsSellable();
            //创建库存对象
            wmsInventoryDb = new WmsInventory();
            BeanUtils.copyProperties(inventoryTransParam,wmsInventoryDb);
            wmsInventoryDb.setOwnerId(products.getOwnerId());
            wmsInventoryDb.setLocationCode(inventoryTransParam.getTargetLocationCode());
            wmsInventoryDb.setStockQuantity(quantity);
            //如果储位是可售库存，则设置可用库存为数量
            wmsInventoryDb.setAvailableQuantity("1".equals(isSellable) ? quantity : 0);
            wmsInventoryDb.setAllocatedQuantity(0);
            //是否可售
            wmsInventoryDb.setIsSellable(isSellable);
            //入库时间
            wmsInventoryDb.setStockInTime(inventoryTransParam.getOperationTime());
            if (!wmsInventoryService.save(wmsInventoryDb)) {
                throw new JeecgBootException("上架目标库存写入失败");
            }
        }else{
            if (freshBatch && (wmsInventoryDb.getExpiryDate() == null
                    || !Instant.ofEpochMilli(wmsInventoryDb.getExpiryDate().getTime())
                    .atZone(ZoneId.of("Asia/Shanghai")).toLocalDate().equals(
                            Instant.ofEpochMilli(inventoryTransParam.getExpiryDate().getTime())
                                    .atZone(ZoneId.of("Asia/Shanghai")).toLocalDate()))) {
                throw new JeecgBootException("目标储位中同批次日期不一致");
            }
            String isSellable = wmsInventoryDb.getIsSellable();
            LambdaUpdateWrapper<WmsInventory> wmsInventoryLambdaUpdateWrapper2 = new LambdaUpdateWrapper<WmsInventory>()
                    .eq(WmsInventory::getId, wmsInventoryDb.getId())
                    .setSql("stock_quantity=stock_quantity+{0}", quantity)
                    .setSql("1".equals(isSellable), "available_quantity=available_quantity+{0}", quantity)
                    .le(WmsInventory::getStockQuantity, Integer.MAX_VALUE - quantity)
                    .le("1".equals(isSellable), WmsInventory::getAvailableQuantity, Integer.MAX_VALUE - quantity);
            boolean update1 = wmsInventoryService.update(null, wmsInventoryLambdaUpdateWrapper2);
            if (!update1) {
                //抛出异常
                throw new RuntimeException("更新库存失败");
            }

        }
        //插入库存变更表
        WmsInventoryTrans wmsInventoryTrans2 = new WmsInventoryTrans();
        wmsInventoryTrans2.setProductId(inventoryTransParam.getProductId());
        wmsInventoryTrans2.setLocationCode(inventoryTransParam.getTargetLocationCode());
        wmsInventoryTrans2.setBatchNumber(inventoryTransParam.getBatchNumber());
        wmsInventoryTrans2.setChangeQuantity(quantity);
        wmsInventoryTrans2.setTransactionType(inventoryTransParam.getTransactionType());
        wmsInventoryTrans2.setRemarks(inventoryTransParam.getRemarks());
        wmsInventoryTrans2.setTransactionTime(new Date());
        if (!save(wmsInventoryTrans2)) {
            throw new JeecgBootException("上架目标库存流水写入失败");
        }
    }
}
