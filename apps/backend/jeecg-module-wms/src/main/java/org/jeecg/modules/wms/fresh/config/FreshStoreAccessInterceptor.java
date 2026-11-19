package org.jeecg.modules.wms.fresh.config;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.jeecg.modules.wms.fresh.access.FreshAccessService;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import jakarta.annotation.Resource;

/**
 * Central server-side guard for legacy WMS and system-administration endpoints.
 * Hiding a menu button is not access control: store accounts are rejected here even when they
 * call an old endpoint directly, and warehouse accounts cannot reach system user/role management.
 */
@Component
public class FreshStoreAccessInterceptor implements HandlerInterceptor {

    @Resource
    private FreshAccessService accessService;

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        String path = request.getServletPath();
        if (path == null || path.isEmpty()) {
            return true;
        }
        // Unauthenticated requests are handled by Shiro; do not turn them into 403 here.
        if (accessService.currentUser() == null) {
            return true;
        }
        if (accessService.isHq()) {
            return true;
        }
        if (accessService.isStoreUser()) {
            if (isStoreAllowed(path) || isDeliveryRead(request, path)) {
                return true;
            }
            reject(response, "门店账号无权访问该功能，仅可查看本店资料");
            return false;
        }
        if (accessService.isWarehouse()) {
            if (isSystemAdministration(path) && !isCommonRead(path)) {
                reject(response, "仓管账号无系统用户管理权限");
                return false;
            }
            return true;
        }
        // A missing business role never grants staff access.
        if (path.startsWith("/fresh/") || !isStoreAllowed(path)) {
            reject(response, "当前账号无生鲜业务权限");
            return false;
        }
        return true;
    }

    private boolean isDeliveryRead(HttpServletRequest request, String path) {
        return "GET".equals(request.getMethod())
                && (path.equals("/fresh/deliveries") || path.matches("/fresh/deliveries/[^/]+"));
    }

    private boolean isStoreAllowed(String path) {
        // Own store data only; all other fresh master data and every legacy WMS endpoint is denied.
        return path.equals("/fresh/stores/list")
                || path.equals("/fresh/stores/my")
                || path.equals("/fresh/stores/queryById")
                || path.equals("/fresh/userStores/my")
                || path.equals("/sys/user/getUserInfo")
                || path.equals("/sys/permission/getUserPermissionByToken")
                || path.startsWith("/sys/dict/getDictItems")
                || path.startsWith("/sys/dict/getDictText")
                || path.startsWith("/sys/common/")
                || path.startsWith("/sys/announcement/")
                || path.startsWith("/sys/annountCement/")
                || path.equals("/sys/visitInfo")
                || path.startsWith("/sys/loginfo")
                || path.startsWith("/sys/message/")
                || path.startsWith("/sys/login")
                || path.startsWith("/sys/logout")
                || path.startsWith("/sys/randomImage")
                || path.startsWith("/sys/phoneLogin")
                || path.startsWith("/sys/mLogin")
                || path.startsWith("/sys/thirdLogin")
                || path.startsWith("/sys/getEncryptedString")
                || path.startsWith("/jmreport/") // read-only report shell at most; no WMS data endpoint
                || path.equals("/error");
    }

    private boolean isSystemAdministration(String path) {
        return path.startsWith("/sys/user/")
                || path.startsWith("/sys/role/")
                || path.startsWith("/sys/permission/")
                || path.startsWith("/sys/tenant/")
                || path.startsWith("/sys/depart/")
                || path.startsWith("/sys/position/");
    }

    private boolean isCommonRead(String path) {
        return path.equals("/sys/user/getUserInfo")
                || path.equals("/sys/permission/getUserPermissionByToken");
    }

    private void reject(HttpServletResponse response, String message) throws Exception {
        response.setStatus(HttpServletResponse.SC_FORBIDDEN);
        response.setContentType("application/json;charset=UTF-8");
        response.getWriter().write("{\"success\":false,\"message\":\"" + message + "\",\"code\":403,\"result\":null}");
    }
}
