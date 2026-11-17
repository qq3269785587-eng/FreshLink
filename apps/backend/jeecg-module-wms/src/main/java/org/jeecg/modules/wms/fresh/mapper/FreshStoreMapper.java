package org.jeecg.modules.wms.fresh.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.jeecg.modules.wms.fresh.entity.FreshStore;

public interface FreshStoreMapper extends BaseMapper<FreshStore> {

    @Select("SELECT s.* FROM fresh_store s JOIN fresh_user_store f ON f.store_id = s.id WHERE f.user_id = #{userId} LIMIT 1")
    FreshStore selectBoundStore(@Param("userId") String userId);

    @Select("SELECT COUNT(*) FROM fresh_user_store WHERE store_id = #{storeId}")
    int countBindingsByStore(@Param("storeId") String storeId);
}
