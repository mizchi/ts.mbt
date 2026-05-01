export interface NonSharedBuffer {}
export interface Dirent {}
export interface ErrnoException {}

export type BufferEncoding = "utf8" | "buffer";
export type PathOrFileDescriptor = string | number;

export interface ObjectEncodingOptions {
  encoding?: BufferEncoding | null | undefined;
}

export interface CopyOptions {
  filter?: (source: string, destination: string) => boolean | Promise<boolean>;
}

export declare function readFileSync(
  path: PathOrFileDescriptor,
  options?: {
    encoding?: null | undefined;
    flag?: string | undefined;
  } | null,
): NonSharedBuffer;
export declare function readFileSync(
  path: PathOrFileDescriptor,
  options:
    | {
        encoding: BufferEncoding;
        flag?: string | undefined;
      }
    | BufferEncoding,
): string;
export declare function readFileSync(
  path: PathOrFileDescriptor,
  options?:
    | (ObjectEncodingOptions & {
        flag?: string | undefined;
      })
    | BufferEncoding
    | null,
): string | NonSharedBuffer;

export declare function readFile(
  path: PathOrFileDescriptor,
  callback: (err: ErrnoException | null, data: NonSharedBuffer) => void,
): void;

declare namespace readFile {
  export function __promisify__(
    path: PathOrFileDescriptor,
    options?: {
      encoding?: null | undefined;
      flag?: string | undefined;
    } | null,
  ): Promise<NonSharedBuffer>;
  export function __promisify__(
    path: PathOrFileDescriptor,
    options:
      | {
          encoding: BufferEncoding;
          flag?: string | undefined;
        }
      | BufferEncoding,
  ): Promise<string>;
  export function __promisify__(
    path: PathOrFileDescriptor,
    options?:
      | (ObjectEncodingOptions & {
          flag?: string | undefined;
        })
      | BufferEncoding
      | null,
  ): Promise<string | NonSharedBuffer>;
}

export interface URL {}

export interface _GlobOptions<T extends Dirent | string> {
  cwd?: string | URL | undefined;
  exclude?: ((fileName: T) => boolean) | readonly string[] | undefined;
}

export interface GlobOptions extends _GlobOptions<Dirent | string> {}

export interface GlobOptionsWithFileTypes extends GlobOptions {
  withFileTypes: true;
}

export interface GlobOptionsWithoutFileTypes extends GlobOptions {
  withFileTypes?: false | undefined;
}

export declare function globSync(pattern: string | readonly string[]): string[];
export declare function globSync(
  pattern: string | readonly string[],
  options: GlobOptionsWithFileTypes,
): Dirent[];
export declare function globSync(
  pattern: string | readonly string[],
  options: GlobOptionsWithoutFileTypes,
): string[];
export declare function globSync(
  pattern: string | readonly string[],
  options: GlobOptions,
): Dirent[] | string[];
