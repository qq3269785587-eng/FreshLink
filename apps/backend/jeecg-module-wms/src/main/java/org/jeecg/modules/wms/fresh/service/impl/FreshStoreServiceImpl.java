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
import org.jeecg.modules.wms.fresh.mapper.FreshStoreMapper;
import org.jeecg.modules.wms.fresh.service.IFreshStoreService;
import org.jeecg.modules.wms.fresh.support.FreshReferenceGuard;
import org.jeecg.modules.wms.fresh.support.FreshValidation;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import jakarta.annotation.Resource;
import java.util.Date;
import java.util.List;

@Service
public class FreshStoreServiceImpl extends ServiceImpl<FreshStoreMapper, FreshStore>
        implements IFreshStoreService {

    @Resource
    private FreshReferenceGuard referenceGuard;

    @Resource
    private FreshAccessService accessService;

    @Override
    public IPage<FreshStore> pageStores(Page<FreshStore> page, String keyword, String status) {
        if (accessService.isStoreUser()) {
            FreshStore bound = accessService.requireBoundStore();
            Page<FreshStore> result = new Page<>(page.getCurrent(), page.getSize());
            result.setRecords(List.of(bound));
            result.setTotal(1);
            return result;
        }
        accessService.requireStaff();
        LambdaQueryWrapper<FreshStore> query = new LambdaQueryWrapper<>();
        if (oConvertUtils.isNotEmpty(keyword)) {
            query.and(w -> w.like(FreshStore::getStoreCode, keyword)
                    .or().like(FreshStore::getStoreName, keyword));
        }
        if (oConvertUtils.isNotEmpty(status)) {
            query.eq(FreshStore::getStatus, status.trim().toUpperCase());
        }
        query.orderByAsc(FreshStore::getStoreCode);
        return page(page, query);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public FreshStore addStore(FreshStore store) {
        normalize(store);
        referenceGuard.assertStoreCodeUnique(store.getStoreCode(), null);
        store.setCreateBy(currentUsername());
        store.setCreateTime(new Date());
        save(store);
        return store;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public FreshStore editStore(FreshStore store) {
        if (oConvertUtils.isEmpty(store.getId())) {
            throw new JeecgBootException("门店ID不能为空");
        }
        FreshStore existing = getById(store.getId());
        if (existing == null) {
            throw new JeecgBootException("门店不存在或已被删除");
        }
        normalize(store);
        referenceGuard.assertStoreCodeUnique(store.getStoreCode(), store.getId());
        store.setCreateBy(existing.getCreateBy());
        store.setCreateTime(existing.getCreateTime());
        store.setUpdateBy(currentUsername());
        store.setUpdateTime(new Date());
        updateById(store);
        return store;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void deleteStore(String id) {
        if (oConvertUtils.isEmpty(id) || getById(id) == null) {
            throw new JeecgBootException("门店不存在或已被删除");
        }
        referenceGuard.assertStoreDeletable(id);
        removeById(id);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void deleteStores(List<String> ids) {
        for (String id : ids) {
            deleteStore(id);
        }
    }

    @Override
    public List<FreshStore> enabledOptions() {
        return list(new LambdaQueryWrapper<FreshStore>()
                .eq(FreshStore::getStatus, FreshConstants.STATUS_ACTIVE)
                .orderByAsc(FreshStore::getStoreCode));
    }

    @Override
    public FreshStore myStore() {
        return accessService.requireBoundStore();
    }

    private void normalize(FreshStore store) {
        if (store == null) {
            throw new JeecgBootException("门店信息不能为空");
        }
        store.setStoreCode(FreshValidation.code(store.getStoreCode(), "门店编码"));
        store.setStoreName(FreshValidation.text(store.getStoreName(), "门店名称", 128));
        store.setAddress(FreshValidation.text(store.getAddress(), "门店地址", 255));
        store.setContactName(FreshValidation.optionalText(store.getContactName(), "联系人", 64));
        store.setContactPhone(FreshValidation.optionalText(store.getContactPhone(), "联系方式", 32));
        store.setStatus(FreshValidation.status(store.getStatus()));
        store.setRemark(FreshValidation.optionalText(store.getRemark(), "备注", 255));
    }

    private String currentUsername() {
        try {
            return accessService.requireUser().getUsername();
        } catch (RuntimeException e) {
            return "system";
        }
    }
}
