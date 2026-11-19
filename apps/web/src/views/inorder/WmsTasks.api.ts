import { defHttp } from '/@/utils/http/axios';
import { useMessage } from '/@/hooks/web/useMessage';
import { listPutawayTargets } from '/@/views/warehouse/WmsStorageLocations.api';
import { type InboundActionRequest, requireInboundSuccess } from './inboundRequest';

const { createConfirm, createMessage } = useMessage();

enum Api {
  putawaylist = '/inorder/putawayTasks/list',
  receivelist = '/inorder/receiveTasks/list',
  receive = '/inorder/receiveTasks/addRecords',
  putaway = '/inorder/putawayTasks/addRecords',
  deleteOne = '/wmstask/wmsTasks/delete',
  deleteBatch = '/wmstask/wmsTasks/deleteBatch',
  importExcel = '/wmstask/wmsTasks/importExcel',
  exportXls = '/wmstask/wmsTasks/exportXls',
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
 * 上架任务查询接口
 * @param params
 */
export const putawaylist = (params) => defHttp.get({ url: Api.putawaylist, params });
/**
 * 收货任务查询接口
 * @param params
 */
export const receivelist = (params) => defHttp.get({ url: Api.receivelist, params });

/**
 * 删除单个
 */
export const deleteOne = (params, handleSuccess) => {
  return defHttp.delete({ url: Api.deleteOne, params }, { joinParamsToUrl: true }).then(() => {
    handleSuccess();
  });
};
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
      return defHttp.delete({ url: Api.deleteBatch, data: params }, { joinParamsToUrl: true }).then(() => {
        handleSuccess();
      });
    },
  });
};
/**
 * 收货
 * @param params
 */
export const receive = (data: InboundActionRequest) =>
  defHttp.post({ url: Api.receive, data }, { isTransformResponse: false }).then(requireInboundSuccess);
/**
 * 上架
 * @param params
 */
export const putaway = (data: InboundActionRequest) =>
  defHttp.post({ url: Api.putaway, data }, { isTransformResponse: false }).then(requireInboundSuccess);

export async function listReceivingTargets(params: { warehouseId?: string }) {
  const locations = await listPutawayTargets(params);
  return locations.filter((location) => location.locationType === 'RECEIVING_LOC');
}

export async function listFormalPutawayTargets(params: { warehouseId?: string }) {
  const locations = await listPutawayTargets(params);
  return locations.filter(
    (location) => location.isSellable === '1' && ['STORAGE_LOC', 'PICKING_LOC'].includes(location.locationType),
  );
}
/**
 * 保存或者更新
 * @param params
 */
export async function saveOrUpdate(_params: unknown, _isUpdate: boolean) {
  const message = '请通过收货或上架任务办理';
  createMessage.error(message);
  throw new Error(message);
}
