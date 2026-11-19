<template>
  <a-form :model="{ storeId, lines }" layout="vertical" @finish="save">
    <a-alert v-if="error" type="error" :message="error" show-icon class="mb-4" />
    <a-form-item label="配送门店" required>
      <a-select v-model:value="storeId" :options="stores" :disabled="busy" show-search option-filter-prop="label" />
    </a-form-item>
    <a-table :columns="columns" :data-source="lines" :pagination="false" row-key="key" :scroll="{ x: 650 }">
      <template #bodyCell="{ column, record }">
        <a-select
          v-if="column.key === 'batch'"
          v-model:value="record.batchId"
          :options="batchOptions"
          :disabled="busy"
          show-search
          option-filter-prop="label"
          aria-label="库存批次"
          class="w-full"
        />
        <span v-else-if="column.key === 'available'">{{ availability.get(record.batchId) ?? '—' }}</span>
        <a-input-number
          v-else-if="column.key === 'quantity'"
          v-model:value="record.quantity"
          :disabled="busy"
          aria-label="出库数量"
        />
        <a-button v-else-if="column.key === 'action'" type="link" :disabled="busy" @click="remove(record.key)">移除</a-button>
      </template>
    </a-table>
    <a-space class="mt-4">
      <a-button :disabled="busy || lines.length >= 100" @click="add">添加明细</a-button>
      <a-button type="primary" html-type="submit" :loading="busy">保存草稿</a-button>
    </a-space>
  </a-form>
</template>

<script lang="ts" setup>
  import { computed, ref } from 'vue';
  import { canSelectBatch, validateOutboundDraft, type OutboundBatchOption, type OutboundDraftLine } from './outboundDraft';

  interface DraftInput {
    storeId: string;
    lines: { batchId: string; quantity: number }[];
  }

  const props = defineProps<{
    stores: { value: string; label: string }[];
    batches: OutboundBatchOption[];
    initialDraft?: DraftInput;
    saveDraft: (draft: DraftInput) => Promise<void>;
  }>();
  const emit = defineEmits<{ (event: 'saved'): void }>();
  const columns = [
    { title: '人工选批', key: 'batch', width: 290 },
    { title: '可出库量', key: 'available', width: 100 },
    { title: '出库数量', key: 'quantity', width: 145 },
    { title: '操作', key: 'action', width: 85 },
  ];
  let nextKey = 1;
  const storeId = ref(props.initialDraft?.storeId);
  const lines = ref<(OutboundDraftLine & { key: number })[]>(
    props.initialDraft?.lines.map((line) => ({ ...line, key: nextKey++ })) ?? [{ key: nextKey++ }],
  );
  const busy = ref(false);
  const error = ref<string>();
  const availability = computed(() => new Map(props.batches.map((batch) => [batch.id, batch.eligibleQuantity])));
  const batchOptions = computed(() =>
    props.batches.map((batch) => ({
      value: batch.id,
      label: batch.label + ' · 可出库 ' + batch.eligibleQuantity,
      disabled: !canSelectBatch(batch.eligibleQuantity),
    })),
  );

  function add() {
    lines.value.push({ key: nextKey++ });
  }

  function remove(key: number) {
    lines.value = lines.value.filter((line) => line.key !== key);
  }

  async function save() {
    if (busy.value) return;
    const selectedStore = storeId.value;
    error.value = validateOutboundDraft(selectedStore, lines.value, props.batches);
    if (error.value || !selectedStore) return;

    const validLines = lines.value.flatMap(({ batchId, quantity }) =>
      batchId && typeof quantity === 'number' ? [{ batchId, quantity }] : [],
    );
    busy.value = true;
    try {
      await props.saveDraft({ storeId: selectedStore, lines: validLines });
      emit('saved');
    } catch (cause) {
      error.value = cause instanceof Error ? cause.message : '保存草稿失败，请重试';
    } finally {
      busy.value = false;
    }
  }
</script>
