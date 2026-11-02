// ws: `close(cb?: (err?: Error) => void)` — an OPTIONAL callback whose own
// parameter is optional, so the callable is wrapped in `CallableMeta`.
export declare class Server<T = any> {
  constructor(n: number);
  close(cb?: (err?: Error) => void): void;
  close2(cb?: (err: Error) => void): void;
}
export declare function close3(cb?: (err?: Error) => void): void;
