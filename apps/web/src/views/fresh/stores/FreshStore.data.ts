import { BasicColumn, FormSchema } from '/@/components/Table';

export const columns: BasicColumn[] = [
  { title: '门店编码', align: 'center', dataIndex: 'storeCode' },
  { title: '门店名称', align: 'center', dataIndex: 'storeName' },
  { title: '地址', align: 'center', dataIndex: 'address' },
  { title: '联系人', align: 'center', dataIndex: 'contactName' },
  { title: '联系方式', align: 'center', dataIndex: 'contactPhone' },
  { title: '状态', align: 'center', dataIndex: 'status_dictText' },
];

export const searchFormSchema: FormSchema[] = [
  {
    label: '编码/名称',
    field: 'keyword',
    component: 'Input',
    colProps: { span: 8 },
  },
  {
    label: '状态',
    field: 'status',
    component: 'JDictSelectTag',
    componentProps: { dictCode: 'fresh_enabled_status' },
    colProps: { span: 8 },
  },
];

export const formSchema: FormSchema[] = [
  {
    label: '门店编码',
    field: 'storeCode',
    component: 'Input',
    dynamicRules: () => [{ required: true, message: '请输入门店编码!' }],
  },
  {
    label: '门店名称',
    field: 'storeName',
    component: 'Input',
    dynamicRules: () => [{ required: true, message: '请输入门店名称!' }],
  },
  {
    label: '门店地址',
    field: 'address',
    component: 'Input',
    dynamicRules: () => [{ required: true, message: '请输入门店地址!' }],
  },
  {
    label: '联系人',
    field: 'contactName',
    component: 'Input',
  },
  {
    label: '联系方式',
    field: 'contactPhone',
    component: 'Input',
  },
  {
    label: '状态',
    field: 'status',
    component: 'JDictSelectTag',
    componentProps: { dictCode: 'fresh_enabled_status' },
    defaultValue: 'ACTIVE',
    dynamicRules: () => [{ required: true, message: '请选择状态!' }],
  },
  {
    label: '备注',
    field: 'remark',
    component: 'InputTextArea',
  },
  {
    label: '',
    field: 'id',
    component: 'Input',
    show: false,
  },
];
