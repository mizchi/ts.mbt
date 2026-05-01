export declare function ok(
  value: unknown,
  message?: string | Error,
): asserts value;

export declare function equal(
  actual: unknown,
  expected: unknown,
  message?: string | Error,
): void;

export declare function strictEqual<T>(
  actual: unknown,
  expected: T,
  message?: string | Error,
): asserts actual is T;
