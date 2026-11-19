package org.jeecg.modules.wms.inventory.controller;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.net.URLDecoder;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.jeecg.common.api.vo.Result;
import org.jeecg.common.system.query.QueryGenerator;
import org.jeecg.common.system.query.QueryRuleEnum;
import org.jeecg.common.util.oConvertUtils;
import org.jeecg.modules.wms.inventory.entity.WmsInventory;
import org.jeecg.modules.wms.inventory.service.IWmsInventoryService;
import org.jeecg.modules.wms.fresh.access.FreshAccessService;
import org.jeecg.common.exception.JeecgBootException;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import lombok.extern.slf4j.Slf4j;

import org.jeecgframework.poi.excel.ExcelImportUtil;
import org.jeecgframework.poi.excel.def.NormalExcelConstants;
import org.jeecgframework.poi.excel.entity.ExportParams;
import org.jeecgframework.poi.excel.entity.ImportParams;
import org.jeecgframework.poi.excel.view.JeecgEntityExcelView;
import org.jeecg.common.system.base.controller.JeecgController;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.multipart.MultipartHttpServletRequest;
import org.springframework.web.servlet.ModelAndView;
import com.alibaba.fastjson.JSON;
import io.swagger.v3.oas.annotations.tags.Tag;
import io.swagger.v3.oas.annotations.Operation;
import org.jeecg.common.aspect.annotation.AutoLog;
import org.apache.shiro.authz.annotation.RequiresPermissions;

 /**
 * @Description: 库存表
 * @Author: jeecg-boot
 * @Date:   2025-08-30
 * @Version: V1.0
 */
@Tag(name="库存表")
@RestController
@RequestMapping("/inventory/wmsInventory")
@Slf4j
public class WmsInventoryController extends JeecgController<WmsInventory, IWmsInventoryService> {
	@Autowired
	private IWmsInventoryService wmsInventoryService;
	@Autowired
	private FreshAccessService freshAccess;

	/**
	 * 分页列表查询
	 *
	 * @param wmsInventory
	 * @param pageNo
	 * @param pageSize
	 * @param req
	 * @return
	 */
	//@AutoLog(value = "库存表-分页列表查询")
	@Operation(summary="库存表-分页列表查询")
	@GetMapping(value = "/list")
	public Result<IPage<WmsInventory>> queryPageList(WmsInventory wmsInventory,
								   @RequestParam(name="pageNo", defaultValue="1") Integer pageNo,
								   @RequestParam(name="pageSize", defaultValue="10") Integer pageSize,
								   HttpServletRequest req) {
		freshAccess.requireStaff();
		IPage<WmsInventory> wmsInventoryIPage = wmsInventoryService.queryList(wmsInventory, pageNo, pageSize);
		return Result.OK(wmsInventoryIPage);
	}

	/**
	 *   添加
	 *
	 * @param wmsInventory
	 * @return
	 */
	@AutoLog(value = "库存表-添加")
	@Operation(summary="库存表-添加")
	@RequiresPermissions("inventory:wms_inventory:add")
	@PostMapping(value = "/add")
	public Result<String> add(@RequestBody WmsInventory wmsInventory) {
		freshAccess.requireStaff();
		throw new JeecgBootException("库存只能通过入库收货、上架和确认出库业务变更");
	}

	/**
	 *  编辑
	 *
	 * @param wmsInventory
	 * @return
	 */
	@AutoLog(value = "库存表-编辑")
	@Operation(summary="库存表-编辑")
	@RequiresPermissions("inventory:wms_inventory:edit")
	@RequestMapping(value = "/edit", method = {RequestMethod.PUT,RequestMethod.POST})
	public Result<String> edit(@RequestBody WmsInventory wmsInventory) {
		freshAccess.requireStaff();
		throw new JeecgBootException("库存只能通过入库收货、上架和确认出库业务变更");
	}

	/**
	 *   通过id删除
	 *
	 * @param id
	 * @return
	 */
	@AutoLog(value = "库存表-通过id删除")
	@Operation(summary="库存表-通过id删除")
	@RequiresPermissions("inventory:wms_inventory:delete")
	@DeleteMapping(value = "/delete")
	public Result<String> delete(@RequestParam(name="id",required=true) String id) {
		freshAccess.requireStaff();
		throw new JeecgBootException("库存流水和批次来源需保留，不能直接删除库存");
	}

	/**
	 *  批量删除
	 *
	 * @param ids
	 * @return
	 */
	@AutoLog(value = "库存表-批量删除")
	@Operation(summary="库存表-批量删除")
	@RequiresPermissions("inventory:wms_inventory:deleteBatch")
	@DeleteMapping(value = "/deleteBatch")
	public Result<String> deleteBatch(@RequestParam(name="ids",required=true) String ids) {
		freshAccess.requireStaff();
		throw new JeecgBootException("库存流水和批次来源需保留，不能直接删除库存");
	}

	/**
	 * 通过id查询
	 *
	 * @param id
	 * @return
	 */
	//@AutoLog(value = "库存表-通过id查询")
	@Operation(summary="库存表-通过id查询")
	@GetMapping(value = "/queryById")
	public Result<WmsInventory> queryById(@RequestParam(name="id",required=true) String id) {
		freshAccess.requireStaff();
        WmsInventory query = new WmsInventory();
        query.setId(id);
        return wmsInventoryService.queryList(query, 1, 1).getRecords().stream()
                .findFirst().map(Result::OK).orElseGet(() -> Result.error("未找到对应数据"));
	}

    /**
    * 导出excel
    *
    * @param request
    * @param wmsInventory
    */
    @RequiresPermissions("inventory:wms_inventory:exportXls")
    @RequestMapping(value = "/exportXls")
    public ModelAndView exportXls(HttpServletRequest request, WmsInventory wmsInventory) {
        freshAccess.requireStaff();
        return super.exportXls(request, wmsInventory, WmsInventory.class, "库存表");
    }

    /**
      * 通过excel导入数据
    *
    * @param request
    * @param response
    * @return
    */
    @RequiresPermissions("inventory:wms_inventory:importExcel")
    @RequestMapping(value = "/importExcel", method = RequestMethod.POST)
    public Result<?> importExcel(HttpServletRequest request, HttpServletResponse response) {
        freshAccess.requireStaff();
        throw new JeecgBootException("库存只能通过入库收货、上架和确认出库业务变更");
    }

}
