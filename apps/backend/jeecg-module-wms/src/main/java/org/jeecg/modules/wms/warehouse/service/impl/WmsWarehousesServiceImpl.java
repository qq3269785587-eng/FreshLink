package org.jeecg.modules.wms.warehouse.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.fresh.support.FreshReferenceGuard;
import org.jeecg.modules.wms.fresh.support.FreshValidation;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.transaction.annotation.Transactional;
import org.jeecg.modules.wms.warehouse.entity.WmsWarehouses;
import org.jeecg.modules.wms.warehouse.mapper.WmsWarehousesMapper;
import org.jeecg.modules.wms.warehouse.service.IWmsWarehousesService;
import org.springframework.stereotype.Service;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;

/**
 * @Description: 仓库表
 * @Author: jeecg-boot
 * @Date:   2025-04-10
 * @Version: V1.0
 */
@Service
public class WmsWarehousesServiceImpl extends ServiceImpl<WmsWarehousesMapper, WmsWarehouses> implements IWmsWarehousesService {

    @Autowired
    private FreshReferenceGuard references;

    @Override
    public void enable(String id) {
        String warehouseId = FreshValidation.text(id, "仓库ID", 36);
        if (!lambdaUpdate().eq(WmsWarehouses::getId, warehouseId)
                .in(WmsWarehouses::getStatus, WmsMasterData.CREATED, WmsMasterData.INACTIVE)
                .set(WmsWarehouses::getStatus, WmsMasterData.ACTIVE).update()) {
            throw new JeecgBootException("只能启用创建中或已禁用的仓库");
        }
    }

    @Override
    public void disable(String id) {
        String warehouseId = FreshValidation.text(id, "仓库ID", 36);
        if (!lambdaUpdate().eq(WmsWarehouses::getId, warehouseId)
                .eq(WmsWarehouses::getStatus, WmsMasterData.ACTIVE)
                .set(WmsWarehouses::getStatus, WmsMasterData.INACTIVE).update()) {
            throw new JeecgBootException("只能禁用已启用的仓库");
        }
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void delete(String id) {
        WmsWarehouses warehouse = requireWarehouse(id);
        references.assertWarehouseUnreferenced(warehouse.getId(), warehouse.getWarehouseCode());
        if (!WmsMasterData.CREATED.equals(warehouse.getStatus())) {
            throw new JeecgBootException("只能删除创建状态的仓库");
        }
        if (!removeById(warehouse.getId())) {
            throw new JeecgBootException("删除仓库失败");
        }
    }

    @Override
    public void add(WmsWarehouses warehouse) {
        warehouse.setId(null);
        warehouse.setStatus(WmsMasterData.CREATED);
        saveMaster(warehouse, false);
    }

    @Override
    public void edit(WmsWarehouses warehouse) {
        requireWarehouse(warehouse.getId());
        // Warehouse status is managed only by enable and disable.
        warehouse.setStatus(null);
        saveMaster(warehouse, true);
    }

    private void saveMaster(WmsWarehouses warehouse, boolean update) {
        warehouse.setWarehouseCode(FreshValidation.text(warehouse.getWarehouseCode(), "仓库编码", 50));
        warehouse.setWarehouseName(FreshValidation.text(warehouse.getWarehouseName(), "仓库名称", 100));
        warehouse.setWarehouseAttr(FreshValidation.text(warehouse.getWarehouseAttr(), "仓库属性", 50));
        LambdaQueryWrapper<WmsWarehouses> duplicate = new LambdaQueryWrapper<WmsWarehouses>()
                .eq(WmsWarehouses::getWarehouseCode, warehouse.getWarehouseCode())
                .ne(update, WmsWarehouses::getId, warehouse.getId());
        if (count(duplicate) > 0) {
            throw new JeecgBootException("仓库编码已存在");
        }
        try {
            if (!(update ? updateById(warehouse) : save(warehouse))) {
                throw new JeecgBootException("保存仓库失败");
            }
        } catch (DuplicateKeyException e) {
            throw new JeecgBootException("仓库编码已存在");
        }
    }

    private WmsWarehouses requireWarehouse(String id) {
        WmsWarehouses warehouse = getById(FreshValidation.text(id, "仓库ID", 36));
        if (warehouse == null) {
            throw new JeecgBootException("仓库不存在");
        }
        return warehouse;
    }
}
