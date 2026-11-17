package org.jeecg.modules.wms.fresh.support;

import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.fresh.constant.FreshConstants;

import java.util.regex.Pattern;

/**
 * Server-side validation shared by HTTP controllers, imports and tests.
 * Messages are explicit so the page can show the real business reason.
 */
public final class FreshValidation {
    private static final Pattern CODE = Pattern.compile("^[A-Za-z0-9_.-]{2,64}$");

    private FreshValidation() {
    }

    public static String text(String value, String field, int maxLength) {
        if (value == null || value.trim().isEmpty()) {
            throw new JeecgBootException(field + "不能为空");
        }
        String trimmed = value.trim();
        if (trimmed.length() > maxLength) {
            throw new JeecgBootException(field + "长度不能超过" + maxLength);
        }
        return trimmed;
    }

    public static String code(String value, String field) {
        String trimmed = text(value, field, 64);
        if (!CODE.matcher(trimmed).matches()) {
            throw new JeecgBootException(field + "只能包含字母、数字、下划线、点和短横线，长度2-64");
        }
        return trimmed;
    }

    public static String optionalText(String value, String field, int maxLength) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        if (trimmed.length() > maxLength) {
            throw new JeecgBootException(field + "长度不能超过" + maxLength);
        }
        return trimmed.isEmpty() ? null : trimmed;
    }

    public static String status(String value) {
        if (value == null || value.trim().isEmpty()) {
            return FreshConstants.STATUS_ACTIVE;
        }
        String normalized = value.trim().toUpperCase();
        if (!FreshConstants.STATUSES.contains(normalized)) {
            throw new JeecgBootException("状态只能是ACTIVE或INACTIVE");
        }
        return normalized;
    }

    public static String storageType(String value, boolean required) {
        if (value == null || value.trim().isEmpty()) {
            if (required) {
                throw new JeecgBootException("温区不能为空");
            }
            return null;
        }
        String normalized = value.trim().toUpperCase();
        if (!FreshConstants.STORAGE_TYPES.contains(normalized)) {
            throw new JeecgBootException("温区只能是NORMAL、CHILLED或FROZEN");
        }
        return normalized;
    }

    public static Integer nearExpiryDays(Integer value) {
        if (value == null) {
            throw new JeecgBootException("临期阈值天数不能为空");
        }
        if (value < 0) {
            throw new JeecgBootException("临期阈值天数不能为负数");
        }
        if (value > 36500) {
            throw new JeecgBootException("临期阈值天数超出合理范围");
        }
        return value;
    }

    public static Integer positiveDays(Integer value, String field) {
        if (value == null || value <= 0) {
            throw new JeecgBootException(field + "必须为正整数");
        }
        if (value > 36500) {
            throw new JeecgBootException(field + "超出合理范围");
        }
        return value;
    }
}
