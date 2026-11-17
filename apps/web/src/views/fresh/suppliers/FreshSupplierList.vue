<template>
  <div>
    <BasicTable @register="registerTable" :rowSelection="rowSelection">
      <template #tableTitle>
        <a-button type="primary" v-auth="'fresh:supplier:add'" @click="handleAdd" preIcon="ant-design:plus-outlined">新增</a-button>
        <a-dropdown v-if="selectedRowKeys.length > 0">
          <template #overlay>
            <a-menu>
              <a-menu-item key="1" @click="batchHandleDelete">
                <Icon icon="ant-design:delete-outlined" />
                删除
              </a-menu-item>
            </a-menu>
          </template>
          <a-button v-auth="'fresh:supplier:deleteBatch'">
            批量操作
            <Icon icon="mdi:chevron-down" />
          </a-button>
        </a-dropdown>
      </template>
      <template #action="{ record }">
        <TableAction :actions="getTableAction(record)" :dropDownActions="getDropDownAction(record)" />
      </template>
    </BasicTable>
    <FreshSupplierModal @register="registerModal" @success="handleSuccess" />
  </div>
</template>

<script lang="ts" name="fresh-supplier" setup>
  import { reactive } from 'vue';
  import { BasicTable, TableAction } from '/@/components/Table';
  import { useModal } from '/@/components/Modal';
  import { useListPage } from '/@/hooks/system/useListPage';
  import FreshSupplierModal from './components/FreshSupplierModal.vue';
  import { columns, searchFormSchema } from './FreshSupplier.data';
  import { list, deleteOne, batchDelete } from './FreshSupplier.api';

  const queryParam = reactive<any>({});
  const [registerModal, { openModal }] = useModal();
  const { tableContext } = useListPage({
    tableProps: {
      title: '生鲜供应商',
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
        auth: 'fresh:supplier:edit',
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
        auth: 'fresh:supplier:delete',
      },
    ];
  }
</script>
