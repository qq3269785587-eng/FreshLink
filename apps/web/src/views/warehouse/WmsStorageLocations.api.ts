import {defHttp} from '/@/utils/http/axios';
import { useMessage } from "/@/hooks/web/useMessage";

const { createConfirm } = useMessage();

enum Api {
  list = '/warehouse/wmsStorageLocations/list',
  save='/warehouse/wmsStorageLocations/add',
  edit='/warehouse/wmsStorageLocations/edit',
  deleteOne = '/warehouse/wmsStorageLocations/delete',
  deleteBatch = '/warehouse/wmsStorageLocations/deleteBatch',
  importExcel = '/warehouse/wmsStorageLocations/importExcel',
  exportXls = '/warehouse/wmsStorageLocations/exportXls',
  enable = '/warehouse/wmsStorageLocations/enable',
  disable = '/warehouse/wmsStorageLocations/disable',
}
/**
 * 导出api
 * @param params
 */
export const getExportUrl = Api.exportXls;
/**
 * 导入api
 */
export const getImportUrl = Api.importExcel;
/**
 * 列表接口
 * @param params
 */
export const list = (params) =>
  defHttp.get({url: Api.list, params});

export const setLocationEnabled = (id: string, enabled: boolean) =>
  defHttp.put({ url: enabled ? Api.enable : Api.disable, data: { id } });

interface PutawayLocation {
  locationCode: string;
  locationType: string;
  isSellable: string;
  status: string;
  warehouse?: { status: string };
  storageZones?: { status: string };
}

export async function listPutawayTargets({ warehouseId }: { warehouseId?: string } = {}) {
  if (!warehouseId) return [];
  const pageSize = 100;
  const targets: PutawayLocation[] = [];
  for (let pageNo = 1; ; pageNo++) {
    const { records, total } = await list({ warehouseId, status: 'ACTIVE', pageNo, pageSize });
    targets.push(
      ...records.filter((row: PutawayLocation) =>
        row.status === 'ACTIVE' && row.warehouse?.status === 'ACTIVE' && row.storageZones?.status === 'ACTIVE',
      ),
    );
    if (!records.length || pageNo * pageSize >= total) return targets;
  }
}
/**
 * 拣货储位列表接口
 * @param params
 */
export const listByPickType = (params) =>
  list({ ...params, locationType: 'PICKING_LOC' });

/**
 * 删除单个
 */
export const deleteOne = (params,handleSuccess) => {
  return defHttp.delete({url: Api.deleteOne, params}, {joinParamsToUrl: true}).then(() => {
    handleSuccess();
  });
}
/**
 * 批量删除
 * @param params
 */
export const batchDelete = (params, handleSuccess) => {
  createConfirm({
    iconType: 'warning',
    title: '确认删除',
    content: '是否删除选中数据',
    okText: '确认',
    cancelText: '取消',
    onOk: () => {
      return defHttp.delete({url: Api.deleteBatch, data: params}, {joinParamsToUrl: true}).then(() => {
        handleSuccess();
      });
    }
  });
}
/**
 * 保存或者更新
 * @param params
 */
export const saveOrUpdate = (params, isUpdate) => {
  let url = isUpdate ? Api.edit : Api.save;
  return defHttp.post({url: url, params});
}
