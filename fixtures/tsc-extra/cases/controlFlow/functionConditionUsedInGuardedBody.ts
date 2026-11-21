// @strict: true
// @target: esnext

// TS2774 ("this condition will always return true since this function is
// always defined") is not reported when the tested function is used in the
// guarded region: the `if` body, the true branch of a ternary, or the right
// operand of `&&`. A use after the region does not count.

declare function f(): number;
declare const g: () => number;
export function okUsedAnd() { return f && f(); }
export function badUnusedAnd() { return f && 1; }
export function okUsedIf() { if (f) { f(); } }
export function okUsedTernary() { return f ? f() : 0; }
export function badUnusedIf() { if (g) { return 1; } return 0; }
export function okUsedAsValue() { if (g) { const h = g; return h; } return 0; }
export function okUsedInConditionAnd() { if (g && g()) { return 1; } return 0; }

interface P { onChange?: (v: string) => void; disabled?: boolean; value?: string }
export function okNarrowedOptional(props: P) {
  const { onChange, disabled, value } = props;
  if (!onChange || disabled) { return; }
  if (typeof value !== "undefined") {
    onChange && onChange(value);
  }
}
