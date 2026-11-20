// @strict: true
// @target: esnext

// TypeScript 4.4 inlines an unannotated `const` used as a condition, so
// `const column = line?.parent; if (!column) return` narrows `line` through
// the optional chain. Narrowing the chain's receiver does not narrow a
// value read from it.

interface Col { lines: Line[] }
interface Line { divides: Div[]; parent?: Col }
interface Div { parent?: Line }
interface Glyph { parent?: Div }

export function ok(glyph: Glyph) {
  const divide = glyph.parent;
  const line = divide?.parent;
  const column = line?.parent;
  if (!divide || !column) return;
  return line.divides.indexOf(divide) + column.lines.indexOf(line);
}
export function bad(glyph: Glyph) {
  const divide = glyph.parent;
  const line = divide?.parent;
  if (!divide) return;
  return line.divides;
}
