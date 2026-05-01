export interface DiffEntry {
  value: string;
  count?: number;
}

export declare function diff(
  actual: string | readonly string[],
  expected: string | readonly string[],
): DiffEntry[];

export declare function isArray(object: unknown): boolean;
