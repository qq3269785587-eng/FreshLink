import { buildUUID } from '/@/utils/uuid';

export interface InboundActionFields {
  id: string;
  execQuantity: number;
  targetLocationCode: string;
}

export interface InboundActionRequest extends InboundActionFields {
  requestKey: string;
}

interface InboundResult<T> {
  success: boolean;
  message?: string;
  result?: T;
}

export class InboundBusinessError extends Error {}

export function requireInboundSuccess<T>(response: InboundResult<T>) {
  if (response?.success !== true) throw new InboundBusinessError(response?.message || '入库操作未成功');
  return response.result;
}

export function createInboundActionSubmitter<T>(send: (request: InboundActionRequest) => Promise<T>) {
  const pending = new Map<string, string>();
  return async ({ id, execQuantity, targetLocationCode }: InboundActionFields) => {
    const signature = JSON.stringify([id, execQuantity, targetLocationCode]);
    const requestKey = pending.get(signature) ?? buildUUID();
    pending.set(signature, requestKey);
    const result = await send({ id, execQuantity, targetLocationCode, requestKey });
    pending.delete(signature);
    return result;
  };
}
