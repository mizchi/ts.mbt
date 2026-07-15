export interface Box<A, B> {
  value: A;
  check(...checks: string[]): this;
  optional(): Wrap<this>;
  pair(other: B): this;
}
export interface Wrap<T> {
  inner: T;
}
export declare class Chain<A, B> {
  value: A;
  push(item: A): this;
  wrap(): Wrap<this>;
  merge(other: this): this;
}
