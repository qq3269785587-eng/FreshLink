package org.jeecg.modules.wms.fresh.service;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.IService;
import org.jeecg.modules.wms.fresh.entity.FreshStore;

import java.util.List;

public interface IFreshStoreService extends IService<FreshStore> {

    IPage<FreshStore> pageStores(Page<FreshStore> page, String keyword, String status);

    FreshStore addStore(FreshStore store);

    FreshStore editStore(FreshStore store);

    void deleteStore(String id);

    void deleteStores(List<String> ids);

    List<FreshStore> enabledOptions();

    FreshStore myStore();
}
