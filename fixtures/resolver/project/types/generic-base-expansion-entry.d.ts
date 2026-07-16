export interface Base<T> {
    parse(value: unknown): T;
    label: T;
}
export interface StrSchema extends Base<string> {
    kind: string;
}
export declare function make(): StrSchema;
