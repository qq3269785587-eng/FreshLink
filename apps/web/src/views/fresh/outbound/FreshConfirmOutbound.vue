<template>
  <a-popconfirm
    title="确认后会扣减库存并生成待配送单，确定出库？"
    ok-text="确认出库"
    cancel-text="取消"
    :disabled="busy || disabled"
    @confirm="confirm"
  >
    <a-button type="primary" :loading="busy" :disabled="disabled">确认出库</a-button>
  </a-popconfirm>
  <a-alert v-if="error" type="error" :message="error" show-icon class="mt-2" />
</template>

<script lang="ts" setup>
  import { ref } from 'vue';

  const props = defineProps<{ confirmOutbound: () => Promise<void>; disabled?: boolean }>();
  const busy = ref(false);
  const error = ref<string>();

  async function confirm() {
    if (busy.value || props.disabled) return;
    error.value = undefined;
    busy.value = true;
    try {
      await props.confirmOutbound();
    } catch (cause) {
      error.value = cause instanceof Error ? cause.message : '确认出库失败，请刷新库存后重试';
    } finally {
      busy.value = false;
    }
  }
</script>
