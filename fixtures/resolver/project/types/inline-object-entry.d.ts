export declare class Client {
  handlers: { request: string; response: number };
  send(url: string, options?: { retries?: number; verbose?: boolean }): Promise<string>;
}
export interface Panel {
  layout: { width: number; height: number };
  resize(spec: { width: number; height: number }): void;
}
