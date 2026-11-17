package org.jeecg.modules.wms.fresh.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.common.util.oConvertUtils;
import org.jeecg.modules.wms.fresh.access.FreshAccessService;
import org.jeecg.modules.wms.fresh.constant.FreshConstants;
import org.jeecg.modules.wms.fresh.entity.FreshStore;
import org.jeecg.modules.wms.fresh.entity.FreshUserStore;
import org.jeecg.modules.wms.fresh.mapper.FreshStoreMapper;
import org.jeecg.modules.wms.fresh.mapper.FreshUserStoreMapper;
import org.jeecg.modules.wms.fresh.service.IFreshUserStoreService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import jakarta.annotation.Resource;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class FreshUserStoreServiceImpl extends ServiceImpl<FreshUserStoreMapper, FreshUserStore>
        implements IFreshUserStoreService {

    @Resource
    private FreshAccessService accessService;

    @Resource
    private FreshStoreMapper freshStoreMapper;

    @Override
    public IPage<Map<String, Object>> pageUsersWithStore(Page<?> page, String keyword) {
        accessService.requireHq();
        return baseMapper.pageUsersWithStore(page, keyword);
    }

    @Override
    public List<Map<String, Object>> storeRoleUsers() {
        accessService.requireHq();
        return baseMapper.selectStoreRoleUsers();
    }

    @Override
    public Map<String, Object> myBinding() {
        FreshStore store = accessService.requireBoundStore();
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("storeId", store.getId());
        result.put("storeCode", store.getStoreCode());
        result.put("storeName", store.getStoreName());
        result.put("address", store.getAddress());
        result.put("status", store.getStatus());
        return result;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void bind(String userId, String storeId) {
        // The binding is an HQ-only operation. A store account can never reach this method,
        // and it also cannot pass another user id because the endpoint requires HQ in the controller.
        accessService.requireHq();
        if (oConvertUtils.isEmpty(userId)) {
            throw new JeecgBootException("用户ID不能为空");
        }
        if (baseMapper.countActiveUser(userId) == 0) {
            throw new JeecgBootException("用户不存在、已冻结或已删除");
        }
        String username = baseMapper.selectUsername(userId);
        List<String> roles = baseMapper.selectRoleCodes(userId);
        if (roles.contains("admin") || roles.contains(FreshConstants.ROLE_HQ) || roles.contains(FreshConstants.ROLE_WAREHOUSE)) {
            throw new JeecgBootException("只能为门店角色用户绑定门店");
        }
        if (!roles.contains(FreshConstants.ROLE_STORE)) {
            throw new JeecgBootException("目标用户不是门店角色，请先分配门店角色");
        }
        FreshUserStore existing = getOne(new LambdaQueryWrapper<FreshUserStore>()
                .eq(FreshUserStore::getUserId, userId), false);
        if (oConvertUtils.isEmpty(storeId)) {
            if (existing != null) {
                removeById(existing.getId());
            }
            return;
        }
        FreshStore store = freshStoreMapper.selectById(storeId);
        if (store == null) {
            throw new JeecgBootException("门店不存在");
        }
        if (!FreshConstants.STATUS_ACTIVE.equals(store.getStatus())) {
            throw new JeecgBootException("门店已禁用，不能绑定用户");
        }
        String operator = accessService.requireUser().getUsername();
        if (existing == null) {
            FreshUserStore binding = new FreshUserStore();
            binding.setUserId(userId);
            binding.setStoreId(storeId);
            binding.setCreateBy(operator);
            binding.setCreateTime(new Date());
            save(binding);
        } else if (!storeId.equals(existing.getStoreId())) {
            existing.setStoreId(storeId);
            existing.setUpdateBy(operator);
            existing.setUpdateTime(new Date());
            updateById(existing);
        }
    }
}
