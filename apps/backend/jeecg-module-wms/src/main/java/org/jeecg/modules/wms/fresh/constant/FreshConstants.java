package org.jeecg.modules.wms.fresh.constant;

import java.util.Set;

/** FreshLink P1 role codes, master-data statuses and temperature zones. */
public final class FreshConstants {
    public static final String ROLE_HQ = "fresh_hq";
    public static final String ROLE_WAREHOUSE = "fresh_warehouse";
    public static final String ROLE_STORE = "fresh_store";

    public static final String STATUS_ACTIVE = "ACTIVE";
    public static final String STATUS_INACTIVE = "INACTIVE";

    public static final String STORAGE_NORMAL = "NORMAL";
    public static final String STORAGE_CHILLED = "CHILLED";
    public static final String STORAGE_FROZEN = "FROZEN";

    public static final Set<String> STORAGE_TYPES = Set.of(STORAGE_NORMAL, STORAGE_CHILLED, STORAGE_FROZEN);
    public static final Set<String> STATUSES = Set.of(STATUS_ACTIVE, STATUS_INACTIVE);

    private FreshConstants() {
    }
}
