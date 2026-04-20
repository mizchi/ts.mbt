export type Unit = undefined;
export type Bool = boolean;
export type Int = number;
export type Double = number;
export type String = string;
export type Bytes = Uint8Array;
export type Result<T, E> =
  | { $tag: 1; _0: T }
  | { $tag: 0; _0: E };
