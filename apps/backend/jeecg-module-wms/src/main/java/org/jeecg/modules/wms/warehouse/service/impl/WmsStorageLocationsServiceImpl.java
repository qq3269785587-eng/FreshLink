package org.jeecg.modules.wms.warehouse.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.fresh.support.FreshReferenceGuard;
import org.jeecg.modules.wms.fresh.support.FreshValidation;
import org.jeecg.modules.wms.warehouse.entity.WmsStorageLocations;
import org.jeecg.modules.wms.warehouse.entity.WmsStorageZones;
import org.jeecg.modules.wms.warehouse.entity.WmsWarehouses;
import org.jeecg.modules.wms.warehouse.service.IWmsStorageZonesService;
import org.jeecg.modules.wms.warehouse.service.IWmsWarehousesService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.transaction.annotation.Transactional;
import org.jeecg.modules.wms.warehouse.mapper.WmsStorageLocationsMapper;
import org.jeecg.modules.wms.warehouse.service.IWmsStorageLocationsService;
import org.springframework.stereotype.Service;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;

/**
 * @Description: 库位表
 * @Author: jeecg-boot
 * @Date:   2025-04-10
 * @Version: V1.0
 */
@Service
public class WmsStorageLocationsServiceImpl extends ServiceImpl<WmsStorageLocationsMapper, WmsStorageLocations> implements IWmsStorageLocationsService {

    @Autowired
    private IWmsStorageZonesService zones;
    @Autowired
    private IWmsWarehousesService warehouses;
    @Autowired
    private FreshReferenceGuard references;

    @Override
    public void createMaster(WmsStorageLocations location) {
        location.setId(null);
        saveMaster(location, null);
    }

    @Override
    public void updateMaster(WmsStorageLocations location) {
        WmsStorageLocations existing = requireLocation(location.getId());
        if (location.getStatus() == null) {
            location.setStatus(existing.getStatus());
        }
        saveMaster(location, existing);
    }

    private void saveMaster(WmsStorageLocations location, WmsStorageLocations existing) {
        location.setLocationCode(FreshValidation.text(location.getLocationCode(), "储位编码", 32));
        location.setLocationCategory(FreshValidation.text(location.getLocationCategory(), "储位类别", 100));
        location.setLocationType(FreshValidation.text(location.getLocationType(), "储位类型", 50));
        location.setStatus(WmsMasterData.status(location.getStatus()));
        location.setIsSellable(WmsMasterData.sellable(location.getIsSellable()));
        location.setZoneId(FreshValidation.text(location.getZoneId(), "所属库区", 32));
        WmsStorageZones zone = zones.getById(location.getZoneId());
        if (zone == null || warehouses.getById(zone.getWarehouseId()) == null) {
            throw new JeecgBootException("所属库区或仓库不存在");
        }
        if (location.getWarehouseId() != null && !zone.getWarehouseId().equals(location.getWarehouseId())) {
            throw new JeecgBootException("库区不属于所选仓库");
        }
        location.setWarehouseId(zone.getWarehouseId());
        boolean update = existing != null;
        if (update && (!existing.getLocationCode().equals(location.getLocationCode())
                || !existing.getWarehouseId().equals(location.getWarehouseId()))) {
            references.assertLocationUnreferenced(existing.getLocationCode());
        }
        if (lambdaQuery().eq(WmsStorageLocations::getLocationCode, location.getLocationCode())
                .ne(update, WmsStorageLocations::getId, location.getId()).exists()) {
            throw new JeecgBootException("储位编码已存在");
        }
        try {
            if (!(update ? updateById(location) : save(location))) {
                throw new JeecgBootException("保存储位失败");
            }
        } catch (DuplicateKeyException e) {
            throw new JeecgBootException("储位编码已存在");
        }
    }

    @Override
    public void setEnabled(String id, boolean enabled) {
        String locationId = FreshValidation.text(id, "储位ID", 36);
        var update = lambdaUpdate().eq(WmsStorageLocations::getId, locationId);
        if (enabled) {
            update.in(WmsStorageLocations::getStatus, WmsMasterData.CREATED, WmsMasterData.INACTIVE);
        } else {
            update.eq(WmsStorageLocations::getStatus, WmsMasterData.ACTIVE);
        }
        if (!update.set(WmsStorageLocations::getStatus, enabled ? WmsMasterData.ACTIVE : WmsMasterData.INACTIVE).update()) {
            throw new JeecgBootException(enabled ? "只能启用创建中或已禁用的储位" : "只能禁用已启用的储位");
        }
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void deleteMaster(String id) {
        WmsStorageLocations location = requireLocation(id);
        references.assertLocationUnreferenced(location.getLocationCode());
        if (!removeById(location.getId())) {
            throw new JeecgBootException("删除储位失败");
        }
    }

    private WmsStorageLocations requireLocation(String id) {
        WmsStorageLocations location = getById(FreshValidation.text(id, "储位ID", 36));
        if (location == null) {
            throw new JeecgBootException("储位不存在");
        }
        return location;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public String requireActivePutawayTarget(String warehouseId, String locationCode) {
        String targetWarehouse = FreshValidation.text(warehouseId, "目标仓库", 36);
        String targetCode = FreshValidation.text(locationCode, "目标储位", 50);
        // Lock throughout the putaway transaction so a concurrent disable cannot change the target midway.
        WmsWarehouses warehouse = warehouses.getOne(new LambdaQueryWrapper<WmsWarehouses>()
                .eq(WmsWarehouses::getId, targetWarehouse).last("FOR UPDATE"));
        if (warehouse == null || !WmsMasterData.ACTIVE.equals(warehouse.getStatus())) {
            throw new JeecgBootException("目标仓库不存在或未启用");
        }
        WmsStorageLocations location = lambdaQuery().eq(WmsStorageLocations::getWarehouseId, targetWarehouse)
                .eq(WmsStorageLocations::getLocationCode, targetCode).last("FOR UPDATE").one();
        if (location == null || !WmsMasterData.ACTIVE.equals(location.getStatus())) {
            throw new JeecgBootException("目标储位不存在或未启用");
        }
        WmsStorageZones zone = zones.getOne(new LambdaQueryWrapper<WmsStorageZones>()
                .eq(WmsStorageZones::getId, location.getZoneId())
                .eq(WmsStorageZones::getWarehouseId, targetWarehouse).last("FOR UPDATE"));
        if (zone == null || !WmsMasterData.ACTIVE.equals(zone.getStatus())) {
            throw new JeecgBootException("目标库区不存在或未启用");
        }
        return location.getLocationCode();
    }
}
