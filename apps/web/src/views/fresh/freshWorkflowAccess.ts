import { computed } from 'vue';
import { usePermissionStore } from '/@/store/modules/permission';

export function canWriteFreshWorkflow(permissions: readonly (string | number)[]) {
  return permissions.includes('outorder:wms_out_orders:add');
}

export function useFreshWorkflowAccess() {
  const permissions = usePermissionStore();
  return { canWrite: computed(() => canWriteFreshWorkflow(permissions.getPermCodeList)) };
}
