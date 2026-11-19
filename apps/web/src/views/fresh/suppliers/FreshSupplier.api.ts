import { defHttp } from '/@/utils/http/axios';

enum Api {
  list = '/fresh/suppliers/list',
  options = '/fresh/suppliers/options',
  detail = '/fresh/suppliers/queryById',
  save = '/fresh/suppliers/add',
  edit = '/fresh/suppliers/edit',
  deleteOne = '/fresh/suppliers/delete',
  deleteBatch = '/fresh/suppliers/deleteBatch',
}

export const list = (params) => defHttp.get({ url: Api.list, params });

interface SupplierOption {
  id: string;
  supplierName: string;
}

export async function inboundSupplierOptions({ supplierId }: { supplierId?: string } = {}) {
  const options = await defHttp.get<SupplierOption[]>({ url: Api.options });
  if (!supplierId || options.some((supplier) => supplier.id === supplierId)) return options;
  const selected = await defHttp.get<SupplierOption>({ url: Api.detail, params: { id: supplierId } });
  return [...options, selected];
}

export const saveOrUpdate = (params, isUpdate: boolean) => {
  return defHttp.post({ url: isUpdate ? Api.edit : Api.save, params });
};

export const deleteOne = (params, handleSuccess) => {
  return defHttp.delete({ url: Api.deleteOne, params }, { joinParamsToUrl: true }).then(() => {
    handleSuccess();
  });
};

export const batchDelete = (params, handleSuccess) => {
  return defHttp.delete({ url: Api.deleteBatch, params }, { joinParamsToUrl: true }).then(() => {
    handleSuccess();
  });
};
