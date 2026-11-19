<template>
  <PageWrapper title="人工选批出库">
    <a-alert v-if="error" type="error" :message="error" show-icon class="mb-3" />
    <a-alert v-if="stockBatchKey" type="info" message="当前仅查询所选批次的出库记录" show-icon class="mb-3">
      <template #action><a-button type="link" @click="emit('clear-batch')">清除筛选</a-button></template>
    </a-alert>
    <BasicTable @register="registerTable">
      <template #tableTitle>
        <a-button v-if="canWrite" type="primary" @click="openDraft()">新建出库草稿</a-button>
      </template>
      <template #action="{ record }">
        <a-button type="link" @click="openDetail(record.id)">详情</a-button>
      </template>
    </BasicTable>
    <a-modal v-model:open="draftOpen" title="出库草稿" :footer="null" :width="940">
      <a-spin :spinning="draftLoading">
        <a-alert v-if="draftError" type="error" :message="draftError" show-icon />
        <FreshOutboundDraft
          v-if="draftReady"
          :key="draftKey"
          :stores="stores"
          :batches="batchOptions"
          :initial-draft="initialDraft"
          :save-draft="saveDraft"
          @saved="afterSave"
        />
      </a-spin>
    </a-modal>
    <a-modal v-model:open="detailOpen" title="出库详情" :footer="null" :width="940"
      :closable="!mutating" :mask-closable="!mutating" :keyboard="!mutating">
      <a-spin :spinning="detailLoading">
        <a-alert v-if="detailError" type="error" :message="detailError" show-icon />
        <template v-if="detail">
          <a-descriptions bordered size="small" :column="2">
            <a-descriptions-item label="出库单号">{{ detail.order.orderNumber }}</a-descriptions-item>
            <a-descriptions-item label="配送门店">{{ detail.order.storeName }}</a-descriptions-item>
            <a-descriptions-item label="状态">{{ outboundLabels[detail.order.status] ?? detail.order.status }}</a-descriptions-item>
            <a-descriptions-item label="出库时间">{{ detail.order.confirmedAt ?? '—' }}</a-descriptions-item>
          </a-descriptions>
          <FreshLotTable :items="detail.lines" class="my-4" />
          <a-space v-if="canWrite && detail.order.status === 'DRAFT'">
            <a-button :disabled="mutating" @click="edit">编辑草稿</a-button>
            <a-popconfirm title="删除此出库草稿？" @confirm="removeDraft">
              <a-button danger :disabled="confirming" :loading="deleting">删除草稿</a-button>
            </a-popconfirm>
            <FreshConfirmOutbound :confirm-outbound="confirm" :disabled="deleting" />
          </a-space>
          <a-button v-else-if="detail.deliveryId" type="link" @click="showDelivery(detail.deliveryId)">查看配送单</a-button>
        </template>
      </a-spin>
    </a-modal>
  </PageWrapper>
</template>

<script lang="ts" setup>
  import { computed, ref, watch } from 'vue';
  import { PageWrapper } from '/@/components/Page';
  import { BasicTable, useTable } from '/@/components/Table';
  import FreshLotTable from '../FreshLotTable.vue';
  import {
    listOutbounds, getOutbound, saveOutbound, deleteOutbound, confirmOutbound,
    loadInventoryBatches, loadStoreOptions, type OutboundDetail, type InventoryBatch,
  } from '../freshWorkflow.api';
  import { useFreshWorkflowAccess } from '../freshWorkflowAccess';
  import FreshOutboundDraft from './FreshOutboundDraft.vue';
  import FreshConfirmOutbound from './FreshConfirmOutbound.vue';

  type DraftSelection = { storeId: string; lines: { batchId: string; quantity: number }[] };
  const props = defineProps<{ stockBatchKey?: string }>();
  const emit = defineEmits<{ (event: 'delivery', id: string): void; (event: 'clear-batch'): void }>();
  const { canWrite } = useFreshWorkflowAccess();
  const error = ref<string>();
  const detailError = ref<string>();
  const draftError = ref<string>();
  const detail = ref<OutboundDetail>();
  const detailOpen = ref(false);
  const detailLoading = ref(false);
  const deleting = ref(false);
  const confirming = ref(false);
  const mutating = computed(() => deleting.value || confirming.value);
  const draftOpen = ref(false);
  const draftLoading = ref(false);
  const draftReady = ref(false);
  const draftKey = ref(0);
  const editId = ref<string>();
  const stores = ref<Awaited<ReturnType<typeof loadStoreOptions>>>([]);
  const batches = ref<InventoryBatch[]>([]);
  const initialDraft = ref<DraftSelection>();
  const outboundLabels: Record<string, string> = { DRAFT: '草稿', CONFIRMED: '已出库' };

  const batchOptions = computed(() => batches.value.map((batch) => ({
    id: batch.id,
    label: [batch.productName, batch.productSpec, batch.unit, batch.supplierName, batch.batchNumber, batch.locationCode, batch.expiryDate].filter(Boolean).join(' · '),
    eligibleQuantity: batch.eligibleQuantity ?? 0,
  })));
  const [registerTable, { reload }] = useTable({
    rowKey: 'id',
    api: async (params) => {
      error.value = undefined;
      try { return await listOutbounds({ ...params, stockBatchKey: props.stockBatchKey }); }
      catch (cause) {
        error.value = cause instanceof Error ? cause.message : '加载出库列表失败';
        throw cause;
      }
    },
    columns: [
      { title: '出库单号', dataIndex: 'orderNumber' },
      { title: '配送门店', dataIndex: 'storeName' },
      { title: '状态', dataIndex: 'status', customRender: ({ text }) => outboundLabels[text] ?? text },
      { title: '创建时间', dataIndex: 'createdAt' },
      { title: '出库时间', dataIndex: 'confirmedAt' },
    ],
    actionColumn: { title: '操作', width: 80, slots: { customRender: 'action' } },
  });
  watch(() => props.stockBatchKey, () => { void reload({ page: 1 }); });

  async function openDetail(id: string) {
    if (detailLoading.value || mutating.value) return;
    detail.value = undefined;
    detailError.value = undefined;
    detailOpen.value = true;
    detailLoading.value = true;
    try { detail.value = await getOutbound(id); }
    catch (cause) { detailError.value = cause instanceof Error ? cause.message : '加载出库详情失败'; }
    finally { detailLoading.value = false; }
  }

  async function openDraft(existing?: OutboundDetail) {
    if (!canWrite.value || draftLoading.value) return;
    draftReady.value = false;
    draftOpen.value = true;
    draftLoading.value = true;
    draftError.value = undefined;
    editId.value = existing?.order.id;
    initialDraft.value = existing && {
      storeId: existing.order.storeId,
      lines: existing.lines.map((line) => ({ batchId: line.inventoryId, quantity: line.quantity })),
    };
    try {
      [stores.value, batches.value] = await Promise.all([loadStoreOptions(), loadInventoryBatches()]);
      draftKey.value++;
      draftReady.value = true;
    } catch (cause) { draftError.value = cause instanceof Error ? cause.message : '加载门店或库存失败'; }
    finally { draftLoading.value = false; }
  }

  function edit() {
    if (detail.value?.order.status !== 'DRAFT' || mutating.value) return;
    detailOpen.value = false;
    void openDraft(detail.value);
  }

  async function saveDraft(draft: DraftSelection) {
    if (!canWrite.value) return;
    const keys = new Map(batches.value.map((batch) => [batch.id, batch.stockBatchKey]));
    await saveOutbound({
      storeId: draft.storeId,
      lines: draft.lines.map(({ batchId, quantity }) => {
        const key = keys.get(batchId);
        if (!key) throw new Error('所选批次已不可用，请重新选择');
        return { inventoryId: batchId, stockBatchKey: key, quantity };
      }),
    }, editId.value);
  }

  function afterSave() {
    draftOpen.value = false;
    void reload();
  }

  function showDelivery(id: string) {
    detailOpen.value = false;
    emit('delivery', id);
  }

  async function confirm() {
    const record = detail.value?.order;
    if (!canWrite.value || record?.status !== 'DRAFT' || mutating.value) return;
    confirming.value = true;
    try {
      detail.value = await confirmOutbound(record.id);
      void reload();
    } finally {
      confirming.value = false;
    }
  }

  async function removeDraft() {
    const record = detail.value?.order;
    if (!canWrite.value || record?.status !== 'DRAFT' || mutating.value) return;
    deleting.value = true;
    detailError.value = undefined;
    try {
      await deleteOutbound(record.id);
      detailOpen.value = false;
      void reload();
    } catch (cause) { detailError.value = cause instanceof Error ? cause.message : '删除草稿失败'; }
    finally { deleting.value = false; }
  }
</script>
