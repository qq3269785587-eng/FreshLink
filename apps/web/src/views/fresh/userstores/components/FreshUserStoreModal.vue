<template>
  <BasicModal v-bind="$attrs" @register="registerModal" destroyOnClose title="绑定门店" :width="640" @ok="handleSubmit">
    <BasicForm @register="registerForm" />
  </BasicModal>
</template>

<script lang="ts" setup>
  import { BasicModal, useModalInner } from '/@/components/Modal';
  import { BasicForm, useForm } from '/@/components/Form/index';
  import { candidates, bind } from '../FreshUserStore.api';
  import { options as storeOptions } from '../../stores/FreshStore.api';

  const emit = defineEmits(['register', 'success']);
  const [registerForm, { resetFields, setFieldsValue, validate }] = useForm({
    schemas: [
      {
        label: '门店用户',
        field: 'userId',
        component: 'ApiSelect',
        componentProps: {
          api: candidates,
          labelField: 'label',
          valueField: 'id',
          showSearch: true,
        },
        dynamicRules: () => [{ required: true, message: '请选择门店用户!' }],
      },
      {
        label: '绑定门店',
        field: 'storeId',
        component: 'ApiSelect',
        componentProps: {
          api: storeOptions,
          labelField: 'storeName',
          valueField: 'id',
          showSearch: true,
        },
        dynamicRules: () => [{ required: true, message: '请选择门店!' }],
      },
    ],
    showActionButtonGroup: false,
    baseColProps: { span: 24 },
  });

  const [registerModal, { setModalProps, closeModal }] = useModalInner(async (data) => {
    await resetFields();
    setModalProps({ confirmLoading: false });
    if (data?.userId) {
      await setFieldsValue({ userId: data.userId, storeId: data.storeId });
    }
  });

  async function handleSubmit() {
    try {
      const values = await validate();
      setModalProps({ confirmLoading: true });
      await bind({ userId: values.userId, storeId: values.storeId });
      closeModal();
      emit('success');
    } finally {
      setModalProps({ confirmLoading: false });
    }
  }
</script>
