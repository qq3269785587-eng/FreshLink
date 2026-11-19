import { defHttp } from '/@/utils/http/axios';
import {
  confirmOutbound, finishDelivery, listOutbounds, loadInventoryBatches, saveDispatch, saveOutbound, startDelivery,
} from '/@/views/fresh/freshWorkflow.api';
import { canSelectBatch, validateOutboundDraft } from '/@/views/fresh/outbound/outboundDraft';
import { deliveryLabels, normalizeDriver } from '/@/views/fresh/delivery/deliveryState';
import { canWriteFreshWorkflow } from '/@/views/fresh/freshWorkflowAccess';

jest.mock('/@/utils/http/axios', () => ({ defHttp: { get: jest.fn(), post: jest.fn(), put: jest.fn() } }));
jest.mock('/@/hooks/web/useMessage', () => ({ useMessage: () => ({ createConfirm: jest.fn() }) }));
jest.mock('/@/store/modules/permission', () => ({ usePermissionStore: jest.fn() }));

const get = defHttp.get as jest.Mock;
const post = defHttp.post as jest.Mock;
const put = defHttp.put as jest.Mock;
const raw = { isTransformResponse: false };

test('使用后台授予的操作权限向仓管展示出库和配送写动作，门店只读', () => {
  expect(canWriteFreshWorkflow(['outorder:wms_out_orders:add'])).toBe(true);
  expect(canWriteFreshWorkflow(['fresh:store:my'])).toBe(false);
  expect(canWriteFreshWorkflow([])).toBe(false);
});

test('出库草稿按库存记录 ID 和库存批次键提交，业务失败保留原消息', async () => {
  const draft = { storeId: 'A', lines: [{ inventoryId: 'I', stockBatchKey: 'FL:B1', quantity: 6 }] };
  post.mockResolvedValueOnce({ success: true, result: { order: { status: 'DRAFT' } } });
  put.mockResolvedValueOnce({ success: true, result: { order: { status: 'DRAFT' } } });
  post.mockResolvedValueOnce({ success: false, message: '第 2 行库存不足' });
  await saveOutbound(draft);
  expect(post).toHaveBeenLastCalledWith({ url: '/fresh/outbounds', data: draft }, raw);
  await saveOutbound(draft, 'O');
  expect(put).toHaveBeenLastCalledWith({ url: '/fresh/outbounds/O', data: draft }, raw);
  await expect(confirmOutbound('O')).rejects.toThrow('第 2 行库存不足');
  expect(post).toHaveBeenLastCalledWith({ url: '/fresh/outbounds/O/confirm', data: undefined }, raw);
});

test('按库存批次键查询出库，并使用 D2 可出库量', async () => {
  const params = { pageNo: 1, pageSize: 10, stockBatchKey: 'FL:B1' };
  get.mockResolvedValueOnce({ success: true, result: { records: [], total: 0 } });
  await listOutbounds(params);
  expect(get).toHaveBeenLastCalledWith({ url: '/fresh/outbounds', params }, raw);
  const records = [{ id: 'I', stockBatchKey: 'FL:B1', eligibleQuantity: 4, availableQuantity: 10 }, { id: 'old', availableQuantity: 4 }];
  get.mockResolvedValueOnce({ records, total: 2 });
  await expect(loadInventoryBatches()).resolves.toEqual([records[0]]);
  expect(canSelectBatch(0)).toBe(false);
  expect(canSelectBatch(undefined)).toBe(false);
});

test('出库数量须为正整数，同一库存行合计不得超出服务端口径', () => {
  const batches = [{ id: 'I', label: '鸡胸肉 B1', eligibleQuantity: 4 }];
  expect(validateOutboundDraft('A', [{ batchId: 'I', quantity: 4 }], batches)).toBeUndefined();
  expect(validateOutboundDraft('A', [{ batchId: 'I', quantity: 1.5 }], batches)).toMatch(/整数/);
  expect(validateOutboundDraft('A', [{ batchId: 'I', quantity: 3 }, { batchId: 'I', quantity: 2 }], batches)).toMatch(/合计.*4/);
  expect(validateOutboundDraft(undefined, [], batches)).toMatch(/门店/);
});

test('配送资料及状态动作使用独立接口，送达失败保留业务提示', async () => {
  const info = { driverName: '配送员', driverPhone: '123', remark: '' };
  expect(normalizeDriver({ driverName: ' 配送员 ', driverPhone: ' 123 ' })).toEqual(info);
  expect(normalizeDriver({ driverName: '配送员', driverPhone: ' ' })).toBeUndefined();
  put.mockResolvedValueOnce({ success: true, result: { status: 'PENDING' } });
  post.mockResolvedValueOnce({ success: true, result: { status: 'IN_TRANSIT' } });
  post.mockResolvedValueOnce({ success: false, message: '当前状态不可送达' });
  await saveDispatch('D', info);
  expect(put).toHaveBeenLastCalledWith({ url: '/fresh/deliveries/D/dispatch-info', data: info }, raw);
  await expect(startDelivery('D')).resolves.toEqual({ status: 'IN_TRANSIT' });
  expect(post).toHaveBeenLastCalledWith({ url: '/fresh/deliveries/D/start', data: undefined }, raw);
  await expect(finishDelivery('D')).rejects.toThrow('当前状态不可送达');
  expect(post).toHaveBeenLastCalledWith({ url: '/fresh/deliveries/D/deliver', data: undefined }, raw);
  expect(deliveryLabels.DELIVERED).toBe('已送达');
});
