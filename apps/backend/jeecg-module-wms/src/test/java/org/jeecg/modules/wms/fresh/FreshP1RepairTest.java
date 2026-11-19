package org.jeecg.modules.wms.fresh;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.goods.entity.WmsProducts;
import org.jeecg.modules.wms.goods.service.IWmsProductsService;
import org.jeecg.modules.wms.inorder.entity.WmsStockInOrderItems;
import org.jeecg.modules.wms.inorder.entity.WmsStockInOrders;
import org.jeecg.modules.wms.inorder.mapper.WmsStockInOrdersMapper;
import org.jeecg.modules.wms.inorder.service.impl.WmsStockInOrdersServiceImpl;
import org.jeecg.modules.wms.fresh.access.FreshAccessService;
import org.jeecg.modules.wms.fresh.entity.FreshSupplier;
import org.jeecg.modules.wms.fresh.service.IFreshSupplierService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class FreshP1RepairTest {
    @Test void accountWithoutBusinessRoleIsNeverAuthorizedByBinding() {
        org.jeecg.modules.wms.fresh.access.FreshAccessService access = new org.jeecg.modules.wms.fresh.access.FreshAccessService() {
            @Override public org.jeecg.common.system.vo.LoginUser currentUser() {
                org.jeecg.common.system.vo.LoginUser user = new org.jeecg.common.system.vo.LoginUser();
                user.setId("ordinary"); user.setUsername("ordinary"); return user;
            }
            @Override public java.util.List<String> roleCodes(String id) { return java.util.List.of(); }
        };
        assertFalse(access.isStoreUser());
        assertThrows(JeecgBootException.class, access::requireStaff);
        assertThrows(JeecgBootException.class, access::requireBoundStore);
    }

    @Test void thresholdDeserializerRejectsCoercionAndOverflow() {
        ObjectMapper mapper = new ObjectMapper();
        for (String value : List.of("1.5", "1.0", "2147483648", "\"1.5\"", "true", "{}")) {
            assertThrows(Exception.class, () -> mapper.readValue("{\"nearExpiryDays\":" + value + "}", WmsProducts.class));
        }
    }
    @Test void thresholdDeserializerRetainsZeroAndNullForServiceValidation() throws Exception {
        ObjectMapper mapper = new ObjectMapper();
        assertEquals(0, mapper.readValue("{\"nearExpiryDays\":0}", WmsProducts.class).getNearExpiryDays());
        assertNull(mapper.readValue("{\"nearExpiryDays\":null}", WmsProducts.class).getNearExpiryDays());
    }
    @Test void importRejectsDisabledProductBeforeWritingParentOrItems() {
        WmsStockInOrdersServiceImpl service = new WmsStockInOrdersServiceImpl();
        IWmsProductsService products = mock(IWmsProductsService.class);
        IFreshSupplierService suppliers = mock(IFreshSupplierService.class);
        FreshAccessService access = mock(FreshAccessService.class);
        WmsStockInOrdersMapper orders = mock(WmsStockInOrdersMapper.class);
        ReflectionTestUtils.setField(service, "productsService", products);
        ReflectionTestUtils.setField(service, "supplierService", suppliers);
        ReflectionTestUtils.setField(service, "freshAccessService", access);
        ReflectionTestUtils.setField(service, "wmsStockInOrdersMapper", orders);
        when(suppliers.getById("supplier")).thenReturn(new FreshSupplier().setStatus("ACTIVE"));
        when(products.getById("disabled")).thenReturn(new WmsProducts().setOwnerId("owner").setStatus("INACTIVE"));
        WmsStockInOrders order = new WmsStockInOrders(); order.setOwnerId("owner"); order.setSupplierId("supplier");
        WmsStockInOrderItems item = validItem("disabled");
        assertThrows(JeecgBootException.class, () -> service.saveMain(order, List.of(item)));
        verifyNoInteractions(orders);
    }
    @Test void importRejectsMissingProductBeforeWritingParent() {
        WmsStockInOrdersServiceImpl service = new WmsStockInOrdersServiceImpl();
        IWmsProductsService products = mock(IWmsProductsService.class);
        IFreshSupplierService suppliers = mock(IFreshSupplierService.class);
        FreshAccessService access = mock(FreshAccessService.class);
        WmsStockInOrdersMapper orders = mock(WmsStockInOrdersMapper.class);
        ReflectionTestUtils.setField(service, "productsService", products);
        ReflectionTestUtils.setField(service, "supplierService", suppliers);
        ReflectionTestUtils.setField(service, "freshAccessService", access);
        ReflectionTestUtils.setField(service, "wmsStockInOrdersMapper", orders);
        when(suppliers.getById("supplier")).thenReturn(new FreshSupplier().setStatus("ACTIVE"));
        WmsStockInOrders order = new WmsStockInOrders(); order.setOwnerId("owner"); order.setSupplierId("supplier");
        WmsStockInOrderItems item = validItem("missing");
        assertThrows(JeecgBootException.class, () -> service.saveMain(order, List.of(item)));
        verifyNoInteractions(orders);
    }

    private WmsStockInOrderItems validItem(String productId) {
        WmsStockInOrderItems item = new WmsStockInOrderItems();
        item.setProductId(productId);
        item.setExpectedQuantity(1);
        item.setBatchNumber("B1");
        item.setProductionDate(java.time.LocalDate.now().minusDays(1));
        item.setExpiryDate(java.time.LocalDate.now().plusDays(1));
        return item;
    }
}
