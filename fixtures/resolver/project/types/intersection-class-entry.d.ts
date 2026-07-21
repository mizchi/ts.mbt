export declare class HeaderBag {
  set(name: string, value: string): this;
  get(name: string): string | undefined;
}

export type RawHeaders = {
  [key: string]: string;
};

export type RequestHeaders = RawHeaders & HeaderBag;

export interface RequestConfig {
  headers: RequestHeaders;
}

export declare function makeConfig(): RequestConfig;
