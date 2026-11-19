import { getReceiptDateError, getInboundQuantityError, normalizeInboundPlan } from '/@/views/inorder/inboundValidation';

test('收货和上架数量必须为正整数，采购数量支持数字单元格的整数字符串', () => {
  for (const invalid of [undefined, null, '', ' ', false, 0, -1, 1.5, '1.5', '1e2', 2147483648, '2147483648']) {
    expect(getInboundQuantityError(invalid)).toBe('数量须为 1 至 2147483647 的整数');
  }
  expect(getInboundQuantityError(1)).toBeUndefined();
  expect(getInboundQuantityError('12')).toBeUndefined();
  expect(getInboundQuantityError(2147483647)).toBeUndefined();
});

test('以任务计划减去已完成量提示剩余数量', () => {
  expect(getInboundQuantityError(3, 10, 7)).toBeUndefined();
  expect(getInboundQuantityError(4, 10, 7)).toBe('数量不能超过剩余待处理数量（3）');
  expect(getInboundQuantityError(1, 10, 10)).toBe('数量不能超过剩余待处理数量（0）');
});

test('收货当日到期及未来生产日期均不可提交', () => {
  expect(getReceiptDateError('2026-11-18', '2026-11-19', '2026-11-19')).toBe('到期日期须晚于收货日期');
  expect(getReceiptDateError('2026-11-20', '2026-11-21', '2026-11-19')).toBe('生产日期不得晚于收货日期');
  expect(getReceiptDateError('2026-11-19', '2026-11-20', '2026-11-19')).toBeUndefined();
});

test('入库计划写入实际 JSON 整数并限制整单计划总量', () => {
  const item = { productId: 'P01', batchNumber: ' B01 ', productionDate: '2026-11-18', expiryDate: '2026-11-21', expectedQuantity: '10' };
  const plan = { supplierId: 'S01', wmsStockInOrderItemsList: [item] };
  expect(normalizeInboundPlan(plan).wmsStockInOrderItemsList).toEqual([{ ...item, expectedQuantity: 10, batchNumber: 'B01' }]);
  expect(() => normalizeInboundPlan({ ...plan, wmsStockInOrderItemsList: [item, { ...item, expectedQuantity: 2147483647 }] }))
    .toThrow('入库单计划总数量不能超过 2147483647');
  expect(() => normalizeInboundPlan({ ...plan, wmsStockInOrderItemsList: [] })).toThrow('请至少添加一条入库明细');
});
