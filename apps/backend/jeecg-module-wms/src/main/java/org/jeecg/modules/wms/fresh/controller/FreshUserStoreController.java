package org.jeecg.modules.wms.fresh.controller;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.apache.shiro.authz.annotation.RequiresPermissions;
import org.jeecg.common.api.vo.Result;
import org.jeecg.modules.wms.fresh.access.FreshAccessService;
import org.jeecg.modules.wms.fresh.service.IFreshUserStoreService;
import org.springframework.web.bind.annotation.*;

import jakarta.annotation.Resource;
import java.util.Map;

@Tag(name = "用户门店绑定")
@RestController
@RequestMapping("/fresh/userStores")
public class FreshUserStoreController {

    @Resource
    private IFreshUserStoreService userStoreService;

    @Resource
    private FreshAccessService accessService;

    @Operation(summary = "用户与门店绑定分页列表（总部）")
    @GetMapping("/list")
    public Result<IPage<Map<String, Object>>> list(@RequestParam(name = "pageNo", defaultValue = "1") Integer pageNo,
                                                   @RequestParam(name = "pageSize", defaultValue = "10") Integer pageSize,
                                                   @RequestParam(name = "keyword", required = false) String keyword) {
        accessService.requireHq();
        return Result.OK(userStoreService.pageUsersWithStore(new Page<>(pageNo, pageSize), keyword));
    }

    @Operation(summary = "当前账号的绑定门店")
    @GetMapping("/my")
    public Result<Map<String, Object>> my() {
        return Result.OK(userStoreService.myBinding());
    }

    @Operation(summary = "可绑定的门店角色用户")
    @GetMapping("/candidates")
    public Result<java.util.List<Map<String, Object>>> candidates() {
        accessService.requireHq();
        return Result.OK(userStoreService.storeRoleUsers());
    }

    @Operation(summary = "绑定/解绑用户门店（总部）")
    @RequiresPermissions("fresh:userstore:edit")
    @PostMapping("/bind")
    public Result<String> bind(@RequestBody Map<String, String> body) {
        // The service re-checks the HQ role and the target role; the client cannot self-assign.
        accessService.requireHq();
        userStoreService.bind(body.get("userId"), body.get("storeId"));
        return Result.OK("绑定已更新");
    }
}
