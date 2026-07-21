export interface CollectionChain<T> {
  compact(): CollectionChain<T>;
  first(): T;
  map<U>(fn: (item: T) => U): CollectionChain<U>;
  value(): T[];
}
export declare function chain<T>(items: T[]): CollectionChain<T>;
