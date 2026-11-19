import { defHttp } from '/@/utils/http/axios';
import { listPutawayTargets } from '/@/views/warehouse/WmsStorageLocations.api';

jest.mock('/@/utils/http/axios', () => ({ defHttp: { get: jest.fn() } }));
jest.mock('/@/hooks/web/useMessage', () => ({ useMessage: () => ({ createConfirm: jest.fn() }) }));

const get = defHttp.get as jest.Mock;

test('上架选项跳过未启用的仓、区或储位，并仍能找到后续页的可用储位', async () => {
  const active = { status: 'ACTIVE', warehouse: { status: 'ACTIVE' }, storageZones: { status: 'ACTIVE' } };
  const eligible = { ...active, locationCode: '可用储位' };
  get
    .mockResolvedValueOnce({
      total: 101,
      records: [
        { ...active, locationCode: '禁用仓库', warehouse: { status: 'INACTIVE' } },
        { ...active, locationCode: '禁用库区', storageZones: { status: 'INACTIVE' } },
        { ...active, locationCode: '禁用储位', status: 'INACTIVE' },
      ],
    })
    .mockResolvedValueOnce({ total: 101, records: [eligible] });

  await expect(listPutawayTargets({ warehouseId: 'W01' })).resolves.toEqual([eligible]);
});
