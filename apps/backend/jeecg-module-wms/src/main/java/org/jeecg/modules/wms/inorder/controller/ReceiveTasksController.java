package org.jeecg.modules.wms.inorder.controller;


import jakarta.servlet.http.HttpServletRequest;
import java.util.Arrays;
import org.apache.commons.lang3.StringUtils;
import org.apache.shiro.SecurityUtils;
import org.jeecg.common.api.vo.Result;
import org.jeecg.modules.wms.config.WarehouseDictEnum;
import org.jeecg.modules.wms.fresh.access.FreshAccessService;
import org.jeecg.modules.wms.inorder.vo.FreshInboundAction;
import org.jeecg.common.system.vo.LoginUser;
import org.jeecg.modules.wms.wmstask.entity.WmsTasks;
import org.jeecg.modules.wms.wmstask.entity.WmsTasksRecords;
import org.jeecg.modules.wms.wmstask.service.IWmsTasksRecordsService;
import org.jeecg.modules.wms.wmstask.service.IWmsTasksService;

import com.baomidou.mybatisplus.core.metadata.IPage;
import lombok.extern.slf4j.Slf4j;

import org.jeecg.common.system.base.controller.JeecgController;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.ModelAndView;
import io.swagger.v3.oas.annotations.tags.Tag;
import io.swagger.v3.oas.annotations.Operation;
import org.jeecg.common.aspect.annotation.AutoLog;
import org.apache.shiro.authz.annotation.RequiresPermissions;

 /**
 * @Description: 收货任务接口
 * @Author: jeecg-boot
 * @Date:   2025-08-30
 * @Version: V1.0
 */
@Tag(name="任务表")
@RestController
@RequestMapping("/inorder/receiveTasks")
@Slf4j
public class ReceiveTasksController extends JeecgController<WmsTasks, IWmsTasksService> {
	@Autowired
	private IWmsTasksService wmsTasksService;
    @Autowired
    private FreshAccessService access;
	 @Autowired
	 private IWmsTasksRecordsService wmsTasksRecordsService;
	/**
	 * 分页列表查询
	 *
	 * @param wmsTasks
	 * @param pageNo
	 * @param pageSize
	 * @param req
	 * @return
	 */
	//@AutoLog(value = "任务表-分页列表查询")
	@Operation(summary="任务表-分页列表查询")
	@GetMapping(value = "/list")
	public Result<IPage<WmsTasks>> queryPageList(WmsTasks wmsTasks,
								   @RequestParam(name="pageNo", defaultValue="1") Integer pageNo,
								   @RequestParam(name="pageSize", defaultValue="10") Integer pageSize,
								   HttpServletRequest req) {

        access.requireStaff();
        wmsTasks.setTaskType(WarehouseDictEnum.TASK_TYPE_RECEIVING.getCode());
		//获取当前用户
		LoginUser sysUser = (LoginUser) SecurityUtils.getSubject().getPrincipal();
		wmsTasks.setOperator(sysUser.getId());
		IPage<WmsTasks> pageList = wmsTasksService.list(wmsTasks,pageNo,pageSize);
		return Result.OK(pageList);
	}

	 @Operation(summary="收货记录查询")
	 @GetMapping(value = "/records")
	 public Result<IPage<WmsTasksRecords>> records(WmsTasksRecords wmsTasksRecords,
														 @RequestParam(name="pageNo", defaultValue="1") Integer pageNo,
														 @RequestParam(name="pageSize", defaultValue="10") Integer pageSize,
														 HttpServletRequest req) {
         access.requireStaff();
         wmsTasksRecords.setTaskType(WarehouseDictEnum.TASK_TYPE_RECEIVING.getCode());
		 //当前用户id
		 LoginUser sysUser = (LoginUser) SecurityUtils.getSubject().getPrincipal();
		 wmsTasksRecords.setOperator(sysUser.getId());
		 IPage<WmsTasksRecords> records = wmsTasksRecordsService.pageList(wmsTasksRecords, pageNo, pageSize);
		 return Result.OK(records);
	 }
	 /**
	  * 创建收货任务
	  * 参数： 入库单id,执行人
	  */
	 @AutoLog(value = "创建收货任务")
	 @Operation(summary="创建收货任务")
	 @RequiresPermissions("inorder:receive_task:add")
	 @PostMapping(value = "/add")
	 public Result<String> add(String orderIds, String operator){
         access.requireStaff();
		 if(StringUtils.isEmpty(orderIds) || StringUtils.isEmpty( operator)){
			 return Result.error("请选择入库单及执行人！");
		 }
		 String[] orderIdArray = orderIds.split(",");
		 if(orderIdArray.length == 0){
			 return Result.error("请选择入库单！");
		 }
         wmsTasksService.createReceiveTasks(Arrays.asList(orderIdArray), operator);
		 return Result.OK("创建成功！");
	 }
	 /**
	  *   收货
	  *
	  * @param wmsTasksRecords
	  * @return
	  */
	 @AutoLog(value = "收货")
	 @Operation(summary="收货")
	 @RequiresPermissions("inorder:receive_task:addRecords")
	 @PostMapping(value = "/addRecords")
	 public Result<String> addRecords(@RequestBody FreshInboundAction action) {
        access.requireStaff();
        wmsTasksService.receive(action.toRecord());
        return Result.OK("添加成功！");
	 }

	 /**
	  * 通过id查询
	  *
	  * @param id
	  * @return
	  */
	 //@AutoLog(value = "任务表-通过id查询")
	 @Operation(summary="任务表-通过id查询")
	 @GetMapping(value = "/queryById")
	 public Result<WmsTasks> queryById(@RequestParam(name="id",required=true) String id) {
		 access.requireStaff();
       WmsTasks wmsTasks = wmsTasksService.getById(id);
		 if (wmsTasks == null || !WarehouseDictEnum.TASK_TYPE_RECEIVING.getCode().equals(wmsTasks.getTaskType())) {
			 return Result.error("未找到对应数据");
		 }
		 return Result.OK(wmsTasks);
	 }

}
