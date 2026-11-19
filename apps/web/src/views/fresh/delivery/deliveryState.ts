export const deliveryLabels: Record<string, string> = {
  PENDING: '待配送',
  IN_TRANSIT: '配送中',
  DELIVERED: '已送达',
};
export function normalizeDriver(info: { driverName?: string; driverPhone?: string; remark?: string }) {
  const driverName = info.driverName?.trim();
  const driverPhone = info.driverPhone?.trim();
  if (!driverName || !driverPhone) return;
  return { driverName, driverPhone, remark: info.remark?.trim() ?? '' };
}
export function hasSavedDriver(info: { driverName?: string; driverPhone?: string }) {
  return Boolean(normalizeDriver(info));
}
