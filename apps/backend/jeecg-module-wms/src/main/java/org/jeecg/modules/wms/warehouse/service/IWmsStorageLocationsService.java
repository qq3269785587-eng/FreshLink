package org.jeecg.modules.wms.warehouse.service;

import org.jeecg.modules.wms.warehouse.entity.WmsStorageLocations;
import com.baomidou.mybatisplus.extension.service.IService;

/**
 * @Description: 库位表
 * @Author: jeecg-boot
 * @Date:   2025-04-10
 * @Version: V1.0
 */
public interface IWmsStorageLocationsService extends IService<WmsStorageLocations> {

    void createMaster(WmsStorageLocations record);

    void updateMaster(WmsStorageLocations record);

    void deleteMaster(String id);

    void setEnabled(String id, boolean enabled);

    String requireActivePutawayTarget(String warehouseId, String locationCode);
}
