export interface GlobOptions {
  dot?: boolean | undefined;
}

export declare const hasMagic: (
  pattern: string | string[],
  options?: GlobOptions,
) => boolean;

export declare const escape: (
  pattern: string,
  options: GlobOptions,
) => string;
