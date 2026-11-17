package org.jeecg.modules.wms.fresh.controller;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.apache.shiro.authz.annotation.RequiresPermissions;
import org.jeecg.common.api.vo.Result;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.modules.wms.fresh.access.FreshAccessService;
import org.jeecg.modules.wms.fresh.entity.FreshStore;
import org.jeecg.modules.wms.fresh.service.IFreshStoreService;
import org.springframework.web.bind.annotation.*;

import jakarta.annotation.Resource;
import java.util.Arrays;
import java.util.List;

@Tag(name = "生鲜门店")
@RestController
@RequestMapping("/fresh/stores")
public class FreshStoreController {

    @Resource
    private IFreshStoreService storeService;

    @Resource
    private FreshAccessService accessService;

    @Operation(summary = "门店分页列表；门店账号只返回本店")
    @GetMapping("/list")
    public Result<IPage<FreshStore>> list(@RequestParam(name = "pageNo", defaultValue = "1") Integer pageNo,
                                          @RequestParam(name = "pageSize", defaultValue = "10") Integer pageSize,
                                          @RequestParam(name = "keyword", required = false) String keyword,
                                          @RequestParam(name = "status", required = false) String status) {
        return Result.OK(storeService.pageStores(new Page<>(pageNo, pageSize), keyword, status));
    }

    @Operation(summary = "本店资料")
    @GetMapping("/my")
    public Result<FreshStore> myStore() {
        return Result.OK(storeService.myStore());
    }

    @Operation(summary = "门店启用选项")
    @GetMapping("/options")
    public Result<List<FreshStore>> options() {
        accessService.requireStaff();
        return Result.OK(storeService.enabledOptions());
    }

    @Operation(summary = "门店详情")
    @GetMapping("/queryById")
    public Result<FreshStore> queryById(@RequestParam("id") String id) {
        if (accessService.isStoreUser()) {
            FreshStore bound = accessService.requireBoundStore();
            if (!bound.getId().equals(id)) {
                throw new JeecgBootException("门店账号只能查看本店资料");
            }
        } else {
            accessService.requireStaff();
        }
        FreshStore store = storeService.getById(id);
        if (store == null) {
            return Result.error("门店不存在");
        }
        return Result.OK(store);
    }

    @Operation(summary = "新增门店")
    @RequiresPermissions("fresh:store:add")
    @PostMapping("/add")
    public Result<FreshStore> add(@RequestBody FreshStore store) {
        accessService.requireStaff();
        return Result.OK("新增成功", storeService.addStore(store));
    }

    @Operation(summary = "编辑门店")
    @RequiresPermissions("fresh:store:edit")
    @RequestMapping(value = "/edit", method = {RequestMethod.PUT, RequestMethod.POST})
    public Result<FreshStore> edit(@RequestBody FreshStore store) {
        accessService.requireStaff();
        return Result.OK("编辑成功", storeService.editStore(store));
    }

    @Operation(summary = "删除门店")
    @RequiresPermissions("fresh:store:delete")
    @DeleteMapping("/delete")
    public Result<String> delete(@RequestParam("id") String id) {
        accessService.requireStaff();
        storeService.deleteStore(id);
        return Result.OK("删除成功");
    }

    @Operation(summary = "批量删除门店")
    @RequiresPermissions("fresh:store:deleteBatch")
    @DeleteMapping("/deleteBatch")
    public Result<String> deleteBatch(@RequestParam("ids") String ids) {
        accessService.requireStaff();
        storeService.deleteStores(Arrays.asList(ids.split(",")));
        return Result.OK("批量删除成功");
    }
}
