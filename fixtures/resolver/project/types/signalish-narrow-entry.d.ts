export interface SignalLike<T> {
  value: T;
  peek(): T;
}

export type Signalish<T> = T | SignalLike<T>;

export interface SvgLike<Target> {
  accentHeight?: Signalish<number | string | undefined>;
  fill?: Signalish<string>;
  customSignal?: SignalLike<number>;
}
