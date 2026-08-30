// neverthrow, used the way its README's first examples use it: a
// `Result` chain over a discriminated success/failure, plus `safeTry`.
//
// Every export is a scalar.

import { err, ok, Result, safeTry } from "./src/index.ts";

type ParseError =
  | { kind: "empty" }
  | { kind: "not-a-number"; text: string }
  | { kind: "negative"; value: number };

function parse(text: string): Result<number, ParseError> {
  if (text === "") return err({ kind: "empty" });
  const n = Number(text);
  if (Number.isNaN(n)) return err({ kind: "not-a-number", text });
  if (n < 0) return err({ kind: "negative", value: n });
  return ok(n);
}

function describe(e: ParseError): string {
  switch (e.kind) {
    case "empty":
      return "empty";
    case "not-a-number":
      return "nan(" + e.text + ")";
    case "negative":
      return "neg(" + e.value + ")";
  }
}

function total(a: string, b: string): string {
  return safeTry<number, ParseError>(function* () {
    const x = yield* parse(a);
    const y = yield* parse(b);
    return ok(x + y);
  }).match((v) => "sum:" + v, (e) => "err:" + describe(e));
}

export const doubled: string = parse("21").map((n) => n * 2).unwrapOr(-1) + "";
export const chained: string = parse("4")
  .andThen((n) => parse(String(n * 2)))
  .map((n) => n + 1)
  .match((v) => "ok:" + v, (e) => "err:" + describe(e));
export const failures: string = ["", "abc", "-3"]
  .map((t) => parse(t).match(() => "?", describe))
  .join("|");
export const sums: string = [total("1", "2"), total("1", "x"), total("", "2")]
  .join("|");
