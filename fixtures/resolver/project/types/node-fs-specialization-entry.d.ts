export interface NonSharedBuffer {}

export interface BigIntStats {
  atimeNs: bigint;
  mtimeNs: bigint;
  ctimeNs: bigint;
  birthtimeNs: bigint;
}

export interface FSWatcherEventMap {
  change: [eventType: string, filename: string | NonSharedBuffer];
}

export type BufferEncoding = "utf8" | "buffer";

export interface WatchOptions {
  encoding?: BufferEncoding | "buffer" | undefined;
}
