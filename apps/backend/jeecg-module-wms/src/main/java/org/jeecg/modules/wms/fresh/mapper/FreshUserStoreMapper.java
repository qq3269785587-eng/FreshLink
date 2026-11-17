package org.jeecg.modules.wms.fresh.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.jeecg.modules.wms.fresh.entity.FreshUserStore;

import java.util.List;
import java.util.Map;

public interface FreshUserStoreMapper extends BaseMapper<FreshUserStore> {

    @Select("SELECT DISTINCT r.role_code FROM sys_user_role ur JOIN sys_role r ON r.id = ur.role_id WHERE ur.user_id = #{userId}")
    List<String> selectRoleCodes(@Param("userId") String userId);

    @Select("SELECT COUNT(*) FROM sys_user WHERE id = #{userId} AND status = 1 AND del_flag = 0")
    int countActiveUser(@Param("userId") String userId);

    @Select("SELECT username FROM sys_user WHERE id = #{userId} AND del_flag = 0 LIMIT 1")
    String selectUsername(@Param("userId") String userId);

    @Select("<script>"
            + "SELECT u.id AS userId, u.username, u.realname, u.status AS userStatus, "
            + "f.store_id AS storeId, s.store_code AS storeCode, s.store_name AS storeName, f.create_time AS boundTime "
            + "FROM sys_user u "
            + "LEFT JOIN fresh_user_store f ON f.user_id = u.id "
            + "LEFT JOIN fresh_store s ON s.id = f.store_id "
            + "WHERE u.del_flag = 0 AND u.status = 1 "
            + "<if test='keyword != null and keyword != \"\"'>"
            + "AND (u.username LIKE CONCAT('%', #{keyword}, '%') OR u.realname LIKE CONCAT('%', #{keyword}, '%')) "
            + "</if>"
            + "ORDER BY u.username"
            + "</script>")
    IPage<Map<String, Object>> pageUsersWithStore(Page<?> page, @Param("keyword") String keyword);

    @Select("SELECT COUNT(*) FROM fresh_user_store WHERE user_id = #{userId}")
    int countBindingByUser(@Param("userId") String userId);

    @Select("SELECT DISTINCT u.id AS id, CONCAT(u.username, ' (', IFNULL(u.realname, ''), ')') AS label, "
            + "u.username, u.realname, f.store_id AS storeId "
            + "FROM sys_user u "
            + "JOIN sys_user_role ur ON ur.user_id = u.id "
            + "JOIN sys_role r ON r.id = ur.role_id "
            + "LEFT JOIN fresh_user_store f ON f.user_id = u.id "
            + "WHERE r.role_code = 'fresh_store' AND u.status = 1 AND u.del_flag = 0 "
            + "ORDER BY u.username")
    List<Map<String, Object>> selectStoreRoleUsers();
}
