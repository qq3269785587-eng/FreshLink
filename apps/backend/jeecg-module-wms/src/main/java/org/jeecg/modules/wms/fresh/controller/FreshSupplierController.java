package org.jeecg.modules.wms.fresh.controller;

import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.apache.shiro.authz.annotation.RequiresPermissions;
import org.jeecg.common.api.vo.Result;
import org.jeecg.modules.wms.fresh.access.FreshAccessService;
import org.jeecg.modules.wms.fresh.entity.FreshSupplier;
import org.jeecg.modules.wms.fresh.service.IFreshSupplierService;
import org.springframework.web.bind.annotation.*;

import jakarta.annotation.Resource;
import java.util.Arrays;
import java.util.List;

@Tag(name = "生鲜供应商")
@RestController
@RequestMapping("/fresh/suppliers")
public class FreshSupplierController {

    @Resource
    private IFreshSupplierService supplierService;

    @Resource
    private FreshAccessService accessService;

    @Operation(summary = "供应商分页列表")
    @GetMapping("/list")
    public Result<IPage<FreshSupplier>> list(@RequestParam(name = "pageNo", defaultValue = "1") Integer pageNo,
                                             @RequestParam(name = "pageSize", defaultValue = "10") Integer pageSize,
                                             @RequestParam(name = "keyword", required = false) String keyword,
                                             @RequestParam(name = "status", required = false) String status) {
        accessService.requireStaff();
        return Result.OK(supplierService.pageSuppliers(new Page<>(pageNo, pageSize), keyword, status));
    }

    @Operation(summary = "供应商启用选项")
    @GetMapping("/options")
    public Result<List<FreshSupplier>> options() {
        accessService.requireStaff();
        return Result.OK(supplierService.enabledOptions());
    }

    @Operation(summary = "供应商详情")
    @GetMapping("/queryById")
    public Result<FreshSupplier> queryById(@RequestParam("id") String id) {
        accessService.requireStaff();
        FreshSupplier supplier = supplierService.getById(id);
        if (supplier == null) {
            return Result.error("供应商不存在");
        }
        return Result.OK(supplier);
    }

    @Operation(summary = "新增供应商")
    @RequiresPermissions("fresh:supplier:add")
    @PostMapping("/add")
    public Result<FreshSupplier> add(@RequestBody FreshSupplier supplier) {
        accessService.requireStaff();
        return Result.OK("新增成功", supplierService.addSupplier(supplier));
    }

    @Operation(summary = "编辑供应商")
    @RequiresPermissions("fresh:supplier:edit")
    @RequestMapping(value = "/edit", method = {RequestMethod.PUT, RequestMethod.POST})
    public Result<FreshSupplier> edit(@RequestBody FreshSupplier supplier) {
        accessService.requireStaff();
        return Result.OK("编辑成功", supplierService.editSupplier(supplier));
    }

    @Operation(summary = "删除供应商")
    @RequiresPermissions("fresh:supplier:delete")
    @DeleteMapping("/delete")
    public Result<String> delete(@RequestParam("id") String id) {
        accessService.requireStaff();
        supplierService.deleteSupplier(id);
        return Result.OK("删除成功");
    }

    @Operation(summary = "批量删除供应商")
    @RequiresPermissions("fresh:supplier:deleteBatch")
    @DeleteMapping("/deleteBatch")
    public Result<String> deleteBatch(@RequestParam("ids") String ids) {
        accessService.requireStaff();
        supplierService.deleteSuppliers(Arrays.asList(ids.split(",")));
        return Result.OK("批量删除成功");
    }
}
