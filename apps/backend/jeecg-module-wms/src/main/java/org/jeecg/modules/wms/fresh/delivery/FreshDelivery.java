package org.jeecg.modules.wms.fresh.delivery;

import com.fasterxml.jackson.annotation.JsonFormat;
import lombok.Data;

import java.util.Date;
import java.util.List;

@Data
public class FreshDelivery {
    private String id;
    private String outboundId;
    private String outboundNumber;
    private String storeId;
    private String storeName;
    private String storeAddress;
    private String status;
    private String driverName;
    private String driverPhone;
    private String remark;
    private String createdBy;
    @JsonFormat(timezone = "GMT+8", pattern = "yyyy-MM-dd HH:mm:ss")
    private Date createdAt;
    private String dispatchBy;
    @JsonFormat(timezone = "GMT+8", pattern = "yyyy-MM-dd HH:mm:ss")
    private Date dispatchAt;
    private String deliveredBy;
    @JsonFormat(timezone = "GMT+8", pattern = "yyyy-MM-dd HH:mm:ss")
    private Date deliveredAt;
    private List<FreshDeliveryItem> items;
}
