package org.jeecg.modules.wms.fresh;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.goods.entity.WmsProducts;
import org.jeecg.modules.wms.goods.service.IWmsProductsService;
import org.jeecg.modules.wms.inorder.entity.WmsStockInOrderItems;
import org.jeecg.modules.wms.inorder.entity.WmsStockInOrders;
import org.jeecg.modules.wms.inorder.mapper.WmsStockInOrdersMapper;
import org.jeecg.modules.wms.inorder.service.impl.WmsStockInOrdersServiceImpl;
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
        WmsStockInOrdersMapper orders = mock(WmsStockInOrdersMapper.class);
        ReflectionTestUtils.setField(service, "productsService", products);
        ReflectionTestUtils.setField(service, "wmsStockInOrdersMapper", orders);
        when(products.getById("disabled")).thenReturn(new WmsProducts().setOwnerId("owner").setStatus("INACTIVE"));
        WmsStockInOrders order = new WmsStockInOrders(); order.setOwnerId("owner");
        WmsStockInOrderItems item = new WmsStockInOrderItems(); item.setProductId("disabled"); item.setExpectedQuantity(1);
        assertThrows(JeecgBootException.class, () -> service.saveMain(order, List.of(item)));
        verifyNoInteractions(orders);
    }
    @Test void importRejectsMissingProductBeforeWritingParent() {
        WmsStockInOrdersServiceImpl service = new WmsStockInOrdersServiceImpl();
        IWmsProductsService products = mock(IWmsProductsService.class);
        WmsStockInOrdersMapper orders = mock(WmsStockInOrdersMapper.class);
        ReflectionTestUtils.setField(service, "productsService", products);
        ReflectionTestUtils.setField(service, "wmsStockInOrdersMapper", orders);
        WmsStockInOrders order = new WmsStockInOrders(); order.setOwnerId("owner");
        WmsStockInOrderItems item = new WmsStockInOrderItems(); item.setProductId("missing"); item.setExpectedQuantity(1);
        assertThrows(JeecgBootException.class, () -> service.saveMain(order, List.of(item)));
        verifyNoInteractions(orders);
    }
}
