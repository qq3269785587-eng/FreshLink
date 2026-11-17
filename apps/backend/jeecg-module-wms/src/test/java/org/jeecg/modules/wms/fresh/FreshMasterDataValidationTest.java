package org.jeecg.modules.wms.fresh;

import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.fresh.constant.FreshConstants;
import org.jeecg.modules.wms.fresh.support.FreshValidation;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

/** Pure P1 master-data validation rules (the real-DB/API cases are executed against MySQL). */
class FreshMasterDataValidationTest {

    @Test
    void rejectsMissingOrMalformedCodes() {
        assertThrows(JeecgBootException.class, () -> FreshValidation.code(null, "编码"));
        assertThrows(JeecgBootException.class, () -> FreshValidation.code("  ", "编码"));
        assertThrows(JeecgBootException.class, () -> FreshValidation.code("A B", "编码"));
        assertEquals("S1", FreshValidation.code(" S1 ", "编码"));
    }

    @Test
    void statusDefaultsToActiveAndRejectsUnknownValues() {
        assertEquals(FreshConstants.STATUS_ACTIVE, FreshValidation.status(null));
        assertEquals(FreshConstants.STATUS_INACTIVE, FreshValidation.status("inactive"));
        assertThrows(JeecgBootException.class, () -> FreshValidation.status("DELETED"));
    }

    @Test
    void temperatureZoneMustBeOneOfTheThreeControlledValues() {
        assertEquals(FreshConstants.STORAGE_CHILLED, FreshValidation.storageType("chilled", true));
        assertThrows(JeecgBootException.class, () -> FreshValidation.storageType(null, true));
        assertThrows(JeecgBootException.class, () -> FreshValidation.storageType("HOT", true));
    }

    @Test
    void nearExpiryThresholdRejectsNullAndNegativeValues() {
        assertEquals(0, FreshValidation.nearExpiryDays(0));
        assertEquals(3, FreshValidation.nearExpiryDays(3));
        assertThrows(JeecgBootException.class, () -> FreshValidation.nearExpiryDays(null));
        assertThrows(JeecgBootException.class, () -> FreshValidation.nearExpiryDays(-1));
        assertThrows(JeecgBootException.class, () -> FreshValidation.nearExpiryDays(36501));
    }

    @Test
    void shelfLifeMustBePositive() {
        assertEquals(7, FreshValidation.positiveDays(7, "保质期天数"));
        assertThrows(JeecgBootException.class, () -> FreshValidation.positiveDays(0, "保质期天数"));
        assertThrows(JeecgBootException.class, () -> FreshValidation.positiveDays(null, "保质期天数"));
    }
}
