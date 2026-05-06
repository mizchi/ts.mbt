// Mixed primitive + string-literal union, modeled after magic-string `hires`.
// `boolean | "boundary"` is discriminated by `typeof` and `===` at the JS
// boundary and lowered to a `pub(all) enum` with one no-payload literal case.
export type Hires = boolean | "boundary";

export declare function setHires(value: Hires): Hires;
export declare function maybeHires(value?: Hires): Hires | undefined;
