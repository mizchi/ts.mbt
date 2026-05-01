export type Params = Record<string, string | null>;

export declare function generatePath(
  originalPath: string,
  params?: Params,
): string;
