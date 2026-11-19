package org.jeecg.modules.wms.fresh;

import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.inventory.service.IWmsInventoryService;
import org.jeecg.modules.wms.inventory.service.impl.WmsInventoryTransByDeliver;
import org.jeecg.modules.wms.inventory.vo.WmsInventoryTransParam;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;

class FreshD3LegacyInventoryGuardTest {

    @Test
    void legacyDeliveryRejectsFreshBatchBeforeLoadingInventory() {
        WmsInventoryTransByDeliver service = new WmsInventoryTransByDeliver();
        IWmsInventoryService inventoryService = mock(IWmsInventoryService.class);
        ReflectionTestUtils.setField(service, "wmsInventoryService", inventoryService);
        WmsInventoryTransParam request = new WmsInventoryTransParam();
        request.setBatchNumber("FL:inbound-item-1");

        assertThrows(JeecgBootException.class, () -> service.transfer(request));
        verifyNoInteractions(inventoryService);
    }
}
