export interface Store {
  get(key: string): string;
  get(key: string, fallback: string): string;
  watch(handler: () => void): void;
}
export declare class Codec {
  encode(value: string): string;
  encode(value: string, pretty: boolean): string;
  decode(raw: string): string;
}
