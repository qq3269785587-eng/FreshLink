package org.jeecg.modules.wms.wmstask.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.baomidou.mybatisplus.core.metadata.IPage;
import com.baomidou.mybatisplus.extension.plugins.pagination.PageDTO;
import com.github.pagehelper.Page;
import com.github.pagehelper.PageHelper;
import org.apache.commons.lang3.ObjectUtils;
import org.apache.shiro.SecurityUtils;
import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.common.system.vo.LoginUser;
import org.jeecg.common.util.DateUtils;
import org.jeecg.common.util.RedisUtil;
import org.jeecg.modules.wms.config.WarehouseDictEnum;
import org.jeecg.modules.wms.fresh.support.FreshValidation;
import org.jeecg.modules.wms.goods.entity.WmsProducts;
import org.jeecg.modules.wms.goods.service.IWmsProductsService;
import org.jeecg.modules.wms.inorder.entity.WmsStockInOrderItems;
import org.jeecg.modules.wms.warehouse.entity.WmsStorageLocations;
import org.jeecg.modules.wms.warehouse.entity.WmsStorageZones;
import org.jeecg.modules.wms.warehouse.service.IWmsStorageZonesService;
import org.jeecg.modules.wms.inorder.entity.WmsStockInOrders;
import org.jeecg.modules.wms.inorder.service.IWmsStockInOrderItemsService;
import org.jeecg.modules.wms.inorder.service.IWmsStockInOrdersService;
import org.jeecg.modules.wms.inventory.service.impl.WmsInventoryTransByPutway;
import org.jeecg.modules.wms.inventory.service.impl.WmsInventoryTransByReceiving;
import org.jeecg.modules.wms.inventory.vo.WmsInventoryTransParam;
import org.jeecg.modules.wms.wmstask.entity.WmsTasks;
import org.jeecg.modules.wms.wmstask.entity.WmsTasksRecords;
import org.jeecg.modules.wms.wmstask.mapper.WmsTasksMapper;
import org.jeecg.modules.wms.wmstask.service.IWmsTasksRecordsService;
import org.jeecg.modules.wms.wmstask.service.IWmsTasksService;
import org.springframework.beans.factory.annotation.Autowired;
import org.jeecg.modules.wms.warehouse.service.IWmsStorageLocationsService;
import org.springframework.stereotype.Service;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Date;
import java.util.Objects;
import java.util.List;

/**
 * @Description: 任务表
 * @Author: jeecg-boot
 * @Date:   2025-08-30
 * @Version: V1.0
 */
@Service
public class WmsTasksServiceImpl extends ServiceImpl<WmsTasksMapper, WmsTasks> implements IWmsTasksService {

    private static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Shanghai");

    @Autowired
    private IWmsProductsService products;
    @Autowired
    private IWmsStorageZonesService zones;
    @Autowired
    private RedisUtil redisUtil;

    @Autowired
    private IWmsStockInOrdersService stockInOrdersService;
    @Autowired
    private IWmsStockInOrderItemsService stockInOrderItemsService;

    @Autowired
    private IWmsTasksRecordsService wmsTasksRecordsService;

    @Autowired
    private WmsInventoryTransByReceiving wmsInventoryTransByReceiving;


    @Autowired
    private WmsInventoryTransByPutway wmsInventoryExecByPutway;
    @Autowired
    private IWmsStorageLocationsService storageLocations;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public void createReceiveTasks(List<String> orderIds, String operator) {
        String assignee = FreshValidation.text(operator, "执行人", 32);
        for (String orderId : orderIds.stream().distinct().sorted().toList()) {
            createReceiveTask(orderId, assignee);
        }
    }

    private void createReceiveTask(String inOrderId, String operator) {
        //查询入库单信息
        WmsStockInOrders stockInOrders = stockInOrdersService.lockById(inOrderId);
        if (stockInOrders == null) {
            throw new JeecgBootException("入库单不存在");
        }
        //仓库
        String warehouseId = stockInOrders.getWarehouseId();
        //入库单状态
        String status = stockInOrders.getStatus();
        //入库单状态非审核通过时不允许创建收货任务
        if(!WarehouseDictEnum.INBOUND_APPROVED.getCode().equals(status)){
            throw new JeecgBootException("入库单审核通过方可创建收货任务");
        }
        //根据入库单id查询入库单明细列表
        List<WmsStockInOrderItems> stockInOrderItems = stockInOrderItemsService.selectByMainId(inOrderId);
        if (stockInOrderItems.isEmpty()) {
            throw new JeecgBootException("入库单没有明细");
        }
        //总采购数量
        long totalQuantity = 0;
        //根据入库明细列表创建收货任务
        for (WmsStockInOrderItems stockInOrderItem : stockInOrderItems) {
            //创建收货任务
            WmsTasks wmsTasks = new WmsTasks();
            //任务类型,收货任务
            wmsTasks.setTaskType(WarehouseDictEnum.TASK_TYPE_RECEIVING.getCode());
            //任务状态，已创建
            wmsTasks.setTaskStatus(WarehouseDictEnum.TASK_STATUS_CREATED.getCode());
            //任务创建时间
            wmsTasks.setCreateTime(new Date());
            //任务号
            wmsTasks.setTaskNumber(generateTaskCode());
            //目的仓库
            wmsTasks.setTargetWarehouseId(warehouseId);
            //入库单id
            wmsTasks.setStockInOrderId(stockInOrderItem.getOrderId());
            //入库单明细id
            wmsTasks.setStockInOrderItemId(stockInOrderItem.getId());
            //商品id
            wmsTasks.setProductId(stockInOrderItem.getProductId());
            //商品采购数量
            wmsTasks.setQuantity(stockInOrderItem.getExpectedQuantity());
            //完成数量为0
            wmsTasks.setCompletedQuantity(0);
            //执行人
            wmsTasks.setOperator(operator);
            requireBatch(stockInOrders, stockInOrderItem);
            wmsTasks.setBatchNumber(stockInOrderItem.getBatchNumber());
            wmsTasks.setExpiryDate(asDate(stockInOrderItem.getExpiryDate()));
            if (!save(wmsTasks)) {
                throw new JeecgBootException("创建收货任务失败");
            }
            //总采购数量
            totalQuantity += stockInOrderItem.getExpectedQuantity();
        }
        //更新入库单状态为收货中
        //sql update wms_stock_in_orders set total_expected_quantity = #{totalExpectedQuantity},status = #{status} where id = #{id} and status = #{status}
        LambdaUpdateWrapper<WmsStockInOrders> eq = new LambdaUpdateWrapper<WmsStockInOrders>()
                .eq(WmsStockInOrders::getId, inOrderId)
                .set(WmsStockInOrders::getTotalExpectedQuantity, Math.toIntExact(totalQuantity))
                .set(WmsStockInOrders::getStatus, WarehouseDictEnum.INBOUND_RECEIVING.getCode())
                .eq(WmsStockInOrders::getStatus, WarehouseDictEnum.INBOUND_APPROVED.getCode());
        boolean update = stockInOrdersService.update(null, eq);
        if(!update){
            throw new JeecgBootException("更新入库单状态失败");
        }
        //根据入库单id更新入库单明细状态为收货中
        boolean update2 = stockInOrderItemsService.update(null,
                new LambdaUpdateWrapper<WmsStockInOrderItems>().eq(WmsStockInOrderItems::getOrderId, inOrderId)
                        .set(WmsStockInOrderItems::getStatus, WarehouseDictEnum.INBOUND_DETAIL_RECEIVING.getCode()));
        if(!update2){
            throw new JeecgBootException("创建收货任务过程中更新入库单明细状态失败");
        }

    }

    /**
     * 生成任务编号
     * 规则: TSK+年月日+5位序号，序号使用redis自增序号实现
     */
    @Override
    public String generateTaskCode() {
        //参考上边的代码实现
        String time = DateUtils.now().substring(0, 10).replace("-", "");
        String key = "tsk_number"+time;
        long incr = redisUtil.incr(key, 1);
        if(incr == 1){
            //设置过期时间，设置24小时+10秒的目的是避免并发产生订单号重复
            redisUtil.expire(key, 24*60*60+10);
        }
        //将incr组成4位字符串
        String incrStr = String.format("%05d", incr);
        String taskNumber = "TSK"+time+incrStr;

        return taskNumber;
    }

    @Override
    public IPage<WmsTasks> list(WmsTasks wmsTasks, Integer pageNo, Integer pageSize) {

        Page<WmsTasks> page = PageHelper.startPage(pageNo, pageSize);
        List<WmsTasks> list = baseMapper.queryTaskList(wmsTasks);
        PageDTO<WmsTasks> wmsTasksPageDTO = new PageDTO<>();
        wmsTasksPageDTO.setRecords(list);
        wmsTasksPageDTO.setTotal(page.getTotal());
        wmsTasksPageDTO.setPages(page.getPages());
        wmsTasksPageDTO.setCurrent(page.getPageNum());
        wmsTasksPageDTO.setSize(page.getPageSize());
        return wmsTasksPageDTO;
    }

    @Transactional(rollbackFor = Exception.class)
    @Override
    public void receive(WmsTasksRecords record) {
        processInbound(record, false);
    }

    @Transactional(rollbackFor = Exception.class)
    @Override
    public void putaway(WmsTasksRecords record) {
        processInbound(record, true);
    }

    private void processInbound(WmsTasksRecords record, boolean putaway) {
        String type = putaway ? WarehouseDictEnum.TASK_TYPE_PUTAWAY.getCode()
                : WarehouseDictEnum.TASK_TYPE_RECEIVING.getCode();
        String taskId = FreshValidation.text(record.getTaskId(), "任务ID", 32);
        String requestKey = FreshValidation.code(record.getRequestKey(), "请求键");
        String targetCode = FreshValidation.text(record.getTargetLocationCode(), "目标储位", 32);
        requireQuantity(record.getExecQuantity());

        WmsTasks task = baseMapper.selectOne(new LambdaQueryWrapper<WmsTasks>()
                .eq(WmsTasks::getId, taskId).eq(WmsTasks::getTaskType, type).last("FOR UPDATE"));
        if (task == null) {
            throw new JeecgBootException("对应类型的入库任务不存在");
        }
        WmsStockInOrders order = stockInOrdersService.lockById(task.getStockInOrderId());
        if (order == null) {
            throw new JeecgBootException("入库单不存在");
        }
        WmsTasksRecords prior = wmsTasksRecordsService.getOne(new LambdaQueryWrapper<WmsTasksRecords>()
                .eq(WmsTasksRecords::getTaskId, taskId).eq(WmsTasksRecords::getRequestKey, requestKey));
        if (prior != null) {
            if (!Objects.equals(prior.getExecQuantity(), record.getExecQuantity())
                    || !targetCode.equalsIgnoreCase(prior.getTargetLocationCode())) {
                throw new JeecgBootException("请求键已用于其他数量或储位");
            }
            return;
        }
        if (putaway ? !List.of(WarehouseDictEnum.INBOUND_RECEIVED.getCode(),
                WarehouseDictEnum.INBOUND_PUTAWAYING.getCode()).contains(order.getStatus())
                : !WarehouseDictEnum.INBOUND_RECEIVING.getCode().equals(order.getStatus())) {
            throw new JeecgBootException("入库单当前状态不允许执行此任务");
        }
        WmsStockInOrderItems item = stockInOrderItemsService.getById(task.getStockInOrderItemId());
        requireBatch(order, item);
        WmsStorageLocations target = requireInboundTarget(task, targetCode, putaway);
        if (!putaway) {
            stockInOrdersService.requireReceivable(order, item);
        }
        record.setRequestKey(requestKey);
        record.setTargetLocationCode(target.getLocationCode());
        record.setSourceLocationCode(putaway ? task.getSourceLocationCode() : null);
        record.setInventoryAttribute(WarehouseDictEnum.INVENTORY_ATTRIBUTE_GOOD.getCode());
        record.setBatchNumber(item.getBatchNumber());
        record.setExpiryDate(asDate(item.getExpiryDate()));
        executeTask(record, task);

        WmsInventoryTransParam transfer = new WmsInventoryTransParam();
        transfer.setProductId(item.getProductId());
        transfer.setExecQuantity(record.getExecQuantity());
        transfer.setWarehouseId(task.getTargetWarehouseId());
        transfer.setSourceLocationCode(record.getSourceLocationCode());
        transfer.setTargetLocationCode(record.getTargetLocationCode());
        transfer.setBatchNumber("FL:" + item.getId());
        transfer.setExpiryDate(record.getExpiryDate());
        transfer.setOperationTime(record.getOperationTime());
        transfer.setIsSellable("1");
        if (putaway) {
            transfer.setRemarks("上架,入库单:" + order.getId());
            transfer.setTransactionType(WarehouseDictEnum.INVENTORY_PUTAWAY.getCode());
            wmsInventoryExecByPutway.transfer(transfer);
            stockInOrderItemsService.updatePutawayStatus(item.getId());
            stockInOrdersService.updatePutawayStatus(order.getId());
        } else {
            transfer.setRemarks("收货,入库单:" + order.getId());
            transfer.setTransactionType(WarehouseDictEnum.INVENTORY_RECEIVING.getCode());
            wmsInventoryTransByReceiving.transfer(transfer);
            stockInOrderItemsService.updateReceivedStatus(item.getId());
            if (WarehouseDictEnum.INBOUND_RECEIVED.getCode().equals(
                    stockInOrdersService.updateReceivedStatus(order.getId()))) {
                createPutawayTask(order.getId());
            }
        }
    }

    private void requireBatch(WmsStockInOrders order, WmsStockInOrderItems item) {
        if (item == null || !order.getId().equals(item.getOrderId()) || order.getSupplierId() == null
                || item.getBatchNumber() == null || item.getProductionDate() == null || item.getExpiryDate() == null) {
            throw new JeecgBootException("入库批次缺供应商、批号或日期，需重新建立有效入库计划");
        }
    }

    private WmsStorageLocations requireInboundTarget(WmsTasks task, String targetCode, boolean putaway) {
        String code = storageLocations.requireActivePutawayTarget(task.getTargetWarehouseId(), targetCode);
        WmsStorageLocations target = storageLocations.lambdaQuery()
                .eq(WmsStorageLocations::getWarehouseId, task.getTargetWarehouseId())
                .eq(WmsStorageLocations::getLocationCode, code).last("FOR UPDATE").one();
        String type = target.getLocationType();
        if (!putaway) {
            if (!WarehouseDictEnum.LOCATION_TYPE_RECEIVING.getCode().equals(type)) {
                throw new JeecgBootException("收货目标须为收货位");
            }
            return target;
        }
        if (!"1".equals(target.getIsSellable())
                || (!WarehouseDictEnum.LOCATION_TYPE_STORAGE.getCode().equals(type)
                    && !WarehouseDictEnum.LOCATION_TYPE_PICKING.getCode().equals(type))) {
            throw new JeecgBootException("上架目标须为可用的良品正式储位");
        }
        WmsStorageZones zone = zones.getById(target.getZoneId());
        WmsProducts product = products.getOne(new LambdaQueryWrapper<WmsProducts>()
                .eq(WmsProducts::getId, task.getProductId()).last("FOR UPDATE"));
        if (product == null || product.getStorageType() == null
                || !product.getStorageType().equals(zone.getStorageType())) {
            throw new JeecgBootException("上架储位温区与食材温区不一致");
        }
        return target;
    }

    private static Date asDate(LocalDate date) {
        return Date.from(date.atStartOfDay(BUSINESS_ZONE).toInstant());
    }

    private static void requireQuantity(Integer quantity) {
        if (quantity == null || quantity <= 0) {
            throw new JeecgBootException("执行数量必须为正整数");
        }
    }

    @Override
    public WmsTasks execute(WmsTasksRecords record) {
        WmsTasks task = getById(record.getTaskId());
        if (task == null || task.getStockInOrderId() != null
                || WarehouseDictEnum.TASK_TYPE_RECEIVING.getCode().equals(task.getTaskType())
                || WarehouseDictEnum.TASK_TYPE_PUTAWAY.getCode().equals(task.getTaskType())) {
            throw new JeecgBootException("入库任务必须通过收货或上架执行");
        }
        return executeTask(record, task);
    }

    private WmsTasks executeTask(WmsTasksRecords wmsTasksRecords, WmsTasks wmsTasks) {
        Integer execQuantity = wmsTasksRecords.getExecQuantity();
        requireQuantity(execQuantity);
        Integer quantity = wmsTasks.getQuantity();
        int completedQuantity = ObjectUtils.defaultIfNull(wmsTasks.getCompletedQuantity(), 0);
        if (quantity == null || (long) completedQuantity + execQuantity > quantity) {
            throw new JeecgBootException("执行数量不能大于计划数量");
        }
        LambdaUpdateWrapper<WmsTasks> update = new LambdaUpdateWrapper<WmsTasks>()
                .setSql("completed_quantity=completed_quantity+{0}", execQuantity)
                .eq(WmsTasks::getId, wmsTasks.getId())
                .ne(WmsTasks::getTaskStatus, WarehouseDictEnum.TASK_STATUS_COMPLETED.getCode())
                .ne(WmsTasks::getTaskStatus, WarehouseDictEnum.TASK_STATUS_CANCELED.getCode())
                .le(WmsTasks::getCompletedQuantity, quantity - execQuantity);
        if (!update(null, update)) {
            throw new JeecgBootException("任务已处理或执行数量超过计划");
        }

        //2.添加任务执行记录
        //目标仓库id
        wmsTasksRecords.setTargetWarehouseId(wmsTasks.getTargetWarehouseId());
        //入库单id
        wmsTasksRecords.setStockInOrderId(wmsTasks.getStockInOrderId());
        //入库单明细id
        wmsTasksRecords.setStockInOrderItemId(wmsTasks.getStockInOrderItemId());
        //任务id
        wmsTasksRecords.setTaskId(wmsTasks.getId());
        //商品 id
        wmsTasksRecords.setProductId(wmsTasks.getProductId());
        //任务编码
        wmsTasksRecords.setTaskNumber(wmsTasks.getTaskNumber());
        //任务类型
        wmsTasksRecords.setTaskType(wmsTasks.getTaskType());
        //执行时间
        wmsTasksRecords.setOperationTime(new Date());
        //执行人
        //获取当前用户
        LoginUser sysUser = (LoginUser) SecurityUtils.getSubject().getPrincipal();
        String userId = sysUser.getId();
        wmsTasksRecords.setOperator(userId);
        boolean save = wmsTasksRecordsService.save(wmsTasksRecords);
        if(!save){
            throw new JeecgBootException("添加任务执行记录失败!");
        }


        //更新任务状态，如果完成数量等于计划数量则任务状态更新为完成
        wmsTasks = getById(wmsTasks.getId());
        //完成数量
        completedQuantity = wmsTasks.getCompletedQuantity();
        //更新任务为已完成
        if(completedQuantity == wmsTasks.getQuantity().intValue()) {
            wmsTasks.setTaskStatus(WarehouseDictEnum.TASK_STATUS_COMPLETED.getCode());
            boolean b = updateById(wmsTasks);
            if(!b){
                throw new JeecgBootException("更新任务状态失败!");
            }
        }

        return wmsTasks;
    }

    private void createPutawayTask(String orderId) {
        // One putaway task per actual receipt keeps its original location and quantity.
        List<WmsTasksRecords> received = wmsTasksRecordsService.lambdaQuery()
                .eq(WmsTasksRecords::getStockInOrderId, orderId)
                .eq(WmsTasksRecords::getTaskType, WarehouseDictEnum.TASK_TYPE_RECEIVING.getCode()).list();
        //遍历收货记录创建上架任务,只将收货商品为良品的创建上架任务
        for (WmsTasksRecords wmsTasksRecords1 : received) {
            //库存属性
            String inventoryAttribute = wmsTasksRecords1.getInventoryAttribute();
            if(!WarehouseDictEnum.INVENTORY_ATTRIBUTE_GOOD.getCode().equals(inventoryAttribute)){
                continue;
            }
            WmsTasks wmsTasks = new WmsTasks();
            wmsTasks.setTaskNumber(generateTaskCode());//任务编号
            wmsTasks.setTaskType(WarehouseDictEnum.TASK_TYPE_PUTAWAY.getCode());//上架任务
            wmsTasks.setTaskStatus(WarehouseDictEnum.TASK_STATUS_CREATED.getCode());//已创建
            wmsTasks.setCreateTime(new Date());
            wmsTasks.setStockInOrderId(wmsTasksRecords1.getStockInOrderId());
            wmsTasks.setStockInOrderItemId(wmsTasksRecords1.getStockInOrderItemId());
            wmsTasks.setProductId(wmsTasksRecords1.getProductId());
            wmsTasks.setQuantity(wmsTasksRecords1.getExecQuantity());//待上架数量为收货完成数量
            wmsTasks.setCompletedQuantity(0);
            wmsTasks.setSourceLocationCode(wmsTasksRecords1.getTargetLocationCode());//来源储位编码为收货目标储位编码
            wmsTasks.setSourceContainerCode(wmsTasksRecords1.getTargetContainerCode());//来源容器编码为收货目标容器编码
            wmsTasks.setTargetWarehouseId(wmsTasksRecords1.getTargetWarehouseId());
            wmsTasks.setBatchNumber(wmsTasksRecords1.getBatchNumber()); //批次号
            wmsTasks.setExpiryDate(wmsTasksRecords1.getExpiryDate());//保质期
            wmsTasks.setOperator(wmsTasksRecords1.getOperator()); //执行人
            if (!save(wmsTasks)) {
                throw new JeecgBootException("创建上架任务失败");
            }
        }
    }

}
