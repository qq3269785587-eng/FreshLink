jest.mock('/@/components/Table', () => ({}));

import { formSchema as supplierSchema } from '/@/views/fresh/suppliers/FreshSupplier.data';
import { formSchema as storeSchema } from '/@/views/fresh/stores/FreshStore.data';

function field(schema: any[], name: string) {
  return schema.find((item) => item.field === name);
}

describe('P1 fresh master-data form contract', () => {
  test('supplier requires a unique code, name and dictionary-backed status', () => {
    expect(field(supplierSchema, 'supplierCode')?.dynamicRules?.()).toEqual(
      expect.arrayContaining([expect.objectContaining({ required: true })]),
    );
    expect(field(supplierSchema, 'supplierName')?.dynamicRules?.()).toEqual(
      expect.arrayContaining([expect.objectContaining({ required: true })]),
    );
    expect(field(supplierSchema, 'status')?.componentProps?.dictCode).toBe('fresh_enabled_status');
  });

  test('store requires code, name and address', () => {
    for (const name of ['storeCode', 'storeName', 'address']) {
      expect(field(storeSchema, name)?.dynamicRules?.()).toEqual(
        expect.arrayContaining([expect.objectContaining({ required: true })]),
      );
    }
  });
});
