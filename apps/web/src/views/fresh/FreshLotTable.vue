<template>
  <a-table :columns="columns" :data-source="items" :pagination="false" :scroll="{ x: 800 }" row-key="id" size="small" />
</template>

<script lang="ts" setup>
  import type { LotSnapshot } from './freshWorkflow.api';

  defineProps<{ items: LotSnapshot[] }>();
  const columns = [
    { title: '食材', dataIndex: 'productName' },
    { title: '规格', dataIndex: 'productSpec' },
    { title: '供应商', dataIndex: 'supplierName' },
    { title: '批号', dataIndex: 'batchNumber' },
    { title: '储位', dataIndex: 'locationCode' },
    { title: '到期日期', dataIndex: 'expiryDate' },
    { title: '数量', dataIndex: 'quantity' },
    { title: '单位', dataIndex: 'unit' },
  ];
</script>
