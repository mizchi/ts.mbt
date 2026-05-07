export interface ParseOptions {}
export interface ParsedUrlQuery {}

export declare function parse(
  str: string,
  sep?: string,
  eq?: string,
  options?: ParseOptions,
): ParsedUrlQuery;

export declare const decode: typeof parse;
