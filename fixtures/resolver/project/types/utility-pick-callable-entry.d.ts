export interface Opts {
  a?: boolean;
  b?: boolean;
  c?: string;
}
// Only `const` callables, each with an OPTIONAL parameter (so the type is
// wrapped in `CallableMeta`): no `function` declaration projects the same
// `Pick` and masks a missing collector.
export declare const escape: (s: string, o?: Pick<Opts, "a" | "b">) => string;
export declare const unescape: (s: string, { a, b, }?: Pick<Opts, "a" | "b">) => string;
