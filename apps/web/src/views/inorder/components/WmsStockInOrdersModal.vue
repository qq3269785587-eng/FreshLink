<template>
  <BasicModal v-bind="$attrs" @register="registerModal" destroyOnClose :title="title" :width="1100" @ok="handleSubmit">
      <BasicForm @register="registerForm" ref="formRef" name="WmsStockInOrdersForm" />
      <!-- 子表单区域 -->
      <a-tabs v-model:activeKey="activeKey" animated @change="handleChangeTabs">
        <a-tab-pane tab="入库单明细" key="wmsStockInOrderItems" :forceRender="true">
          <JVxeTable
            keep-source
            resizable
            ref="wmsStockInOrderItems"
            :loading="wmsStockInOrderItemsTable.loading"
            :columns="wmsStockInOrderItemsTable.columns"
            :dataSource="wmsStockInOrderItemsTable.dataSource"
            :height="340"
            :disabled="formDisabled"
            :rowNumber="true"
            :rowSelection="!formDisabled"
            :toolbar="!formDisabled"
            @valueChange="handleItemValueChange"
            />
        </a-tab-pane>
      </a-tabs>
  </BasicModal>
</template>

<script lang="ts" setup>
    import {ref, computed, unref,reactive} from 'vue';
    import {BasicModal, useModalInner} from '/@/components/Modal';
    import {BasicForm, useForm} from '/@/components/Form/index';
    import { JVxeTable } from '/@/components/jeecg/JVxeTable'
    import { useJvxeMethod } from '/@/hooks/system/useJvxeMethods.ts'
    import { useMessage } from '/@/hooks/web/useMessage';
    import { InboundBusinessError } from '../inboundRequest';
    import {
      createWmsStockInOrderItemsJVxeColumns,
      formAddSchema,
      formSchema,
      // wmsStockInOrderItemsJVxeColumns
    } from '../WmsStockInOrders.data';
    import { type InboundProductOption, listInboundProductOptions, saveOrUpdate, queryWmsStockInOrderItems } from '../WmsStockInOrders.api';
    import { VALIDATE_FAILED } from '/@/utils/common/vxeUtils'

    // Emits声明
    const emit = defineEmits(['register','success']);
    const { createMessage } = useMessage();
    const isUpdate = ref(true);
    const formDisabled = ref(false);
    const refKeys = ref(['wmsStockInOrderItems', ]);
    const activeKey = ref('wmsStockInOrderItems');
    const wmsStockInOrderItems = ref();
    const tableRefs = {wmsStockInOrderItems, };


    //表单配置
    const [registerForm, { setProps, resetSchema, resetFields, setFieldsValue }] = useForm({
        schemas: formSchema,
        showActionButtonGroup: false,
        baseColProps: {span: 12},
    });

    const productOptions = reactive<InboundProductOption[]>([]);
    const wmsStockInOrderItemsTable = reactive({
      loading: false,
      dataSource: [],
      columns: createWmsStockInOrderItemsJVxeColumns(productOptions),
    })
    let productRequest = 0;
    async function loadOwnerProducts(ownerId?: string) {
      const request = ++productRequest;
      productOptions.splice(0);
      if (!ownerId) return;
      try {
        const options = await listInboundProductOptions(ownerId);
        if (request === productRequest) productOptions.splice(0, productOptions.length, ...options);
      } catch {
        // defHttp shows request errors; the table stays available for a new owner selection.
      }
    }

    const addSchemaWithOwner = formAddSchema.map((schema) =>
      schema.field === 'ownerId'
        ? { ...schema, componentProps: { ...schema.componentProps, onChange: loadOwnerProducts } }
        : schema,
    );

    function handleItemValueChange({ row, col, value }) {
      if (col?.key === 'productId') {
        row.productName = productOptions.find((product) => product.value === value)?.label ?? '';
      }
    }
     //表单赋值
    const [registerModal, {setModalProps, closeModal}] = useModalInner(async (data) => {
        //重置表单
        isUpdate.value = !!data?.isUpdate;
        formDisabled.value = !data?.showFooter;
        await resetSchema(isUpdate.value ? formSchema : addSchemaWithOwner);
        await setProps({ disabled: formDisabled.value });
        await reset();
        void loadOwnerProducts(isUpdate.value ? data?.record?.ownerId : undefined);
        setModalProps({confirmLoading: false,showCancelBtn:data?.showFooter,showOkBtn:data?.showFooter});
        if (unref(isUpdate)) {
            //表单赋值
            await setFieldsValue({
                ...data.record,
            });
          //   //如果货主已填写则赋值给wmsStockInOrderItemsTable的params({owner_id:xx}),实现弹窗查询商品传入货主参数
          // alert(data?.record?.ownerId)
          //   if(data?.record?.ownerId){
          //     wmsStockInOrderItemsTable.columns.forEach((item)=>{
          //       if(item.key === 'productId'){
          //         item.params = {owner_id:data?.record?.ownerId}
          //       }
          //     })
          //   }
          //   console.log('wmsStockInOrderItemsTable',wmsStockInOrderItemsTable)
             requestSubTableData(queryWmsStockInOrderItems, {id:data?.record?.id}, wmsStockInOrderItemsTable)
        }
    });
    //方法配置
    const [handleChangeTabs,handleSubmit,requestSubTableData,formRef] = useJvxeMethod(requestAddOrEdit,classifyIntoFormData,tableRefs,activeKey,refKeys);
    //设置标题
    const title = computed(() => (!unref(isUpdate) ? '新增' : !unref(formDisabled) ? '编辑' : '详情'));

    async function reset(){
      await resetFields();
      activeKey.value = 'wmsStockInOrderItems';
      wmsStockInOrderItemsTable.dataSource = [];
    }
    function classifyIntoFormData(allValues) {
         let main = Object.assign({}, allValues.formValue)
         return {
           ...main, // 展开
           wmsStockInOrderItemsList: allValues.tablesValue[0].tableData,
         }
       }
    //表单提交事件
    let submitting = false;
    async function requestAddOrEdit(values) {
        if (submitting) return;
        submitting = true;
        try {
            setModalProps({confirmLoading: true});
            //提交表单
            await saveOrUpdate(values, isUpdate.value);
            createMessage.success('入库单已保存');
            //关闭弹窗
            closeModal();
            //刷新列表
            emit('success');
        } catch (error) {
            if (error instanceof InboundBusinessError) createMessage.error(error.message);
            else throw error;
        } finally {
            submitting = false;
            setModalProps({confirmLoading: false});
        }
    }
</script>

<style lang="less" scoped>
	/** 时间和数字输入框样式 */
  :deep(.ant-input-number) {
    width: 100%;
  }

  :deep(.ant-calendar-picker) {
    width: 100%;
  }
</style>
