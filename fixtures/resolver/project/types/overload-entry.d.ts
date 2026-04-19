export declare function makeCounter(value: string): Counter;
export declare function makeCounter(value: number): Counter;

export declare class Counter {
  value(): number;
  value(radix: number): number;
}
