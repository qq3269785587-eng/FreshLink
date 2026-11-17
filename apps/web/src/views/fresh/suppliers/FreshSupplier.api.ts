import { defHttp } from '/@/utils/http/axios';

enum Api {
  list = '/fresh/suppliers/list',
  save = '/fresh/suppliers/add',
  edit = '/fresh/suppliers/edit',
  deleteOne = '/fresh/suppliers/delete',
  deleteBatch = '/fresh/suppliers/deleteBatch',
}

export const list = (params) => defHttp.get({ url: Api.list, params });

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
