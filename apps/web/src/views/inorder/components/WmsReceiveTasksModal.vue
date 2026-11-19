<template>
  <BasicModal v-bind="$attrs" @register="registerModal" destroyOnClose :title="title" :width="896" @ok="handleSubmit">
      <BasicForm @register="registerForm" name="WmsTasksForm" />
  </BasicModal>
</template>

<script lang="ts" setup>
    import type { ValidateErrorEntity } from 'ant-design-vue/es/form/interface';
    import {ref, computed, unref} from 'vue';
    import {BasicModal, useModalInner} from '/@/components/Modal';
    import {BasicForm, useForm} from '/@/components/Form/index';
    import {receiveFormSchema} from '../WmsTasks.data';
    import {receive} from '../WmsTasks.api';
    import { useMessage } from '/@/hooks/web/useMessage';
    import { createInboundActionSubmitter, InboundBusinessError } from '../inboundRequest';
    import { getReceiptDateError } from '../inboundValidation';
    // Emits声明
    const emit = defineEmits(['register','success']);
    const { createMessage } = useMessage();
    const submitAction = createInboundActionSubmitter(receive);
    const isUpdate = ref(true);
    const isDetail = ref(false);
    //表单配置
    const [registerForm, { setProps,resetFields, setFieldsValue, validate, scrollToField }] = useForm({
        schemas: receiveFormSchema,
        showActionButtonGroup: false,
        baseColProps: {span: 12}
    });
    //表单赋值
    const [registerModal, {setModalProps, closeModal}] = useModalInner(async (data) => {
        //重置表单
        await resetFields();
        setModalProps({confirmLoading: false,showCancelBtn:!!data?.showFooter,showOkBtn:!!data?.showFooter});
        isUpdate.value = !!data?.isUpdate;
        isDetail.value = !!data?.showFooter;
        if (unref(isUpdate)) {
            //表单赋值
            await setFieldsValue({
                ...data.record,
            });
        }
        // 隐藏底部时禁用整个表单
       setProps({ disabled: !data?.showFooter })
    });
    //设置标题
    const title = computed(() => '收货');
    let submitting = false;
    //表单提交事件
    async function handleSubmit() {
        if (submitting) return;
        submitting = true;
        try {
            setModalProps({confirmLoading: true});
            const values = await validate();
            const dateError = getReceiptDateError(values.productionDate, values.expiryDate);
            if (dateError) throw new InboundBusinessError(dateError);
            await submitAction({
                id: values.id,
                execQuantity: Number(values.execQuantity),
                targetLocationCode: values.targetLocationCode,
            });
            createMessage.success('收货成功');
            //关闭弹窗
            closeModal();
            //刷新列表
            emit('success');
        } catch (error) {
            if (error instanceof InboundBusinessError) createMessage.error(error.message);
            const firstField = (error as ValidateErrorEntity | undefined)?.errorFields?.[0];
            if (firstField) {
                scrollToField(firstField.name, { behavior: 'smooth', block: 'center' });
            }
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
