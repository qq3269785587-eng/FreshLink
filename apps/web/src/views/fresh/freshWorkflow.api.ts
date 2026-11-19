import { defHttp } from '/@/utils/http/axios';
import { options as storeOptions } from './stores/FreshStore.api';
import { list as inventoryList } from '../inventory/WmsInventory.api';

export interface Page<T> {
  records: T[];
  total: number;
}
export interface LotSnapshot {
  id: string;
  inventoryId: string;
  stockBatchKey: string;
  productName: string;
  productSpec?: string;
  supplierName?: string;
  batchNumber: string;
  locationCode: string;
  expiryDate: string;
  unit?: string;
  quantity: number;
}
export interface OutboundOrder {
  id: string;
  orderNumber: string;
  storeId: string;
  storeName: string;
  status: 'DRAFT' | 'CONFIRMED';
  confirmedAt?: string;
}
export interface OutboundDetail {
  order: OutboundOrder;
  lines: LotSnapshot[];
  deliveryId?: string;
}
export interface OutboundDraft {
  storeId: string;
  lines: Pick<LotSnapshot, 'inventoryId' | 'stockBatchKey' | 'quantity'>[];
}
export interface DispatchInfo {
  driverName: string;
  driverPhone: string;
  remark?: string;
}
export interface Delivery extends Partial<DispatchInfo> {
  id: string;
  outboundNumber: string;
  storeName: string;
  storeAddress: string;
  status: 'PENDING' | 'IN_TRANSIT' | 'DELIVERED';
  createdAt?: string;
  dispatchBy?: string;
  dispatchAt?: string;
  deliveredBy?: string;
  deliveredAt?: string;
  items?: LotSnapshot[];
}

interface Result<T> {
  success: boolean;
  message?: string;
  result?: T;
}
function unwrap<T>(result: Result<T>): T {
  if (!result?.success) throw new Error(result?.message || '操作未成功，请重试');
  return result.result as T;
}
const raw = { isTransformResponse: false };
const outbound = '/fresh/outbounds';
const delivery = '/fresh/deliveries';
const item = (base: string, id: string) => `${base}/${encodeURIComponent(id)}`;
const get = async <T>(url: string, params?: Record<string, unknown>) => unwrap(await defHttp.get<Result<T>>({ url, params }, raw));
const post = async <T>(url: string, data?: unknown) => unwrap(await defHttp.post<Result<T>>({ url, data }, raw));
const put = async <T>(url: string, data: unknown) => unwrap(await defHttp.put<Result<T>>({ url, data }, raw));

export const listOutbounds = (params: { pageNo: number; pageSize: number; stockBatchKey?: string }) =>
  get<Page<OutboundOrder>>(outbound, params);
export const getOutbound = (id: string) => get<OutboundDetail>(item(outbound, id));
export const saveOutbound = (draft: OutboundDraft, id?: string) =>
  id ? put<OutboundDetail>(item(outbound, id), draft) : post<OutboundDetail>(outbound, draft);
export const deleteOutbound = async (id: string) => unwrap(await defHttp.delete<Result<string>>({ url: item(outbound, id) }, raw));
export const confirmOutbound = (id: string) => post<OutboundDetail>(`${item(outbound, id)}/confirm`);

export const listDeliveries = (params: { pageNo: number; pageSize: number }) => get<Page<Delivery>>(delivery, params);
export const getDelivery = (id: string) => get<Delivery>(item(delivery, id));
export const saveDispatch = (id: string, info: DispatchInfo) => put<Delivery>(`${item(delivery, id)}/dispatch-info`, info);
export const startDelivery = (id: string) => post<Delivery>(`${item(delivery, id)}/start`);
export const finishDelivery = (id: string) => post<Delivery>(`${item(delivery, id)}/deliver`);

export async function loadStoreOptions(): Promise<{ value: string; label: string }[]> {
  const stores: { id: string; storeName: string }[] = await storeOptions();
  return stores.map((store) => ({ value: store.id, label: store.storeName }));
}

export interface InventoryBatch extends Omit<LotSnapshot, 'quantity' | 'inventoryId'> {
  eligibleQuantity?: number;
}

export async function loadInventoryBatches(): Promise<InventoryBatch[]> {
  const batches: InventoryBatch[] = [];
  const pageSize = 100;
  let pageNo = 1;
  while (true) {
    const result: Page<InventoryBatch> = await inventoryList({ pageNo, pageSize });
    batches.push(...result.records.filter((batch) => batch.stockBatchKey));
    if (result.records.length === 0 || pageNo * pageSize >= result.total) return batches;
    pageNo++;
  }
}
