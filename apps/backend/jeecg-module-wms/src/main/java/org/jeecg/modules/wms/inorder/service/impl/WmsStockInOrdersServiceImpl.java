package org.jeecg.modules.wms.inorder.service.impl;

import org.jeecg.common.exception.JeecgBootException;
import org.jeecg.common.util.DateUtils;
import org.jeecg.common.util.RedisUtil;
import org.jeecg.common.util.oConvertUtils;
import org.jeecg.modules.wms.config.WarehouseDictEnum;
import org.jeecg.modules.wms.inorder.entity.WmsStockInOrders;
import org.jeecg.modules.wms.inorder.entity.WmsStockInOrderItems;
import org.jeecg.modules.wms.inorder.mapper.WmsStockInOrderItemsMapper;
import org.jeecg.modules.wms.inorder.mapper.WmsStockInOrdersMapper;
import org.jeecg.modules.wms.inorder.service.IWmsStockInOrderItemsService;
import org.jeecg.modules.wms.inorder.service.IWmsStockInOrdersService;
import org.jeecg.modules.wms.inorder.vo.WmsStockInOrdersPage;
import org.springframework.stereotype.Service;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.transaction.annotation.Transactional;
import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import java.io.Serializable;
import java.util.List;
import java.util.Collection;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Locale;
import org.jeecg.modules.wms.fresh.support.FreshValidation;
import java.util.Objects;
import org.jeecg.modules.wms.goods.entity.WmsProducts;
import org.jeecg.modules.wms.goods.service.IWmsProductsService;
import org.jeecg.modules.wms.fresh.entity.FreshSupplier;
import org.jeecg.modules.wms.fresh.service.IFreshSupplierService;
import org.jeecg.modules.wms.fresh.access.FreshAccessService;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * @Description: 入库单主表
 * @Author: jeecg-boot
 * @Date:   2025-08-30
 * @Version: V1.0
 */
@Service
public class WmsStockInOrdersServiceImpl extends ServiceImpl<WmsStockInOrdersMapper, WmsStockInOrders> implements IWmsStockInOrdersService {
	private record InboundBatchKey(String productId, String batchNumber) { }

	@Autowired
	private WmsStockInOrdersMapper wmsStockInOrdersMapper;
	@Autowired
	private WmsStockInOrderItemsMapper wmsStockInOrderItemsMapper;
	@Autowired
	private RedisUtil redisUtil;
	@Autowired
	private IWmsProductsService productsService;
	@Autowired
	private IFreshSupplierService supplierService;
	@Autowired
	private JdbcTemplate jdbcTemplate;
	@Autowired
	private FreshAccessService freshAccessService;

	@Autowired
	private IWmsStockInOrderItemsService stockInOrderItemsService;

	@Override
	public void add(WmsStockInOrders wmsStockInOrders) {
		//生成入库单号
		String orderNumber = generateOrderNumber();
		wmsStockInOrders.setOrderNumber(orderNumber);
		//设置入库单状态为初始状态
		wmsStockInOrders.setStatus(WarehouseDictEnum.INBOUND_INITIAL.getCode());
		//入库单表插入一条记录
		save(wmsStockInOrders);
	}

	@Override
	public WmsStockInOrders lockById(String id) {
		return getBaseMapper().selectOne(new LambdaQueryWrapper<WmsStockInOrders>()
				.eq(WmsStockInOrders::getId, id).last("FOR UPDATE"));
	}

	@Override
	public void requireReceivable(WmsStockInOrders order, WmsStockInOrderItems item) {
		validatePlannedFacts(order, item);
		LocalDate today = LocalDate.now(ZoneId.of("Asia/Shanghai"));
		if (item.getProductionDate().isAfter(today) || !item.getExpiryDate().isAfter(today)) {
			throw new JeecgBootException("生产日期不得晚于收货日，到期日期须晚于收货日");
		}
	}

	private void validatePlannedFacts(WmsStockInOrders order, WmsStockInOrderItems item) {
		if (order == null || item == null) {
			throw new JeecgBootException("入库单或明细不存在");
		}
		if (order.getSupplierId() == null || order.getSupplierId().isBlank()) {
			throw new JeecgBootException("入库单缺少供应商，不能执行生鲜收货");
		}
		FreshSupplier supplier = supplierService.getById(order.getSupplierId());
		if (supplier == null || !"ACTIVE".equals(supplier.getStatus())) {
			throw new JeecgBootException("供应商不存在或已停用，不能执行新收货");
		}
		WmsProducts product = productsService.getById(item.getProductId());
		if (product == null || !"ACTIVE".equals(product.getStatus())) {
			throw new JeecgBootException("食材不存在或已停用，不能执行生鲜收货");
		}
		if (item.getBatchNumber() == null || item.getBatchNumber().isBlank()
				|| item.getProductionDate() == null || item.getExpiryDate() == null) {
			throw new JeecgBootException("批号、生产日期和到期日期不能为空");
		}
		if (!item.getExpiryDate().isAfter(item.getProductionDate())) {
			throw new JeecgBootException("到期日期须晚于生产日期");
		}
	}

	/**
	 * 生成入库单号
	 */
	public String generateOrderNumber() {
		//8位年月日+4位流水号
		String time = DateUtils.now().substring(0,10).replace("-", "");
		//4位流水号
		String key = "wms:asn_number"+time;
		//获取流水号
		long incr = redisUtil.incr(key, 1);
		if(incr == 1){
			//如果是第一次设置流水号则设置过期 时间为24小时+10秒
			redisUtil.expire(key, 24*60*60+10);
		}
		String serialNumber = String.format("%04d", incr);
		//入库单号
		String orderNumber = "ASN"+time + serialNumber;
		return orderNumber;
	}


	@Override
	@Transactional(rollbackFor = Exception.class)
	public void saveMain(WmsStockInOrders wmsStockInOrders, List<WmsStockInOrderItems> wmsStockInOrderItemsList) {
		freshAccessService.requireStaff();
		if (wmsStockInOrderItemsList == null || wmsStockInOrderItemsList.isEmpty()) {
			throw new JeecgBootException("请添加入库明细");
		}
		validateProducts(wmsStockInOrders, wmsStockInOrderItemsList, List.of());
		wmsStockInOrders.setId(null);
		wmsStockInOrders.setOrderNumber(generateOrderNumber());
		wmsStockInOrders.setStatus(WarehouseDictEnum.INBOUND_INITIAL.getCode());
		wmsStockInOrders.setTotalReceivedQuantity(0);
		wmsStockInOrders.setTotalShelvedQuantity(0);
		wmsStockInOrders.setTotalDefectiveQuantity(0);
		List<WmsStockInOrderItems> items = mergePlannedItems(wmsStockInOrderItemsList);
		long total = items.stream().mapToLong(WmsStockInOrderItems::getExpectedQuantity).sum();
		wmsStockInOrders.setTotalExpectedQuantity(Math.toIntExact(total));
		wmsStockInOrdersMapper.insert(wmsStockInOrders);
		insertPlannedItems(items, wmsStockInOrders.getId());
	}
	/**
	 * 审核入库单
	 * @param wmsStockInOrdersPage
	 */
	@Transactional(rollbackFor = Exception.class)
	public void audit(WmsStockInOrdersPage wmsStockInOrdersPage){
		freshAccessService.requireStaff();
		//如果没有选择入库单则返回错误
		if(oConvertUtils.isEmpty(wmsStockInOrdersPage.getId())){
			//抛出异常
			throw new JeecgBootException("请选择要审核的入库单");
		}
		WmsStockInOrders wmsStockInOrdersEntity = lockById(wmsStockInOrdersPage.getId());
		if(wmsStockInOrdersEntity==null) {
			//异常
			throw new JeecgBootException("入库单不存在");
		}
		//入库单明细
		List<WmsStockInOrderItems> wmsStockInOrderItemsList = stockInOrderItemsService.selectByMainId(wmsStockInOrdersPage.getId());
		if(wmsStockInOrderItemsList==null || wmsStockInOrderItemsList.size()<=0){
			//异常
			throw new JeecgBootException("请添加入库明细");
		}
		if (WarehouseDictEnum.INBOUND_APPROVED.getCode().equals(wmsStockInOrdersPage.getStatus())) {
			for (WmsStockInOrderItems item : wmsStockInOrderItemsList) {
				validatePlannedFacts(wmsStockInOrdersEntity, item);
			}
		}
		if (!(WarehouseDictEnum.INBOUND_APPROVED.getCode().equals(wmsStockInOrdersPage.getStatus())
				|| WarehouseDictEnum.INBOUND_REJECTED.getCode().equals(wmsStockInOrdersPage.getStatus()))) {
			throw new JeecgBootException("审核结果状态无效");
		}
		//当前状态只能是提交审核状态
		if(!WarehouseDictEnum.INBOUND_SUBMIT_AUDIT.getCode().equals(wmsStockInOrdersEntity.getStatus())){
			//异常
			throw new JeecgBootException("当前状态是提交审核状态方可进行审核");
		}
		//更新状态为审核通过或审核不通过
		wmsStockInOrdersEntity.setStatus(wmsStockInOrdersPage.getStatus());
		updateById(wmsStockInOrdersEntity);
	}
	/**
	 * 提交审核
	 * @param wmsStockInOrdersPage
	 */
	@Transactional(rollbackFor = Exception.class)
	public void submitAudit(WmsStockInOrdersPage wmsStockInOrdersPage){
		freshAccessService.requireStaff();
		//如果没有选择入库单则返回错误
		if(wmsStockInOrdersPage==null || oConvertUtils.isEmpty(wmsStockInOrdersPage.getId())){
			//抛出异常
			throw new JeecgBootException("请选择要审核的入库单");
		}
		WmsStockInOrders wmsStockInOrdersEntity = lockById(wmsStockInOrdersPage.getId());
		if(wmsStockInOrdersEntity==null) {
			//异常
			throw new JeecgBootException("入库单不存在");
		}
		//当前状态只能是初始状态、审核失败状态
		if(!(WarehouseDictEnum.INBOUND_INITIAL.getCode().equals(wmsStockInOrdersEntity.getStatus())
				|| WarehouseDictEnum.INBOUND_REJECTED.getCode().equals(wmsStockInOrdersEntity.getStatus()))){
			throw new JeecgBootException("非初始状态、审核失败状态入库单不允许审核");
		}
		//更新状态为提交审核
		wmsStockInOrdersEntity.setStatus(WarehouseDictEnum.INBOUND_SUBMIT_AUDIT.getCode());
		updateById(wmsStockInOrdersEntity);
	}
	@Override
	@Transactional(rollbackFor = Exception.class)
	public void updateMain(WmsStockInOrders wmsStockInOrders,List<WmsStockInOrderItems> wmsStockInOrderItemsList) {
		freshAccessService.requireStaff();
		WmsStockInOrders existing = lockById(wmsStockInOrders.getId());
        if (existing == null) {
            throw new JeecgBootException("入库单不存在");
        }
        if (!(WarehouseDictEnum.INBOUND_INITIAL.getCode().equals(existing.getStatus())
                || WarehouseDictEnum.INBOUND_REJECTED.getCode().equals(existing.getStatus()))) {
            throw new JeecgBootException("非初始状态、审核失败状态入库单不允许修改");
        }
        if (wmsStockInOrderItemsList == null || wmsStockInOrderItemsList.isEmpty()) {
            throw new JeecgBootException("请选择入库单明细");
        }
        wmsStockInOrders.setStatus(existing.getStatus());
        wmsStockInOrders.setOrderNumber(existing.getOrderNumber());
        wmsStockInOrders.setTotalReceivedQuantity(existing.getTotalReceivedQuantity());
        wmsStockInOrders.setTotalShelvedQuantity(existing.getTotalShelvedQuantity());
        wmsStockInOrders.setTotalDefectiveQuantity(existing.getTotalDefectiveQuantity());
        if (wmsStockInOrders.getSupplierId() == null) {
            wmsStockInOrders.setSupplierId(existing.getSupplierId());
        }
        validateProducts(wmsStockInOrders, wmsStockInOrderItemsList,
                stockInOrderItemsService.selectByMainId(existing.getId()));
        List<WmsStockInOrderItems> items = mergePlannedItems(wmsStockInOrderItemsList);
        long total = items.stream().mapToLong(WmsStockInOrderItems::getExpectedQuantity).sum();
        wmsStockInOrders.setTotalExpectedQuantity(Math.toIntExact(total));
        wmsStockInOrdersMapper.updateById(wmsStockInOrders);
        wmsStockInOrderItemsMapper.deleteByMainId(existing.getId());
        insertPlannedItems(items, existing.getId());
    }

    private List<WmsStockInOrderItems> mergePlannedItems(List<WmsStockInOrderItems> items) {
        Map<InboundBatchKey, WmsStockInOrderItems> merged = new LinkedHashMap<>();
        for (WmsStockInOrderItems item : items) {
            merged.merge(batchKey(item), item, (first, next) -> {
                if (!first.getProductionDate().equals(next.getProductionDate())
                        || !first.getExpiryDate().equals(next.getExpiryDate())) {
                    throw new JeecgBootException("相同食材和批号不能使用不同的生产或到期日期");
                }
                first.setExpectedQuantity(Math.addExact(first.getExpectedQuantity(), next.getExpectedQuantity()));
                return first;
            });
        }
        return List.copyOf(merged.values());
    }

    private InboundBatchKey batchKey(WmsStockInOrderItems item) {
        String label = item.getBatchNumber();
        return new InboundBatchKey(item.getProductId(), label == null ? null : label.toLowerCase(Locale.ROOT));
    }

    private void insertPlannedItems(List<WmsStockInOrderItems> items, String orderId) {
        for (WmsStockInOrderItems item : items) {
            resetItemProgress(item, orderId);
            wmsStockInOrderItemsMapper.insert(item);
        }
    }

	private void resetItemProgress(WmsStockInOrderItems item, String orderId) {
		item.setId(null);
		item.setOrderId(orderId);
		item.setReceivedQuantity(0);
		item.setShelvedQuantity(0);
		item.setDefectiveQuantity(0);
		item.setStatus(WarehouseDictEnum.INBOUND_DETAIL_INITIAL.getCode());
	}

    /** Disabled products may retain/reduce existing commitments, but cannot create new ones.
     * Compare persisted product totals, never caller-supplied item IDs.
     */
    private void validateProducts(WmsStockInOrders order, List<WmsStockInOrderItems> items,
                                  List<WmsStockInOrderItems> existingItems) {
        Map<InboundBatchKey, Long> previous = new HashMap<>();
        for (WmsStockInOrderItems item : existingItems) {
			previous.merge(batchKey(item), (long) item.getExpectedQuantity(), Long::sum);
        }
        Map<InboundBatchKey, Long> requested = new HashMap<>();
        if (items == null) { return; }
		if (order.getSupplierId() == null || order.getSupplierId().isBlank()) {
			throw new JeecgBootException("请选择入库供应商");
		}
		FreshSupplier supplier = supplierService.getById(order.getSupplierId());
		if (supplier == null || !"ACTIVE".equals(supplier.getStatus())) {
			throw new JeecgBootException("供应商不存在或已停用");
		}
        for (WmsStockInOrderItems item : items) {
            if (item == null || item.getProductId() == null || item.getProductId().isBlank()) {
                throw new JeecgBootException("入库食材不能为空");
            }
            if (item.getExpectedQuantity() == null || item.getExpectedQuantity() <= 0) {
                throw new JeecgBootException("入库计划数量必须为正整数");
            }
			if (item.getBatchNumber() == null || item.getBatchNumber().isBlank()
					|| item.getProductionDate() == null || item.getExpiryDate() == null
					|| !item.getExpiryDate().isAfter(item.getProductionDate())) {
				throw new JeecgBootException("每条入库明细须填写批号、生产日期及晚于生产日期的到期日期");
			}
            item.setBatchNumber(FreshValidation.text(item.getBatchNumber(), "批号", 32));
			requested.merge(batchKey(item), (long) item.getExpectedQuantity(), Long::sum);
        }
		for (Map.Entry<InboundBatchKey, Long> entry : requested.entrySet()) {
			String productId = entry.getKey().productId();
			WmsProducts product = productsService.getById(productId);
            if (product == null || !Objects.equals(product.getOwnerId(), order.getOwnerId())) {
                throw new JeecgBootException("入库食材不存在或不属于该货主");
            }
            if (!"ACTIVE".equals(product.getStatus()) && entry.getValue() > previous.getOrDefault(entry.getKey(), 0L)) {
                throw new JeecgBootException("禁用食材不能新增入库业务或增加计划数量");
            }
            if (entry.getValue() > Integer.MAX_VALUE) {
                throw new JeecgBootException("入库计划数量超出整数上限");
            }
        }
        if (requested.values().stream().mapToLong(Long::longValue).sum() > Integer.MAX_VALUE) {
            throw new JeecgBootException("入库计划总量超出整数上限");
        }
    }

	@Override
	@Transactional(rollbackFor = Exception.class)
	public void delMain(String id) {
		freshAccessService.requireStaff();
		assertDraftDeletable(id);
		wmsStockInOrderItemsMapper.deleteByMainId(id);
		wmsStockInOrdersMapper.deleteById(id);
	}

	@Override
	@Transactional(rollbackFor = Exception.class)
	public void delBatchMain(Collection<? extends Serializable> idList) {
		freshAccessService.requireStaff();
		for(Serializable id:idList) {
			assertDraftDeletable(id.toString());
			wmsStockInOrderItemsMapper.deleteByMainId(id.toString());
			wmsStockInOrdersMapper.deleteById(id);
		}
	}

	private void assertDraftDeletable(String id) {
		WmsStockInOrders order = getById(id);
		if (order == null) { return; }
		if (!(WarehouseDictEnum.INBOUND_INITIAL.getCode().equals(order.getStatus())
				|| WarehouseDictEnum.INBOUND_REJECTED.getCode().equals(order.getStatus()))) {
			throw new JeecgBootException("已提交或执行的入库单不能删除");
		}
		Long taskCount = jdbcTemplate.queryForObject(
				"SELECT COUNT(*) FROM wms_tasks WHERE stock_in_order_id = ?", Long.class, id);
		if (taskCount != null && taskCount > 0) {
			throw new JeecgBootException("入库单已被任务引用，不能删除");
		}
	}

	@Override
	public String updateReceivedStatus(String stockInOrderId) {

		/**
		 1.根据入库单id查询入库单明细列表
		 2.计算良品总数和不良品总数
		 3.如果入库单明细全部完成收货则入库单状态为完成收货
		 */
		WmsStockInOrders stockInOrdersUpdate = getById(stockInOrderId);
		if(stockInOrdersUpdate==null) {
			//异常
			throw new JeecgBootException("入库单不存在");
		}
		//当前状态只有是收货中或审核通过时方可更新收货状态
		if(!(WarehouseDictEnum.INBOUND_RECEIVING.getCode().equals(stockInOrdersUpdate.getStatus())
				|| WarehouseDictEnum.INBOUND_APPROVED.getCode().equals(stockInOrdersUpdate.getStatus()))){
			throw new JeecgBootException("非收货中、审核通过状态入库单不允许更新收货状态");
		}
		//根据入库单id查询所有入库单明细的完成数量总和
		List<WmsStockInOrderItems> stockInOrderItems = stockInOrderItemsService.selectByMainId(stockInOrderId);
		//使用stream流汇总stockInOrderItems中完成收货数量总和
		int totalCompletedQuantity = stockInOrderItems.stream().mapToInt(WmsStockInOrderItems::getReceivedQuantity).sum();
		//不良品数量
		int totalBadQuantity = stockInOrderItems.stream().mapToInt(WmsStockInOrderItems::getDefectiveQuantity).sum();
		//入库单明细中只要存在一个状态是未完成收货则入库单的状态为收货中
		boolean b = stockInOrderItems.stream().anyMatch(item -> !WarehouseDictEnum.INBOUND_DETAIL_RECEIVED.getCode().equals(item.getStatus()));
		//新状态
		String status = null;
		if(b){
			status = WarehouseDictEnum.INBOUND_RECEIVING.getCode();
			stockInOrdersUpdate.setStatus(WarehouseDictEnum.INBOUND_RECEIVING.getCode());
		}else{
			status = WarehouseDictEnum.INBOUND_RECEIVED.getCode();
			stockInOrdersUpdate.setStatus(WarehouseDictEnum.INBOUND_RECEIVED.getCode());
		}
		stockInOrdersUpdate.setTotalReceivedQuantity(totalCompletedQuantity);
		stockInOrdersUpdate.setTotalDefectiveQuantity(totalBadQuantity);
		boolean update = updateById(stockInOrdersUpdate);
		if(!update){
			throw new JeecgBootException("更新入库单收货状态失败");
		}
		return status;
	}
	/**
	 *  更新上架完成状态
	 *  @param stockInOrderId 入库单id
	 * @return 更新后的入库单状态
	 */
	public String updatePutawayStatus(String stockInOrderId){
		//根据入库单id查询所有入库单明细的完成数量总和
		List<WmsStockInOrderItems> stockInOrderItems = stockInOrderItemsService.selectByMainId(stockInOrderId);
		//使用stream流汇总stockInOrderItems中完成数量总和
		int totalCompletedQuantity = stockInOrderItems.stream().mapToInt(WmsStockInOrderItems::getShelvedQuantity).sum();
		//将完成数量更新至入库单
		WmsStockInOrders stockInOrdersUpdate = getById(stockInOrderId);
		stockInOrdersUpdate.setTotalShelvedQuantity(totalCompletedQuantity);
		//入库单状态更新,入库单状态更新为上架完成
		String status = totalCompletedQuantity == stockInOrdersUpdate.getTotalReceivedQuantity()
				? WarehouseDictEnum.INBOUND_PUTAWAYED.getCode()
				: WarehouseDictEnum.INBOUND_PUTAWAYING.getCode();
		stockInOrdersUpdate.setStatus(status);

		boolean b = updateById(stockInOrdersUpdate);
		if(b){
			//返回入库单状态
			return status;
		}
		//异常
		throw new JeecgBootException("更新入库单上架完成状态失败");
	}
}
