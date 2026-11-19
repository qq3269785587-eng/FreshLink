package org.jeecg.modules.wms.fresh;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.fresh.entity.FreshSupplier;
import org.jeecg.modules.wms.fresh.service.IFreshSupplierService;
import org.jeecg.modules.wms.fresh.support.FreshReferenceGuard;
import org.jeecg.modules.wms.goods.entity.WmsProducts;
import org.jeecg.modules.wms.goods.service.IWmsProductsService;
import org.jeecg.modules.wms.inorder.entity.WmsStockInOrderItems;
import org.jeecg.modules.wms.inorder.entity.WmsStockInOrders;
import org.jeecg.modules.wms.inorder.service.impl.WmsStockInOrdersServiceImpl;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDate;
import java.time.ZoneId;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class FreshD2InboundOrderTest {

    @Test
    void receivingRequiresActiveSupplierProductAndAValidDatedBatch() {
        WmsStockInOrdersServiceImpl service = new WmsStockInOrdersServiceImpl();
        IFreshSupplierService suppliers = mock(IFreshSupplierService.class);
        IWmsProductsService products = mock(IWmsProductsService.class);
        ReflectionTestUtils.setField(service, "supplierService", suppliers);
        ReflectionTestUtils.setField(service, "productsService", products);

        FreshSupplier supplier = new FreshSupplier();
        supplier.setStatus("ACTIVE");
        when(suppliers.getById("SUP-1")).thenReturn(supplier);
        WmsProducts product = new WmsProducts();
        product.setStatus("ACTIVE");
        when(products.getById("SKU-1")).thenReturn(product);

        WmsStockInOrders order = new WmsStockInOrders();
        order.setSupplierId("SUP-1");
        LocalDate today = LocalDate.now(ZoneId.of("Asia/Shanghai"));
        WmsStockInOrderItems item = item(today.minusDays(2), today.plusDays(2));
        assertDoesNotThrow(() -> service.requireReceivable(order, item));

        item.setBatchNumber(" ");
        assertThrows(JeecgBootException.class, () -> service.requireReceivable(order, item));
        item.setBatchNumber("B1");
        item.setExpiryDate(today);
        assertThrows(JeecgBootException.class, () -> service.requireReceivable(order, item));

        supplier.setStatus("INACTIVE");
        item.setExpiryDate(today.plusDays(2));
        assertThrows(JeecgBootException.class, () -> service.requireReceivable(order, item));
    }

    @Test
    void plannedQuantityRejectsFractionalJson() {
        ObjectMapper mapper = new ObjectMapper();
        assertThrows(JsonProcessingException.class, () -> mapper.readValue(
                "{\"expectedQuantity\":1.5}", WmsStockInOrderItems.class));
    }

    @Test
    void impossibleCalendarDatesAreRejected() {
        ObjectMapper mapper = new ObjectMapper().registerModule(new JavaTimeModule());
        assertDoesNotThrow(() -> mapper.readValue(
                "{\"productionDate\":\"2024-02-29\"}", WmsStockInOrderItems.class));
        assertThrows(JsonProcessingException.class, () -> mapper.readValue(
                "{\"productionDate\":\"2026-02-30\"}", WmsStockInOrderItems.class));
    }

    @Test
    void supplierDeletionIsBlockedByAnInboundOrderReference() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        when(jdbc.queryForObject(anyString(), eq(Integer.class), any(Object[].class))).thenReturn(1);
        when(jdbc.queryForObject(anyString(), eq(Long.class), any(Object[].class)))
                .thenAnswer(invocation -> invocation.getArgument(0, String.class).contains("wms_stock_in_orders") ? 1L : 0L);
        FreshReferenceGuard guard = new FreshReferenceGuard();
        ReflectionTestUtils.setField(guard, "jdbcTemplate", jdbc);

        assertThrows(JeecgBootException.class, () -> guard.assertSupplierDeletable("SUP-1"));
    }

    private WmsStockInOrderItems item(LocalDate productionDate, LocalDate expiryDate) {
        WmsStockInOrderItems item = new WmsStockInOrderItems();
        item.setProductId("SKU-1");
        item.setBatchNumber("B1");
        item.setProductionDate(productionDate);
        item.setExpiryDate(expiryDate);
        return item;
    }
}
