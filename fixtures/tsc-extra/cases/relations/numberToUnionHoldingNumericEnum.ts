// @strict: true
// @target: esnext

// A numeric enum accepts any `number`, and so does a union holding one: an
// optional property typed by the enum (`BooleanNumber | undefined`) takes a
// `number` and a numeric conditional. A string enum does not, and a string
// is not a numeric enum.

enum BooleanNumber { FALSE = 0, TRUE = 1 }
enum Mode { A = "a", B = "b" }
interface S { keepLines?: BooleanNumber; mode?: Mode }

function okNumberIntoOptionalEnum(s: S, n: number) { s.keepLines = n; }
function okConditionalIntoOptionalEnum(s: S, v: boolean) { s.keepLines = v ? 1 : 0; }
function okNumberIntoEnumUnion(n: number) { const e: BooleanNumber | null = n; }
function badStringIntoNumericEnumUnion() { const e: BooleanNumber | undefined = "x"; }
function badNumberIntoStringEnum(s: S, n: number) { s.mode = n; }
