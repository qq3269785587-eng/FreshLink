package org.jeecg.modules.wms.fresh.delivery;

import lombok.Data;

import java.time.LocalDate;

@Data
public class FreshDeliveryItem {
    private String id;
    private String inventoryId;
    private String stockBatchKey;
    private String productId;
    private String productName;
    private String productSpec;
    private String unit;
    private String supplierId;
    private String supplierName;
    private String batchNumber;
    private String locationCode;
    private LocalDate expiryDate;
    private Integer quantity;
}
