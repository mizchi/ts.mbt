export type Format<T> = T extends object ? FormatInner<T> : unknown;
export type FormatInner<T> = Format<T>;
export declare function format<T>(value: T): Format<T>;
export declare function format<T>(value: T, fallback?: string): Format<T>;
