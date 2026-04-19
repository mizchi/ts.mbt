export declare class Counter {
  constructor(initial: number);
  inc(delta: number): number;
  value(): number;
  static from(seed: number): Counter;
}
