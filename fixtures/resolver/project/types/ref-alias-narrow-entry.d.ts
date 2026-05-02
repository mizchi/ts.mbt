export type RefObject<T> = { current: T | null };
export type RefCallback<T> = (instance: T | null) => void;
export type Ref<T> = RefObject<T> | RefCallback<T> | null;

export interface VNodeLike<P = {}> {
  ref?: Ref<unknown> | null;
}

export interface ClassAttrs<T> {
  ref?: Ref<T>;
}
