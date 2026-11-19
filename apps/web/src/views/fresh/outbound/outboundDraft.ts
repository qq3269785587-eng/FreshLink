export interface OutboundBatchOption {
  id: string;
  label: string;
  eligibleQuantity: number;
}

export interface OutboundDraftLine {
  batchId?: string;
  quantity?: number;
}

export function canSelectBatch(eligibleQuantity: number | undefined): boolean {
  return Number.isInteger(eligibleQuantity) && (eligibleQuantity ?? 0) > 0;
}

export function validateOutboundDraft(storeId: string | undefined, lines: OutboundDraftLine[], batches: OutboundBatchOption[]): string | undefined {
  if (!storeId) return '请选择配送门店';
  if (!lines.length) return '请添加至少一条出库明细';
  if (lines.length > 100) return '每张出库草稿最多 100 条明细';

  const limits = new Map(batches.map((batch) => [batch.id, batch]));
  const totals = new Map<string, number>();
  for (const [index, line] of lines.entries()) {
    const title = `第 ${index + 1} 行`;
    const batch = line.batchId ? limits.get(line.batchId) : undefined;
    if (!batch) return `${title}请选择库存批次`;
    const quantity = line.quantity;
    if (typeof quantity !== 'number' || !Number.isInteger(quantity) || quantity < 1 || quantity > 2147483647) {
      return `${title}的出库数量须为 1 至 2147483647 的整数`;
    }
    const total = (totals.get(batch.id) ?? 0) + quantity;
    if (!canSelectBatch(batch.eligibleQuantity) || total > batch.eligibleQuantity) {
      return `${batch.label}的合计出库数量超过可出库量（${batch.eligibleQuantity}）`;
    }
    totals.set(batch.id, total);
  }
}
