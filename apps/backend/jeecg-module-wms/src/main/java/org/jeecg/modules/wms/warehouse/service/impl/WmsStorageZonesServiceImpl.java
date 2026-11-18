package org.jeecg.modules.wms.warehouse.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.PageDTO;
import com.github.pagehelper.Page;
import com.github.pagehelper.PageHelper;
import org.jeecg.modules.wms.warehouse.entity.WmsStorageZones;
import org.jeecg.modules.wms.warehouse.mapper.WmsStorageZonesMapper;
import org.jeecg.modules.wms.warehouse.service.IWmsStorageZonesService;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.fresh.support.FreshReferenceGuard;
import org.jeecg.modules.wms.fresh.support.FreshValidation;
import org.jeecg.modules.wms.warehouse.service.IWmsWarehousesService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;

import java.util.List;

/**
 * @Description: 库区表
 * @Author: jeecg-boot
 * @Date:   2025-04-09
 * @Version: V1.0
 */
@Service
public class WmsStorageZonesServiceImpl extends ServiceImpl<WmsStorageZonesMapper, WmsStorageZones> implements IWmsStorageZonesService {

    @Autowired
    private IWmsWarehousesService warehouses;
    @Autowired
    private FreshReferenceGuard references;

    @Override
    public void createMaster(WmsStorageZones zone) {
        zone.setId(null);
        saveMaster(zone, false);
    }

    @Override
    public void updateMaster(WmsStorageZones zone) {
        WmsStorageZones existing = requireZone(zone.getId());
        if (zone.getStatus() == null) {
            zone.setStatus(existing.getStatus());
        }
        if (!existing.getWarehouseId().equals(zone.getWarehouseId())) {
            references.assertZoneUnreferenced(existing.getId());
        }
        saveMaster(zone, true);
    }

    private void saveMaster(WmsStorageZones zone, boolean update) {
        zone.setZoneCode(FreshValidation.text(zone.getZoneCode(), "库区编码", 50));
        zone.setZoneName(FreshValidation.text(zone.getZoneName(), "库区名称", 100));
        zone.setZoneType(FreshValidation.text(zone.getZoneType(), "库区类型", 50));
        zone.setStorageType(FreshValidation.storageType(zone.getStorageType(), true));
        zone.setStatus(WmsMasterData.status(zone.getStatus()));
        zone.setIsSellable(WmsMasterData.sellable(zone.getIsSellable()));
        zone.setWarehouseId(FreshValidation.text(zone.getWarehouseId(), "所属仓库", 32));
        if (warehouses.getById(zone.getWarehouseId()) == null) {
            throw new JeecgBootException("所属仓库不存在");
        }
        var duplicate = new LambdaQueryWrapper<WmsStorageZones>()
                .eq(WmsStorageZones::getZoneCode, zone.getZoneCode())
                .ne(update, WmsStorageZones::getId, zone.getId());
        if (count(duplicate) > 0) {
            throw new JeecgBootException("库区编码已存在");
        }
        try {
            if (!(update ? updateById(zone) : save(zone))) {
                throw new JeecgBootException("保存库区失败");
            }
        } catch (DuplicateKeyException e) {
            throw new JeecgBootException("库区编码已存在");
        }
    }

    @Override
    public void disable(String id) {
        String zoneId = FreshValidation.text(id, "库区ID", 36);
        boolean changed = lambdaUpdate().eq(WmsStorageZones::getId, zoneId)
                .eq(WmsStorageZones::getStatus, WmsMasterData.ACTIVE)
                .set(WmsStorageZones::getStatus, WmsMasterData.INACTIVE)
                .update();
        if (!changed) {
            throw new JeecgBootException("只能禁用已启用的库区");
        }
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void deleteMaster(String id) {
        WmsStorageZones zone = requireZone(id);
        references.assertZoneUnreferenced(zone.getId());
        if (!removeById(zone.getId())) {
            throw new JeecgBootException("删除库区失败");
        }
    }

    private WmsStorageZones requireZone(String id) {
        WmsStorageZones zone = getById(FreshValidation.text(id, "库区ID", 36));
        if (zone == null) {
            throw new JeecgBootException("库区不存在");
        }
        return zone;
    }

    @Override
    public IPage<WmsStorageZones> queryList(WmsStorageZones wmsStorageZones, Integer pageNo, Integer pageSize) {
        //开启分页查询,当执行查询时，插件进行相关的sql拦截进行分页操作，返回一个page对象
        Page<WmsStorageZones> page = PageHelper.startPage(pageNo, pageSize);
        List<WmsStorageZones> list = baseMapper.queryList(wmsStorageZones);
        PageDTO<WmsStorageZones> wmsStorageZonesPageDTO = new PageDTO<>();
        wmsStorageZonesPageDTO.setRecords(list);
        wmsStorageZonesPageDTO.setTotal(page.getTotal());
        wmsStorageZonesPageDTO.setSize(page.getPageSize());
        wmsStorageZonesPageDTO.setCurrent(page.getPageNum());
        wmsStorageZonesPageDTO.setPages(page.getPages());
        return wmsStorageZonesPageDTO;
    }
}
