export interface Payload {
  kind: string;
  body: string;
}
export interface Ack {
  ok: boolean;
}
export type OnPayload<T> = (value: T) => T | Promise<T>;
export interface Channel<V> {
  post: V extends Ack ? (fn: () => void) => number : (fn: OnPayload<V>) => number;
  clear(): void;
}
export declare function payloadChannel(): Channel<Payload>;
export declare function ackChannel(): Channel<Ack>;
