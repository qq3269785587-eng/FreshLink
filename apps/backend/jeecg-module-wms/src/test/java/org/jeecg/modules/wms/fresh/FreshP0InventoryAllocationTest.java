package org.jeecg.modules.wms.fresh;

import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import org.jeecg.modules.wms.goods.entity.WmsProducts;
import org.jeecg.modules.wms.goods.service.IWmsProductsService;
import org.jeecg.modules.wms.inventory.entity.WmsInventory;
import org.jeecg.modules.wms.inventory.service.IWmsInventoryService;
import org.jeecg.modules.wms.inventory.service.impl.WmsInventoryTransByAllocation;
import org.jeecg.modules.wms.inventory.vo.WmsInventoryTransParam;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/** Exercises the existing allocation service's batch selection and guarded quantity update. */
class FreshP0InventoryAllocationTest {
    private final IWmsInventoryService inventoryService = mock(IWmsInventoryService.class);
    private final IWmsProductsService productsService = mock(IWmsProductsService.class);
    private final WmsInventoryTransByAllocation allocation = new WmsInventoryTransByAllocation();

    @BeforeEach
    void setUp() {
        ReflectionTestUtils.setField(allocation, "wmsInventoryService", inventoryService);
        ReflectionTestUtils.setField(allocation, "wmsProductsService", productsService);
    }

    @Test
    void allocationReservesOnlyRequestedBatchAndGuardsAvailableBalance() {
        WmsProducts product = new WmsProducts();
        product.setId("SKU-X");
        when(productsService.getById("SKU-X")).thenReturn(product);
        WmsInventory stock = new WmsInventory();
        stock.setId("INV-B1-C1");
        when(inventoryService.getInventoryByUniqueKey("SKU-X", "C1", "B1")).thenReturn(stock);
        when(inventoryService.update(isNull(), any())).thenReturn(true);

        WmsInventoryTransParam request = new WmsInventoryTransParam();
        request.setProductId("SKU-X");
        request.setSourceLocationCode("C1");
        request.setBatchNumber("B1");
        request.setExecQuantity(4);

        allocation.transfer(request);

        verify(inventoryService).getInventoryByUniqueKey("SKU-X", "C1", "B1");
        @SuppressWarnings({"rawtypes", "unchecked"})
        ArgumentCaptor<LambdaUpdateWrapper<WmsInventory>> updateCaptor = ArgumentCaptor.forClass((Class) LambdaUpdateWrapper.class);
        verify(inventoryService).update(isNull(), updateCaptor.capture());
        LambdaUpdateWrapper<WmsInventory> update = updateCaptor.getValue();
        String assignments = update.getSqlSet();
        String conditions = update.getExpression().getNormal().toString();
        Map<String, Object> values = update.getParamNameValuePairs();
        assertTrue(assignments != null && assignments.contains("available_quantity=available_quantity-"), assignments);
        assertTrue(assignments.contains("allocated_quantity=allocated_quantity+"), assignments);
        assertTrue(conditions.contains("GE"), conditions);
        assertTrue(conditions.contains("AND"), conditions);
        assertTrue(values.containsValue(4), values.toString());
    }

    @Test
    void failedConditionalBalanceUpdateRejectsAllocation() {
        WmsProducts product = new WmsProducts();
        when(productsService.getById("SKU-X")).thenReturn(product);
        WmsInventory stock = new WmsInventory();
        stock.setId("INV-B1-C1");
        when(inventoryService.getInventoryByUniqueKey("SKU-X", "C1", "B1")).thenReturn(stock);
        when(inventoryService.update(isNull(), any())).thenReturn(false);

        WmsInventoryTransParam request = new WmsInventoryTransParam();
        request.setProductId("SKU-X");
        request.setSourceLocationCode("C1");
        request.setBatchNumber("B1");
        request.setExecQuantity(4);

        assertThrows(RuntimeException.class, () -> allocation.transfer(request));
        verify(inventoryService).getInventoryByUniqueKey("SKU-X", "C1", "B1");
        verify(inventoryService).update(isNull(), any());
    }
}
