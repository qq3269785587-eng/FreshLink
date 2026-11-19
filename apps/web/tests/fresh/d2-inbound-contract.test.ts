import { defHttp } from '/@/utils/http/axios';
import { listInboundProductOptions, saveOrUpdate } from '/@/views/inorder/WmsStockInOrders.api';
import { listFormalPutawayTargets, listReceivingTargets, putaway, receive } from '/@/views/inorder/WmsTasks.api';
import { createInboundActionSubmitter } from '/@/views/inorder/inboundRequest';
import { detail, list } from '/@/views/inventory/WmsInventory.api';
import { getExpiryPresentation, getInventoryBlockReason } from '/@/views/inventory/inventoryExpiry';

jest.mock('/@/utils/http/axios', () => ({ defHttp: { get: jest.fn(), post: jest.fn(), put: jest.fn() } }));
jest.mock('/@/hooks/web/useMessage', () => ({ useMessage: () => ({ createConfirm: jest.fn() }) }));

const get = defHttp.get as jest.Mock;
const post = defHttp.post as jest.Mock;
const put = defHttp.put as jest.Mock;

test('入库商品跨页查询同货主商品并保留停用明细的名称', async () => {
  const active = { id: 'P01', productName: '鸡胸肉', ownerId: 'OWNER', status: 'ACTIVE' };
  const inactive = { id: 'P02', productName: '停用商品', ownerId: 'OWNER', status: 'INACTIVE' };
  const otherOwner = { id: 'OTHER', productName: '其他货主', ownerId: 'OTHER', status: 'ACTIVE' };
  get.mockResolvedValueOnce({ records: [active], total: 101 });
  get.mockResolvedValueOnce({ records: [inactive, otherOwner], total: 101 });

  await expect(listInboundProductOptions('OWNER')).resolves.toEqual([
    { value: 'P01', label: '鸡胸肉', disabled: false },
    { value: 'P02', label: '停用商品', disabled: true },
  ]);
  expect(get).toHaveBeenLastCalledWith({ url: '/goods/wmsProducts/list', params: { ownerId: 'OWNER', pageNo: 2, pageSize: 100 } });
});

test('入库单创建和更新按合同提交供应商、批次及日期，保留后端业务错误', async () => {
  const item = { productId: 'P01', expectedQuantity: 10, batchNumber: 'B1', productionDate: '2026-11-17', expiryDate: '2026-11-21' };
  const plan = { supplierId: 'S01', wmsStockInOrderItemsList: [item] };
  post.mockResolvedValueOnce({ success: true, result: 'saved' });
  put.mockResolvedValueOnce({ code: 200, success: false, message: '供应商不存在或已停用' });

  await expect(saveOrUpdate(plan, false)).resolves.toBe('saved');
  expect(post).toHaveBeenLastCalledWith({ url: '/inorder/wmsStockInOrders/add', data: plan }, { isTransformResponse: false });
  await expect(saveOrUpdate({ ...plan, id: 'I01' }, true)).rejects.toThrow('供应商不存在或已停用');
  expect(put).toHaveBeenLastCalledWith({ url: '/inorder/wmsStockInOrders/edit', data: { ...plan, id: 'I01' } }, { isTransformResponse: false });
});

test('收货重试复用请求键，后续分次动作使用新键', async () => {
  const perform = createInboundActionSubmitter(receive);
  const fields = { id: 'T01', execQuantity: 4, targetLocationCode: 'R1' };
  post.mockRejectedValueOnce(new Error('连接超时'));
  post.mockResolvedValueOnce({ success: true });
  post.mockResolvedValueOnce({ success: true });

  await expect(perform(fields)).rejects.toThrow('连接超时');
  await perform(fields);
  await perform(fields);
  const [first, retry, next] = post.mock.calls.map(([config]) => config.data);
  expect(post.mock.calls[0][0].url).toBe('/inorder/receiveTasks/addRecords');
  expect(first).toEqual({ ...fields, requestKey: expect.any(String) });
  expect(retry).toEqual(first);
  expect(next.requestKey).not.toBe(first.requestKey);
});

test('上架保留温区和角色拒绝提示', async () => {
  const fields = { id: 'T02', execQuantity: 4, targetLocationCode: 'C1', requestKey: 'request-1' };
  post.mockResolvedValueOnce({ success: false, message: '上架储位温区与食材温区不一致' });
  post.mockResolvedValueOnce({ code: 403, success: false, message: '仅总部和仓管可操作' });

  await expect(putaway(fields)).rejects.toThrow('上架储位温区与食材温区不一致');
  await expect(putaway(fields)).rejects.toThrow('仅总部和仓管可操作');
  expect(post).toHaveBeenLastCalledWith(
    { url: '/inorder/putawayTasks/addRecords', data: fields },
    { isTransformResponse: false },
  );
});

test('库存从列表和详情读取服务端效期和出库数量', async () => {
  const row = { id: 'INV01', expiryStatus: 'EXPIRED', remainingDays: 0, availableQuantity: 10, eligibleQuantity: 0 };
  get.mockResolvedValueOnce({ records: [row], total: 1 });
  get.mockResolvedValueOnce(row);
  await expect(list({ pageNo: 1, productName: '鸡胸肉' })).resolves.toEqual({ records: [row], total: 1 });
  await expect(detail(row.id)).resolves.toEqual(row);
  expect(get).toHaveBeenLastCalledWith({ url: '/inventory/wmsInventory/queryById', params: { id: row.id } });
  expect(['NORMAL', 'NEAR_EXPIRY', 'EXPIRED', 'PENDING_VERIFICATION'].map((status) => getExpiryPresentation(status).text))
    .toEqual(['正常', '临期', '过期', '待核验']);
  expect(getInventoryBlockReason(row)).toBe('批次已到期');
  expect(getInventoryBlockReason({ expiryStatus: 'NORMAL', eligibleQuantity: 0, locationType: 'RECEIVING_LOC' }))
    .toBe('未进入正式储位');
});

test('收货选择启用的收货位，上架选择启用的可售正式储位', async () => {
  const active = { status: 'ACTIVE', warehouse: { status: 'ACTIVE' }, storageZones: { status: 'ACTIVE' } };
  const receiving = { ...active, locationCode: 'R1', locationType: 'RECEIVING_LOC', isSellable: '0' };
  const formal = { ...active, locationCode: 'C1', locationType: 'STORAGE_LOC', isSellable: '1' };
  const page = { total: 3, records: [receiving, formal, { ...formal, locationCode: 'C2', isSellable: '0' }] };
  get.mockResolvedValueOnce(page);
  get.mockResolvedValueOnce(page);
  await expect(listReceivingTargets({ warehouseId: 'W01' })).resolves.toEqual([receiving]);
  await expect(listFormalPutawayTargets({ warehouseId: 'W01' })).resolves.toEqual([formal]);
});
