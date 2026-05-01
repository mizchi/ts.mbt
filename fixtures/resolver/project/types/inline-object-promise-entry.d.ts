export interface NodeJS_ArrayBufferView {}

export declare function readPromisify<TBuffer extends NodeJS_ArrayBufferView>(
  fd: number,
  buffer: TBuffer,
): Promise<{
  bytesRead: number;
  buffer: TBuffer;
}>;
