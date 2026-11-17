import { BasicColumn } from '/@/components/Table';

export const columns: BasicColumn[] = [
  { title: '账号', align: 'center', dataIndex: 'username' },
  { title: '姓名', align: 'center', dataIndex: 'realname' },
  { title: '绑定门店编码', align: 'center', dataIndex: 'storeCode' },
  { title: '绑定门店', align: 'center', dataIndex: 'storeName' },
  { title: '绑定时间', align: 'center', dataIndex: 'boundTime' },
];
