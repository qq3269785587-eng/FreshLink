package org.jeecg.modules.wms.fresh;

import com.baomidou.mybatisplus.core.MybatisConfiguration;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.metadata.TableInfoHelper;
import org.apache.ibatis.builder.MapperBuilderAssistant;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.config.WarehouseDictEnum;
import org.jeecg.modules.wms.warehouse.entity.WmsStorageZones;
import org.jeecg.modules.wms.warehouse.entity.WmsWarehouses;
import org.jeecg.modules.wms.warehouse.service.IWmsStorageLocationsService;
import org.jeecg.modules.wms.warehouse.service.IWmsWarehousesService;
import org.jeecg.modules.wms.warehouse.service.impl.WmsStorageZonesServiceImpl;
import org.jeecg.modules.wms.wmstask.entity.WmsTasks;
import org.jeecg.modules.wms.wmstask.entity.WmsTasksRecords;
import org.jeecg.modules.wms.wmstask.service.impl.WmsTasksServiceImpl;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class FreshD1WarehouseTest {

    @Test
    void zoneCodeMustBeUniqueExceptForTheCurrentRecord() {
        TableInfoHelper.initTableInfo(new MapperBuilderAssistant(new MybatisConfiguration(), "d1-zones"), WmsStorageZones.class);
        WmsStorageZonesServiceImpl service = spy(new WmsStorageZonesServiceImpl());
        IWmsWarehousesService warehouses = mock(IWmsWarehousesService.class);
        ReflectionTestUtils.setField(service, "warehouses", warehouses);
        when(warehouses.getById("W1")).thenReturn(new WmsWarehouses());
        doReturn(zone("Z1", "CHILL")).when(service).getById("Z1");
        doReturn(true).when(service).updateById(any(WmsStorageZones.class));
        Map<String, String> existingCodes = Map.of("CHILL", "Z1", "FROZEN", "Z2");

        doAnswer(call -> {
            LambdaQueryWrapper<?> wrapper = call.getArgument(0);
            wrapper.getSqlSegment();
            var values = wrapper.getParamNameValuePairs().values();
            return existingCodes.entrySet().stream()
                    .filter(entry -> values.contains(entry.getKey()) && !values.contains(entry.getValue()))
                    .count();
        }).when(service).count(any());

        assertThrows(JeecgBootException.class, () -> service.createMaster(zone(null, "CHILL")));
        assertThrows(JeecgBootException.class, () -> service.updateMaster(zone("Z1", "FROZEN")));
        assertDoesNotThrow(() -> service.updateMaster(zone("Z1", "CHILL")));
        verify(service, never()).save(any(WmsStorageZones.class));
        verify(service, times(1)).updateById(any(WmsStorageZones.class));
    }

    @Test
    void putawayUsesTheTasksWarehouseAndStopsBeforeAnyWriteIfTargetIsDisabled() {
        WmsTasksServiceImpl service = spy(new WmsTasksServiceImpl());
        WmsTasks task = new WmsTasks();
        task.setTaskType(WarehouseDictEnum.TASK_TYPE_PUTAWAY.getCode());
        task.setTargetWarehouseId("W1");
        doReturn(task).when(service).getById("T1");
        IWmsStorageLocationsService locations = mock(IWmsStorageLocationsService.class);
        ReflectionTestUtils.setField(service, "storageLocations", locations);
        for (String inactiveTarget : List.of("目标仓库", "目标库区", "目标储位")) {
            doThrow(new JeecgBootException(inactiveTarget + "未启用"))
                    .when(locations).requireActivePutawayTarget("W1", "L1");
            WmsTasksRecords execution = new WmsTasksRecords();
            execution.setTaskId("T1");
            execution.setTargetWarehouseId("W2");
            execution.setTargetLocationCode("L1");

            assertEquals(inactiveTarget + "未启用", assertThrows(JeecgBootException.class, () -> service.putaway(execution)).getMessage());
        }
        verify(service, never()).execute(any(WmsTasksRecords.class));
    }

    private WmsStorageZones zone(String id, String code) {
        WmsStorageZones zone = new WmsStorageZones();
        zone.setId(id);
        zone.setZoneCode(code);
        zone.setZoneName("测试库区");
        zone.setZoneType("STORAGE_AREA");
        zone.setStorageType("CHILLED");
        zone.setIsSellable("1");
        zone.setWarehouseId("W1");
        zone.setStatus("ACTIVE");
        return zone;
    }
}
