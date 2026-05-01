export interface NonSharedBuffer {}

export type EncodingOption = string | undefined | null;
export type BufferEncodingOption = "buffer" | { encoding: "buffer" };

export declare function readlinkSync(path: string, options?: EncodingOption): string;
export declare function readlinkSync(path: string, options: BufferEncodingOption): NonSharedBuffer;
export declare function readlinkSync(path: string, options?: EncodingOption): string | NonSharedBuffer;
