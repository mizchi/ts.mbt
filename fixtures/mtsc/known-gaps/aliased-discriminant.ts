// tsc --strict: TS2339 — Property 'number' does not exist on type '{ text: string }'.
type Value =
  | { kind: "text"; payload: { text: string } }
  | { kind: "number"; payload: { number: number } }

export function format(value: Value): string {
  const kind = value.kind
  if (kind === "text") {
    return value.payload.number.toFixed()
  }
  return ""
}
