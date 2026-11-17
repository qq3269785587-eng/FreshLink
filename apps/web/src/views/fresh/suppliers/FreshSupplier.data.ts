import { BasicColumn, FormSchema } from '/@/components/Table';

export const columns: BasicColumn[] = [
  { title: '供应商编码', align: 'center', dataIndex: 'supplierCode' },
  { title: '供应商名称', align: 'center', dataIndex: 'supplierName' },
  { title: '联系人', align: 'center', dataIndex: 'contactName' },
  { title: '联系方式', align: 'center', dataIndex: 'contactPhone' },
  { title: '状态', align: 'center', dataIndex: 'status_dictText' },
  { title: '备注', align: 'center', dataIndex: 'remark' },
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
    label: '供应商编码',
    field: 'supplierCode',
    component: 'Input',
    dynamicRules: () => [{ required: true, message: '请输入供应商编码!' }],
  },
  {
    label: '供应商名称',
    field: 'supplierName',
    component: 'Input',
    dynamicRules: () => [{ required: true, message: '请输入供应商名称!' }],
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
