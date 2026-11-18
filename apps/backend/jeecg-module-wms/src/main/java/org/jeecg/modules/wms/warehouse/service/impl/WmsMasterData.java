package org.jeecg.modules.wms.warehouse.service.impl;

import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.config.WarehouseDictEnum;

final class WmsMasterData {
    static final String CREATED = WarehouseDictEnum.STATUS_CREATED.getCode();
    static final String ACTIVE = WarehouseDictEnum.STATUS_ACTIVE.getCode();
    static final String INACTIVE = WarehouseDictEnum.STATUS_INACTIVE.getCode();

    private WmsMasterData() {
    }

    static String status(String value) {
        if (value == null || value.isBlank()) {
            return CREATED;
        }
        String status = value.trim();
        if (!CREATED.equals(status) && !ACTIVE.equals(status) && !INACTIVE.equals(status)) {
            throw new JeecgBootException("状态只能是CREATED、ACTIVE或INACTIVE");
        }
        return status;
    }

    static String sellable(String value) {
        if (!"0".equals(value) && !"1".equals(value)) {
            throw new JeecgBootException("请选择是否可售");
        }
        return value;
    }
}
