// tsc --strict: TS2769 — No overload matches this call.
function parse(value: string): string
function parse(value: number): number
function parse(value: string | number): string | number {
  return value
}

export const result = parse(true)
