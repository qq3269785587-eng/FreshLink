package org.jeecg.modules.wms.fresh.service;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.IService;
import org.jeecg.modules.wms.fresh.entity.FreshSupplier;

import java.util.List;

public interface IFreshSupplierService extends IService<FreshSupplier> {

    IPage<FreshSupplier> pageSuppliers(Page<FreshSupplier> page, String keyword, String status);

    FreshSupplier addSupplier(FreshSupplier supplier);

    FreshSupplier editSupplier(FreshSupplier supplier);

    void deleteSupplier(String id);

    void deleteSuppliers(List<String> ids);

    List<FreshSupplier> enabledOptions();
}
