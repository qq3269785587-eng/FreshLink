const expiryPresentation = {
  NORMAL: { text: '正常', color: 'green' },
  NEAR_EXPIRY: { text: '临期', color: 'orange' },
  EXPIRED: { text: '过期', color: 'red' },
  PENDING_VERIFICATION: { text: '待核验', color: 'default' },
};

export function getExpiryPresentation(status?: string) {
  return expiryPresentation[status ?? ''] ?? { text: '—', color: 'default' };
}

interface InventoryEligibility {
  expiryStatus?: string;
  eligibleQuantity?: number;
  productStatus?: string;
  locationType?: string;
  isSellable?: string;
  availableQuantity?: number;
}

export function getInventoryBlockReason(inventory: InventoryEligibility) {
  if (inventory.eligibleQuantity !== 0) return '—';
  if (inventory.expiryStatus === 'EXPIRED') return '批次已到期';
  if (inventory.expiryStatus === 'PENDING_VERIFICATION') return '批次来源或日期待核验';
  if (inventory.productStatus && inventory.productStatus !== 'ACTIVE') return '食材未启用';
  if (inventory.locationType && !['STORAGE_LOC', 'PICKING_LOC'].includes(inventory.locationType)) return '未进入正式储位';
  if (inventory.isSellable === '0') return '库存不可售';
  if (inventory.availableQuantity === 0) return '无账面未分配量';
  return '当前库存不符合出库条件';
}
