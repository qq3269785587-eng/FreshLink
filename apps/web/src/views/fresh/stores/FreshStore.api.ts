import { defHttp } from '/@/utils/http/axios';

enum Api {
  list = '/fresh/stores/list',
  my = '/fresh/stores/my',
  options = '/fresh/stores/options',
  save = '/fresh/stores/add',
  edit = '/fresh/stores/edit',
  deleteOne = '/fresh/stores/delete',
  deleteBatch = '/fresh/stores/deleteBatch',
}

export const list = (params) => defHttp.get({ url: Api.list, params });

export const myStore = () => defHttp.get({ url: Api.my });

export const options = () => defHttp.get({ url: Api.options });

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
