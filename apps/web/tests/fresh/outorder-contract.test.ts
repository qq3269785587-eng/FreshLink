jest.mock('/@/utils/helper/validator', () => ({ rules: {} }));
jest.mock('/@/utils/common/renderUtils', () => ({ render: {} }));
jest.mock('@/views/warehouse/WmsWarehouses.api', () => ({ list: jest.fn() }));
jest.mock('/@/components/jeecg/JVxeTable/types', () => ({
  JVxeTypes: { input: 'input', inputNumber: 'inputNumber', select: 'select', popup: 'popup' },
}));

import { createWmsOutOrderItemsJVxeColumns } from '/@/views/outorder/WmsOutOrders.data';

describe('existing out-order item form contract', () => {
  const columns = createWmsOutOrderItemsJVxeColumns(() => ({ ownerId: 'OWNER-1' }));

  test('keeps the batch number as an editable field on each out-order item', () => {
    const batchColumn = columns.find((column) => column.key === 'batchNumber');

    expect(batchColumn).toBeDefined();
    expect(batchColumn?.type).toBe('input');
  });

  test('requires an expected quantity and prevents editing the workflow status', () => {
    const quantityColumn = columns.find((column) => column.key === 'expectedQuantity');
    const statusColumn = columns.find((column) => column.key === 'status');

    expect(quantityColumn?.validateRules).toEqual(
      expect.arrayContaining([expect.objectContaining({ required: true })]),
    );
    expect(statusColumn?.disabled).toBe(true);
  });
});
