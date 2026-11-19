package org.jeecg.modules.wms.inventory.service;

import org.jeecg.modules.wms.inventory.entity.WmsInventory;

/** Inventory operations for D3 manual batch selection and outbound confirmation. */
public interface FreshOutboundInventory {

    /** Returns the latest eligible inventory snapshot without reserving or changing stock. */
    WmsInventory requireEligible(String inventoryId, String stockBatchKey);

    /** Deducts a confirmed quantity and writes its inventory ledger within the caller's transaction. */
    WmsInventory deduct(String inventoryId, String stockBatchKey, int quantity,
                        String outboundNumber, String operator);
}
