// Every pass that resolves a NAME against a bundle-wide table, and the
// scopes that re-bind those names.
//
// `call_inline.mbt` documents this at the top of the file: a table keyed
// by name, carried unchanged into every scope, means the wrong thing the
// moment a scope re-binds one of its names. Four other passes were
// carrying tables the same way and none of them narrowed:
//
//   as_const_inline   `const S = [...]` shadowed by an inner `const S`
//                     or by a PARAMETER named `S`
//   const_enum_inline `const enum E` shadowed the same two ways —
//                     visible under plain `--bundle`, no flags
//   predicate_inline  a type guard shadowed by a local function or a
//                     parameter of the same name
//   switch_fold       a literal-union dispatcher shadowed by a parameter
//   type_fold         a nested declaration with no useful type left the
//                     OUTER binding's annotation visible
//
// Every one produced a WRONG VALUE rather than a crash or a free
// variable, so `--verify` cannot see any of them: every name still
// resolves. Only running the output catches this.
//
// Each group below pairs a shadowed read (must use the INNER binding)
// with an unshadowed one (must still be optimized).

// ---- as_const_inline -------------------------------------------------
const STATUSES = ["ok", "warn"];
const HTTP = { OK: 200 };

function statusInner(): string {
  const STATUSES = ["x", "y"];
  return STATUSES[0];
}
function statusParam(STATUSES: string[]): string {
  return STATUSES[0];
}
function httpInner(): number {
  const HTTP = { OK: 99 };
  return HTTP.OK;
}
const statusOuter = STATUSES[0];
const httpOuter = HTTP.OK;

// ---- const_enum_inline ----------------------------------------------
const enum Arch {
  X64 = 1,
  Arm = 2,
}

function archInner(): number {
  const Arch = { X64: 90 };
  return Arch.X64;
}
function archParam(Arch: { X64: number }): number {
  return Arch.X64;
}
const archOuter = Arch.Arm;

// ---- predicate_inline ------------------------------------------------
function isNeg(v: number): v is number {
  return !v;
}

function predInner(v: number): boolean {
  function isNeg(x: number) {
    return x === 7;
  }
  return isNeg(v);
}
function predParam(isNeg: (n: number) => boolean, v: number): boolean {
  return isNeg(v);
}
const predOuter = isNeg(0);

// ---- switch_fold -----------------------------------------------------
function dispatch(k: "a" | "b"): number {
  switch (k) {
    case "a":
      return 1;
    case "b":
      return 2;
  }
}

function swParam(dispatch: (k: "a") => number): number {
  return dispatch("a");
}
const swOuter = dispatch("b");

// ---- type_fold -------------------------------------------------------
function tfInner(s: string): boolean {
  {
    const s = 5 as unknown;
    return typeof s === "string";
  }
}
function tfOuter(s: string): boolean {
  return typeof s === "string";
}

export const report = {
  statusInner: statusInner(),
  statusParam: statusParam(["param"]),
  httpInner: httpInner(),
  statusOuter,
  httpOuter,
  archInner: archInner(),
  archParam: archParam({ X64: 7 }),
  archOuter,
  predInner: predInner(7),
  predParam: predParam((n) => n === 3, 3),
  predOuter,
  swParam: swParam(() => 42),
  swOuter,
  tfInner: tfInner("x"),
  tfOuter: tfOuter("x"),
};
console.log(JSON.stringify(report));
