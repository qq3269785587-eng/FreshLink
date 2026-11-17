import { defHttp } from '/@/utils/http/axios';

enum Api {
  list = '/fresh/userStores/list',
  candidates = '/fresh/userStores/candidates',
  bind = '/fresh/userStores/bind',
}

export const list = (params) => defHttp.get({ url: Api.list, params });

export const candidates = () => defHttp.get({ url: Api.candidates });

export const bind = (params) => defHttp.post({ url: Api.bind, params });
