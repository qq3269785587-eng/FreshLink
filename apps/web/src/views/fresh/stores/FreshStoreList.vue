<template>
  <div>
    <BasicTable @register="registerTable" :rowSelection="rowSelection">
      <template #tableTitle>
        <a-button type="primary" v-auth="'fresh:store:add'" @click="handleAdd" preIcon="ant-design:plus-outlined">新增</a-button>
        <a-dropdown v-if="selectedRowKeys.length > 0">
          <template #overlay>
            <a-menu>
              <a-menu-item key="1" @click="batchHandleDelete">
                <Icon icon="ant-design:delete-outlined" />
                删除
              </a-menu-item>
            </a-menu>
          </template>
          <a-button v-auth="'fresh:store:deleteBatch'">
            批量操作
            <Icon icon="mdi:chevron-down" />
          </a-button>
        </a-dropdown>
      </template>
      <template #action="{ record }">
        <TableAction :actions="getTableAction(record)" :dropDownActions="getDropDownAction(record)" />
      </template>
    </BasicTable>
    <FreshStoreModal @register="registerModal" @success="handleSuccess" />
    <FreshDeliveryList v-if="route.path === '/fresh/my-store'" read-only />
  </div>
</template>

<script lang="ts" name="fresh-store" setup>
  import { reactive } from 'vue';
  import { useRoute } from 'vue-router';
  import { BasicTable, TableAction } from '/@/components/Table';
  import { useModal } from '/@/components/Modal';
  import { useListPage } from '/@/hooks/system/useListPage';
  import FreshStoreModal from './components/FreshStoreModal.vue';
  import { columns, searchFormSchema } from './FreshStore.data';
  import { list, deleteOne, batchDelete } from './FreshStore.api';
  import FreshDeliveryList from '../delivery/FreshDeliveryList.vue';

  const route = useRoute();
  const queryParam = reactive<any>({});
  const [registerModal, { openModal }] = useModal();
  const { tableContext } = useListPage({
    tableProps: {
      title: '门店资料',
      api: list,
      columns,
      canResize: false,
      formConfig: {
        schemas: searchFormSchema,
        autoSubmitOnEnter: true,
        showAdvancedButton: true,
      },
      actionColumn: { width: 120, fixed: 'right' },
      beforeFetch: (params) => Object.assign(params, queryParam),
    },
  });

  const [registerTable, { reload }, { rowSelection, selectedRowKeys }] = tableContext;

  function handleAdd() {
    openModal(true, { isUpdate: false, showFooter: true });
  }

  function handleEdit(record: Recordable) {
    openModal(true, { record, isUpdate: true, showFooter: true });
  }

  async function handleDelete(record) {
    await deleteOne({ id: record.id }, handleSuccess);
  }

  async function batchHandleDelete() {
    await batchDelete({ ids: selectedRowKeys.value.join(',') }, handleSuccess);
  }

  function handleSuccess() {
    selectedRowKeys.value = [];
    reload();
  }

  function getTableAction(record) {
    return [
      {
        label: '编辑',
        onClick: handleEdit.bind(null, record),
        auth: 'fresh:store:edit',
      },
    ];
  }

  function getDropDownAction(record) {
    return [
      {
        label: '删除',
        popConfirm: {
          title: '是否确认删除？被引用时后端会拒绝',
          confirm: handleDelete.bind(null, record),
          placement: 'topLeft',
        },
        auth: 'fresh:store:delete',
      },
    ];
  }
</script>
