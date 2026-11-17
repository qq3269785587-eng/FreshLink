package org.jeecg.modules.wms.fresh.access;

import org.apache.shiro.SecurityUtils;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.common.system.vo.LoginUser;
import org.jeecg.modules.wms.fresh.constant.FreshConstants;
import org.jeecg.modules.wms.fresh.entity.FreshStore;
import org.jeecg.modules.wms.fresh.mapper.FreshStoreMapper;
import org.jeecg.modules.wms.fresh.mapper.FreshUserStoreMapper;
import org.springframework.stereotype.Service;

import jakarta.annotation.Resource;
import java.util.Collections;
import java.util.List;

/**
 * Resolves the logged-in user's FreshLink role and store binding.
 * Role codes are read from the database on each request so a stale menu cache cannot grant access.
 */
@Service
public class FreshAccessService {

    @Resource
    private FreshUserStoreMapper freshUserStoreMapper;

    @Resource
    private FreshStoreMapper freshStoreMapper;

    public LoginUser currentUser() {
        Object principal = SecurityUtils.getSubject().getPrincipal();
        return principal instanceof LoginUser ? (LoginUser) principal : null;
    }

    public LoginUser requireUser() {
        LoginUser user = currentUser();
        if (user == null) {
            throw new JeecgBootException("登录状态已失效，请重新登录");
        }
        return user;
    }

    public String currentUserId() {
        return requireUser().getId();
    }

    public List<String> roleCodes(String userId) {
        if (userId == null) {
            return Collections.emptyList();
        }
        List<String> roles = freshUserStoreMapper.selectRoleCodes(userId);
        return roles == null ? Collections.emptyList() : roles;
    }

    public boolean hasRole(String roleCode) {
        LoginUser user = currentUser();
        return user != null && roleCodes(user.getId()).contains(roleCode);
    }

    public boolean hasAnyRole(String... roleCodes) {
        LoginUser user = currentUser();
        if (user == null) {
            return false;
        }
        List<String> roles = roleCodes(user.getId());
        for (String roleCode : roleCodes) {
            if (roles.contains(roleCode)) {
                return true;
            }
        }
        return false;
    }

    /** Framework admin or the purpose-built FreshLink HQ role. */
    public boolean isHq() {
        LoginUser user = currentUser();
        if (user == null) {
            return false;
        }
        return "admin".equalsIgnoreCase(user.getUsername()) || hasAnyRole(FreshConstants.ROLE_HQ, "admin");
    }

    public boolean isWarehouse() {
        return hasRole(FreshConstants.ROLE_WAREHOUSE);
    }

    /**
     * A store user must have the store role and no HQ/warehouse role. A binding is not authorization.
     * Staff roles win so a misconfigured extra binding cannot lock staff out of warehouse work.
     */
    public boolean isStoreUser() {
        LoginUser user = currentUser();
        if (user == null || isHq() || isWarehouse()) {
            return false;
        }
        return hasRole(FreshConstants.ROLE_STORE);
    }

    public FreshStore boundStore() {
        LoginUser user = requireUser();
        return freshStoreMapper.selectBoundStore(user.getId());
    }

    public FreshStore requireBoundStore() {
        if (!isStoreUser()) {
            throw new JeecgBootException("当前账号无门店业务权限");
        }
        FreshStore store = boundStore();
        if (store == null || !FreshConstants.STATUS_ACTIVE.equals(store.getStatus())) {
            throw new JeecgBootException("当前账号未绑定有效启用门店，请联系总部管理员");
        }
        return store;
    }

    public void requireHq() {
        if (!isHq()) {
            throw new JeecgBootException("仅总部管理员可执行该操作");
        }
    }

    public void requireStaff() {
        if (!isHq() && !isWarehouse()) {
            throw new JeecgBootException("仅总部或仓管可执行该操作");
        }
    }
}
