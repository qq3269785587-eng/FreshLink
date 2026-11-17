<template>
  <component
    :is="asModal ? BasicModal : 'div'"
    v-bind="asModal ? { title: '商品图片', width: '1000px' } : {}"
    @register="registerModal"
    @ok="closeModal"
  >
    <WmsProductImagesTable
      v-if="tableVisible"
      :key="tableVersion"
      :product-id="productId"
    />
  </component>
</template>

<script lang="ts" name="goods-wmsProductImages" setup>
  import { ref } from 'vue';
  import { BasicModal, useModalInner } from '/@/components/Modal';
  import WmsProductImagesTable from './components/WmsProductImagesTable.vue';

  const props = defineProps({ asModal: { type: Boolean, default: false } });
  defineEmits(['register']);
  const productId = ref('');
  const tableVisible = ref(!props.asModal);
  const tableVersion = ref(0);

  const [registerModal, { closeModal }] = useModalInner((data) => {
    productId.value = data?.productId || '';
    tableVersion.value += 1;
    tableVisible.value = !!productId.value;
  });
</script>
