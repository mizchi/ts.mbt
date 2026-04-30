export declare function makeCounter(value: string): Counter;
export declare function makeCounter(value: number): Counter;
export declare function chooseConcrete(value: unknown): unknown;
export declare function chooseConcrete(value: string): number;

export declare class Counter {
  value(): number;
  value(radix: number): number;
}
