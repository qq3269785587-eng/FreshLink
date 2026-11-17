package org.jeecg.modules.wms.fresh.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.common.util.oConvertUtils;
import org.jeecg.modules.wms.fresh.access.FreshAccessService;
import org.jeecg.modules.wms.fresh.constant.FreshConstants;
import org.jeecg.modules.wms.fresh.entity.FreshSupplier;
import org.jeecg.modules.wms.fresh.mapper.FreshSupplierMapper;
import org.jeecg.modules.wms.fresh.service.IFreshSupplierService;
import org.jeecg.modules.wms.fresh.support.FreshReferenceGuard;
import org.jeecg.modules.wms.fresh.support.FreshValidation;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import jakarta.annotation.Resource;
import java.util.Date;
import java.util.List;

@Service
public class FreshSupplierServiceImpl extends ServiceImpl<FreshSupplierMapper, FreshSupplier>
        implements IFreshSupplierService {

    @Resource
    private FreshReferenceGuard referenceGuard;

    @Resource
    private FreshAccessService accessService;

    @Override
    public IPage<FreshSupplier> pageSuppliers(Page<FreshSupplier> page, String keyword, String status) {
        LambdaQueryWrapper<FreshSupplier> query = new LambdaQueryWrapper<>();
        if (oConvertUtils.isNotEmpty(keyword)) {
            query.and(w -> w.like(FreshSupplier::getSupplierCode, keyword)
                    .or().like(FreshSupplier::getSupplierName, keyword));
        }
        if (oConvertUtils.isNotEmpty(status)) {
            query.eq(FreshSupplier::getStatus, status.trim().toUpperCase());
        }
        query.orderByAsc(FreshSupplier::getSupplierCode);
        return page(page, query);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public FreshSupplier addSupplier(FreshSupplier supplier) {
        normalize(supplier, true);
        referenceGuard.assertSupplierCodeUnique(supplier.getSupplierCode(), null);
        String user = currentUsername();
        supplier.setCreateBy(user);
        supplier.setCreateTime(new Date());
        save(supplier);
        return supplier;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public FreshSupplier editSupplier(FreshSupplier supplier) {
        if (oConvertUtils.isEmpty(supplier.getId())) {
            throw new JeecgBootException("供应商ID不能为空");
        }
        FreshSupplier existing = getById(supplier.getId());
        if (existing == null) {
            throw new JeecgBootException("供应商不存在或已被删除");
        }
        normalize(supplier, false);
        referenceGuard.assertSupplierCodeUnique(supplier.getSupplierCode(), supplier.getId());
        supplier.setCreateBy(existing.getCreateBy());
        supplier.setCreateTime(existing.getCreateTime());
        supplier.setUpdateBy(currentUsername());
        supplier.setUpdateTime(new Date());
        updateById(supplier);
        return supplier;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void deleteSupplier(String id) {
        if (oConvertUtils.isEmpty(id) || getById(id) == null) {
            throw new JeecgBootException("供应商不存在或已被删除");
        }
        referenceGuard.assertSupplierDeletable(id);
        removeById(id);
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void deleteSuppliers(List<String> ids) {
        for (String id : ids) {
            deleteSupplier(id);
        }
    }

    @Override
    public List<FreshSupplier> enabledOptions() {
        return list(new LambdaQueryWrapper<FreshSupplier>()
                .eq(FreshSupplier::getStatus, FreshConstants.STATUS_ACTIVE)
                .orderByAsc(FreshSupplier::getSupplierCode));
    }

    private void normalize(FreshSupplier supplier, boolean create) {
        if (supplier == null) {
            throw new JeecgBootException("供应商信息不能为空");
        }
        supplier.setSupplierCode(FreshValidation.code(supplier.getSupplierCode(), "供应商编码"));
        supplier.setSupplierName(FreshValidation.text(supplier.getSupplierName(), "供应商名称", 128));
        supplier.setContactName(FreshValidation.optionalText(supplier.getContactName(), "联系人", 64));
        supplier.setContactPhone(FreshValidation.optionalText(supplier.getContactPhone(), "联系方式", 32));
        supplier.setStatus(FreshValidation.status(supplier.getStatus()));
        supplier.setRemark(FreshValidation.optionalText(supplier.getRemark(), "备注", 255));
    }

    private String currentUsername() {
        try {
            return accessService.requireUser().getUsername();
        } catch (RuntimeException e) {
            return "system";
        }
    }
}
