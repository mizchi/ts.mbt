export interface Base {
  id: string;
  describe(): string;
}
export interface Wide<T> {
  pick(value: T): T;
}
export interface Derived extends Base {
  extra(): number;
}
export interface DerivedGeneric<T> extends Wide<T>, Base {
  own(value: T): void;
}
export declare class Engine {
  start(): void;
}
export interface EngineHandle extends Engine {
  handleOnly(): boolean;
}
export declare function makeDerived(): Derived;
