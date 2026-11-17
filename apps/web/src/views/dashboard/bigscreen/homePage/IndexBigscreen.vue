<template>
  <div class="p-4">
    <Alert
      message="统计接口尚未接入，当前不展示业务统计"
      description="待办任务、入出库趋势、出库排行和库存预警将在接入真实业务数据后展示。"
      type="info"
      show-icon
      class="mb-4"
    />
    <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
      <Card v-for="title in statisticSections" :key="title" :title="title" :bordered="false">
        <Empty description="暂无可展示的业务统计" />
      </Card>
    </div>
  </div>
</template>

<script lang="ts" setup>
  import { Alert, Card, Empty } from 'ant-design-vue';

  const statisticSections = ['待办任务', '入出库趋势', '货主出库排行', '库存预警'];

  // The parent invokes these methods when the selected warehouse changes.
  // Keep the unavailable state until real statistics endpoints are implemented.
  function keepStatisticsUnavailable(): void {}

  defineExpose({
    todoTaskList: keepStatisticsUnavailable,
    inOrderData: keepStatisticsUnavailable,
    outOrderData: keepStatisticsUnavailable,
    rankListData: keepStatisticsUnavailable,
  });
</script>
