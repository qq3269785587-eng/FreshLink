package org.jeecg.modules.wms.fresh.service;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.baomidou.mybatisplus.extension.service.IService;
import org.jeecg.modules.wms.fresh.entity.FreshUserStore;

import java.util.List;
import java.util.Map;

public interface IFreshUserStoreService extends IService<FreshUserStore> {

    IPage<Map<String, Object>> pageUsersWithStore(Page<?> page, String keyword);

    List<Map<String, Object>> storeRoleUsers();

    Map<String, Object> myBinding();

    void bind(String userId, String storeId);
}
