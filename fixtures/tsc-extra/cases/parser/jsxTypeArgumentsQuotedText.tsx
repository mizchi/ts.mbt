// @jsx: preserve
// @strict: true
// @target: esnext

// A JSX element's type arguments can hold string literal types and comments,
// and an angle bracket inside either is not one: the element's attributes
// and children start after the real closing `>`.

declare function Box<T>(p: { children?: unknown }): any;
export const okQuotedLess = <Box<() => "<">>08 px</Box>;
export const okQuotedGreater = <Box<'>' /* > */>>08 px</Box>;
export const badAfter: string = 1;
