export interface JestAssertion<T> {
  toBe(expected: T): void;
  toEqual(expected: T): void;
}

export interface Assertion<T> extends JestAssertion<T> {
  toBeTypeOf(expected: string): void;
}

export interface ExpectStatic {
  <T>(actual: T, message?: string): Assertion<T>;
}
