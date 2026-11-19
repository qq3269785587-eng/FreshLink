package org.jeecg.modules.wms.inorder.vo;

import com.fasterxml.jackson.databind.annotation.JsonDeserialize;
import org.jeecg.modules.wms.fresh.support.StrictIntegerDeserializer;
import org.jeecg.modules.wms.wmstask.entity.WmsTasksRecords;

public record FreshInboundAction(
        String id,
        @JsonDeserialize(using = StrictIntegerDeserializer.class) Integer execQuantity,
        String targetLocationCode,
        String requestKey) {

    public WmsTasksRecords toRecord() {
        WmsTasksRecords record = new WmsTasksRecords();
        record.setTaskId(id);
        record.setExecQuantity(execQuantity);
        record.setTargetLocationCode(targetLocationCode);
        record.setRequestKey(requestKey);
        return record;
    }
}
