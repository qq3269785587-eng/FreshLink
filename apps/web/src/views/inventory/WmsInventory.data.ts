import {BasicColumn} from '/@/components/Table';
import {FormSchema} from '/@/components/Table';
import { rules} from '/@/utils/helper/validator';
import { render } from '/@/utils/common/renderUtils';
import { getWeekMonthQuarterYear } from '/@/utils';
import { h } from 'vue';
import { Tag } from 'ant-design-vue';
import { getExpiryPresentation, getInventoryBlockReason } from './inventoryExpiry';
//列表数据
export const columns: BasicColumn[] = [
  //仓库名称
   {
     title: '仓库名称',
     align:"center",
     dataIndex: 'warehouseName'
   },
  //货主编码
  {
    title: '货主编码',
    align:"center",
    dataIndex: 'ownerCode'
   },
   {
    title: '货主',
    align:"center",
    dataIndex: 'ownerName'
   },
  //商品编码
  {
    title: '商品编码',
    align:"center",
    dataIndex: 'productCode'
   },
   {
    title: '商品',
    align:"center",
    dataIndex: 'productName'
   },
  { title: '规格', align: 'center', dataIndex: 'productSpec' },
  { title: '单位', align: 'center', dataIndex: 'unit' },
  { title: '供应商', align: 'center', dataIndex: 'supplierName' },
  { title: '来源入库单', align: 'center', dataIndex: 'inboundOrderNumber' },
   {
    title: '储位编码',
    align:"center",
    dataIndex: 'locationCode'
   },
  {
    title: '批号 ',
    align:"center",
    dataIndex: 'batchNumber'
  },
  { title: '生产日期', align: 'center', dataIndex: 'productionDate' },
  {
    title: '到期日期',
    align:"center",
    dataIndex: 'expiryDate',
    customRender:({text}) =>{
      text = !text ? "" : (text.length > 10 ? text.substr(0,10) : text);
      return text;
    },
  },
  { title: '剩余天数', align: 'center', dataIndex: 'remainingDays' },
  {
    title: '效期状态',
    align: 'center',
    dataIndex: 'expiryStatus',
    customRender: ({ text }) => {
      const { text: label, color } = getExpiryPresentation(text);
      return h(Tag, { color }, () => label);
    },
  },
  {
    title: '在库数量',
    align:"center",
    dataIndex: 'stockQuantity'
  },
  {
    title: '分配数量',
    align:"center",
    dataIndex: 'allocatedQuantity'
  },
  {
    title: '账面未分配',
    align:"center",
    dataIndex: 'availableQuantity'
  },
  { title: '可出库数量', align: 'center', dataIndex: 'eligibleQuantity' },
  {
    title: '不可出库原因',
    align: 'center',
    dataIndex: 'eligibleQuantity',
    key: 'inventoryBlockReason',
    customRender: ({ record }) => getInventoryBlockReason(record),
  },
  {
    title: '是否可售',
    align:"center",
    dataIndex: 'isSellable_dictText'
  },
  //储位类型
  {
    title: '储位类型',
    align:"center",
    dataIndex: 'locationType',
    customRender: ({text}) => {
    return render.renderDict(text, 'location_type');
    }
   },
  //储区类型
  {
    title: '储区类型',
    align:"center",
    dataIndex: 'zoneType',
    customRender: ({text}) => {
    return render.renderDict(text, 'zone_type');
    }
   },
   // {
   //  title: '容器编码',
   //  align:"center",
   //  dataIndex: 'containerCode'
   // },


   {
    title: '入库时间',
    align:"center",
    dataIndex: 'stockInTime'
   },
   // {
   //  title: '生产日期',
   //  align:"center",
   //  dataIndex: 'productionDate',
   //  customRender:({text}) =>{
   //    text = !text ? "" : (text.length > 10 ? text.substr(0,10) : text);
   //    return text;
   //  },
   // },

];
//查询数据
export const searchFormSchema: FormSchema[] = [
  {
    label: '仓库名称',
    field: 'warehouseName',
    component: 'Input',
    colProps: { span: 6 },
  },
  //货主编码
  {
    label: '货主编码',
    field: 'ownerCode',
    component: 'Input',
    colProps: {span: 6},
  },
  //货主名称
  {
    label: '货主名称',
    field: 'ownerName',
    component: 'Input',
    colProps: {span: 6},
  },
  //商品编码
  {
    label: '商品编码',
    field: 'productCode',
    component: 'Input',
    colProps: {span: 6},
  },
  //商品名称
  {
    label: '商品名称',
    field: 'productName',
    component: 'Input',
    colProps: {span: 6},
  },
  //储位编码
  {
    label: '储位编码',
    field: 'locationCode',
    component: 'Input',
    colProps: {span: 6},
  },
  //储区类型，下拉框
  {
    label: '储区类型',
    field: 'zoneType',
    component: 'JDictSelectTag',
    componentProps: {
      dictCode: "zone_type",
    },
    colProps: {span: 6},
  },
];
//表单数据
export const formSchema: FormSchema[] = [
  { label: '食材', field: 'productName', component: 'Input' },
  { label: '规格', field: 'productSpec', component: 'Input' },
  { label: '单位', field: 'unit', component: 'Input' },
  { label: '供应商', field: 'supplierName', component: 'Input' },
  { label: '来源入库单', field: 'inboundOrderNumber', component: 'Input' },
  { label: '仓库', field: 'warehouseName', component: 'Input' },
  { label: '效期状态', field: 'expiryStatusLabel', component: 'Input' },
  { label: '剩余天数', field: 'remainingDays', component: 'InputNumber' },
  { label: '可出库数量', field: 'eligibleQuantity', component: 'InputNumber' },
  { label: '不可出库原因', field: 'inventoryBlockReason', component: 'Input' },
  {
    label: '商品id',
    field: 'productId',
    component: 'Input',
    dynamicRules: ({model,schema}) => {
          return [
                 { required: true, message: '请输入商品id!'},
          ];
     },
  },
  {
    label: '储位编码',
    field: 'locationCode',
    component: 'Input',
    dynamicRules: ({model,schema}) => {
          return [
                 { required: true, message: '请输入储位编码!'},
          ];
     },
  },
  {
    label: '容器编码',
    field: 'containerCode',
    component: 'Input',
  },
  {
    label: '在库数量',
    field: 'stockQuantity',
    component: 'InputNumber',
    dynamicRules: ({model,schema}) => {
          return [
                 { required: true, message: '请输入在库数量!'},
          ];
     },
  },
  {
    label: '分配数量',
    field: 'allocatedQuantity',
    component: 'InputNumber',
  },
  {
    label: '账面未分配',
    field: 'availableQuantity',
    component: 'Input',
  },
  {
    label: '批号 ',
    field: 'batchNumber',
    component: 'Input',
  },
  {
    label: '入库时间',
    field: 'stockInTime',
    component: 'DatePicker',
    componentProps: {
       showTime: true,
       valueFormat: 'YYYY-MM-DD HH:mm:ss'
     },
    dynamicRules: ({model,schema}) => {
          return [
                 { required: true, message: '请输入入库时间!'},
          ];
     },
  },
  {
    label: '生产日期',
    field: 'productionDate',
    component: 'DatePicker',
    componentProps: {
      valueFormat: 'YYYY-MM-DD'
    },
  },
  {
    label: '保质期到期日',
    field: 'expiryDate',
    component: 'DatePicker',
    componentProps: {
      valueFormat: 'YYYY-MM-DD'
    },
  },
	// TODO 主键隐藏字段，目前写死为ID
	{
	  label: '',
	  field: 'id',
	  component: 'Input',
	  show: false
	},
];

// 高级查询数据
export const superQuerySchema = {
  productId: {title: '商品id',order: 1,view: 'text', type: 'string',},
  locationCode: {title: '储位编码',order: 2,view: 'text', type: 'string',},
  containerCode: {title: '容器编码',order: 3,view: 'text', type: 'string',},
  stockQuantity: {title: '在库数量',order: 4,view: 'number', type: 'number',},
  allocatedQuantity: {title: '分配数量',order: 5,view: 'number', type: 'number',},
  availableQuantity: {title: '账面未分配',order: 6,view: 'text', type: 'string',},
  batchNumber: {title: '批号 ',order: 7,view: 'text', type: 'string',},
  stockInTime: {title: '入库时间',order: 8,view: 'datetime', type: 'string',},
  productionDate: {title: '生产日期',order: 9,view: 'date', type: 'string',},
  expiryDate: {title: '保质期到期日',order: 10,view: 'date', type: 'string',},
};

/**
* 流程表单调用这个方法获取formSchema
* @param param
*/
export function getBpmFormSchema(_formData): FormSchema[]{
  // 默认和原始表单保持一致 如果流程中配置了权限数据，这里需要单独处理formSchema
  return formSchema;
}
