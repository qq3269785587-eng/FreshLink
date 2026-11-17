<template>
  <div>
    <BasicTable @register="registerTable">
      <template #tableTitle>
        <a-button type="primary" v-auth="'fresh:userstore:edit'" @click="handleBind" preIcon="ant-design:link-outlined">绑定门店</a-button>
      </template>
      <template #action="{ record }">
        <TableAction :actions="getTableAction(record)" />
      </template>
    </BasicTable>
    <FreshUserStoreModal @register="registerModal" @success="handleSuccess" />
  </div>
</template>

<script lang="ts" name="fresh-user-store" setup>
  import { BasicTable, TableAction } from '/@/components/Table';
  import { useModal } from '/@/components/Modal';
  import { useListPage } from '/@/hooks/system/useListPage';
  import FreshUserStoreModal from './components/FreshUserStoreModal.vue';
  import { columns } from './FreshUserStore.data';
  import { list, bind } from './FreshUserStore.api';

  const [registerModal, { openModal }] = useModal();
  const { tableContext } = useListPage({
    tableProps: {
      title: '用户门店绑定',
      api: list,
      columns,
      canResize: false,
      actionColumn: { width: 160, fixed: 'right' },
    },
  });

  const [registerTable, { reload }] = tableContext;

  function handleBind() {
    openModal(true, {});
  }

  function handleEdit(record: Recordable) {
    openModal(true, { userId: record.userId, storeId: record.storeId });
  }

  async function handleUnbind(record: Recordable) {
    await bind({ userId: record.userId, storeId: '' });
    reload();
  }

  function handleSuccess() {
    reload();
  }

  function getTableAction(record) {
    const actions: any[] = [
      {
        label: '改绑',
        onClick: handleEdit.bind(null, record),
        auth: 'fresh:userstore:edit',
      },
    ];
    if (record.storeId) {
      actions.push({
        label: '解绑',
        popConfirm: {
          title: '确认解除该用户的门店绑定？',
          confirm: handleUnbind.bind(null, record),
          placement: 'topLeft',
        },
        auth: 'fresh:userstore:edit',
      });
    }
    return actions;
  }
</script>
