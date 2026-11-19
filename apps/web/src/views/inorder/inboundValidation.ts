import { InboundBusinessError } from './inboundRequest';

const MAX_WMS_QUANTITY = 2147483647;
const shanghaiDate = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit' });

export function getInboundQuantityError(value: unknown, planned?: number, completed?: number): string | undefined {
  // JVxe number cells can supply digit strings until the editor is blurred.
  const quantity = typeof value === 'string' && /^\d+$/.test(value) ? Number(value) : value;
  if (typeof quantity !== 'number' || !Number.isInteger(quantity) || quantity < 1 || quantity > MAX_WMS_QUANTITY) {
    return '数量须为 1 至 2147483647 的整数';
  }
  if (typeof planned === 'number' && typeof completed === 'number' && quantity > planned - completed) {
    return `数量不能超过剩余待处理数量（${Math.max(0, planned - completed)}）`;
  }
}

export function getReceiptDateError(productionDate?: string, expiryDate?: string, today = shanghaiDate.format(new Date())) {
  if (productionDate && productionDate > today) return '生产日期不得晚于收货日期';
  if (expiryDate && expiryDate <= today) return '到期日期须晚于收货日期';
}

export function normalizeInboundPlan<T extends Recordable>(plan: T) {
  if (!plan.supplierId) throw new InboundBusinessError('请选择供应商');
  const items = plan.wmsStockInOrderItemsList;
  if (!Array.isArray(items) || items.length === 0) throw new InboundBusinessError('请至少添加一条入库明细');
  let total = 0;
  const details = items.map((item, index) => {
    const line = `第 ${index + 1} 条明细`;
    const error = getInboundQuantityError(item.expectedQuantity);
    if (error) throw new InboundBusinessError(`${line}：${error}`);
    const batchNumber = item.batchNumber?.trim();
    if (!item.productId || !batchNumber || !item.productionDate || !item.expiryDate) {
      throw new InboundBusinessError(`${line}：请填写商品、批次号、生产日期和到期日期`);
    }
    if (item.expiryDate <= item.productionDate) throw new InboundBusinessError(`${line}：到期日期须晚于生产日期`);
    const expectedQuantity = Number(item.expectedQuantity);
    total += expectedQuantity;
    return { ...item, batchNumber, expectedQuantity };
  });
  if (total > MAX_WMS_QUANTITY) {
    throw new InboundBusinessError('入库单计划总数量不能超过 2147483647');
  }
  return { ...plan, wmsStockInOrderItemsList: details };
}
