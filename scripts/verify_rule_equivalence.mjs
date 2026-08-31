// Every rewrite, checked against every awkward value.
//
// A peephole rewrite is a claim: "these two expressions mean the same
// thing". Most of the claims in `src/transform/peephole.mbt` are true
// only for SOME inputs, and the ones that were wrong said so in a
// comment and checked nothing:
//
//   //   x !== false    -> x     (saves 7 bytes)
//
// That is true when `x` is a boolean. TypeScript's binder writes
// `symbol.constEnumOnlyModule !== false` on a field that is usually
// `undefined`, `undefined !== false` is `true`, and the rewrite left
// `undefined` behind. Same story for `!(a < b)` -> `a >= b`, which is
// false for `a = undefined` because every NaN comparison is false.
//
// Neither the corpus nor the fuzzer nor the real-package suite is the
// right shape to find that. They ask "does this program still behave?"
// on programs built from ordinary values. This asks the narrower
// question directly: for each rewrite, does it hold for `undefined`,
// `-0`, `NaN`, a Symbol, a BigInt, an object with a poisoned `valueOf`,
// an array-like with a negative `length`?
//
// How it works. Each case is a function body with up to two holes, `a`
// and `b`. One generated program per case evaluates that body across
// the CROSS PRODUCT of the value domain — so one compile covers ~600
// input pairs — and the results are compared three ways:
//
//   reference   Node running the TypeScript directly (type stripping);
//               nothing of ours touches it
//   plain       mtsc --bundle, no optimization
//   optimized   mtsc --bundle --fold --minify
//
// `optimized != reference` while `plain == reference` is an optimizer
// bug. `plain != reference` is a lowering bug and says so. And when
// `optimized`'s body is textually the same as `plain`'s, the case is
// reported INERT: the rewrite never fired, so the case proves nothing
// and needs rewriting.
//
// Usage:
//   node scripts/verify_rule_equivalence.mjs [--only <name>] [--rule <rule>]
//                                           [--verbose] [--update]

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const EXPECTED = path.join(ROOT, "fixtures", "rule-equivalence", "expected.json");

const MTSC_CANDIDATES = [
  path.join(ROOT, "_build", "native", "release", "build", "cmd", "mtsc", "mtsc.exe"),
  path.join(ROOT, "_build", "native", "debug", "build", "cmd", "mtsc", "mtsc.exe"),
];

function findMtsc() {
  for (const candidate of MTSC_CANDIDATES) if (fs.existsSync(candidate)) return candidate;
  console.error("verify_rule_equivalence: mtsc binary not found. Run `moon build --target native`.");
  process.exit(2);
}

const MTSC = findMtsc();
const PLAIN_FLAGS = ["--bundle", "--no-check"];
const OPT_FLAGS = ["--bundle", "--no-check", "--fold", "--minify"];

// ---------------------------------------------------------------
// The value domain
// ---------------------------------------------------------------
//
// Chosen so that each entry is a counterexample to some plausible
// rewrite, not for coverage of "typical" values. `{ length: -1 }` and
// `{ length: NaN }` exist because `x.length > 0 -> !!x.length` assumes
// a non-negative integer; the poisoned `valueOf` exists because
// `x.toString() -> "" + x` assumes they agree; `Symbol` and `BigInt`
// exist because they throw where every other value converts.
//
// The getter is the READ hazard, and it was missing while the poisoned
// `valueOf` — the COERCION hazard — had been here from the start. A
// property read runs arbitrary code when the property is an accessor,
// and `is_pure_value` called `h.p` pure whenever `h` was, which is a
// statement about evaluating `h` rather than about reading `.p` off it.
// Four shapes dropped the getter body outright. It counts on itself so
// the effect is visible in the compared VALUE: `a.hits` after a read of
// `a.tick` says whether the read happened.

const DOMAIN = [
  "undefined",
  "null",
  "0",
  "-0",
  "1",
  "-1",
  // Non-integers. The domain had none, so every rule that TRUNCATES
  // rather than preserves — `~~x`, `x | 0`, a shift — could pass on
  // integers alone. `~~1.5` is `1`, which is the canonical
  // counterexample to reading `~~` as an identity.
  "1.5",
  "-1.5",
  "NaN",
  "Infinity",
  '""',
  '"0"',
  '"a"',
  "true",
  "false",
  "[]",
  "[1]",
  "{}",
  "{ p: 1 }",
  "{ length: 0 }",
  "{ length: -1 }",
  "{ length: NaN }",
  "{ length: undefined }",
  // A genuine array-LIKE: `length` plus index properties, and no
  // `Symbol.iterator`. Every `Array.from(x)` / `Array.prototype.M.call(x)`
  // / `x.slice(0)` rewrite that reaches for a spread or a method call
  // assumes this is an Array, and it is the shape those built-ins exist
  // to handle.
  '{ length: 2, 0: "a", 1: "b" }',
  "{ size: -1 }",
  "{ toString() { return 's'; }, valueOf() { return 1; } }",
  "{ hits: 0, get tick() { this.hits += 1; return this.hits; } }",
  "{ hasOwnProperty() { return 'own'; } }",
  "Symbol.for('s')",
  "10n",
];

// ---------------------------------------------------------------
// The cases
// ---------------------------------------------------------------
//
// `body` is the function body, with `a` and `b` in scope as `any`.
// `rule` names the peephole/fold rule it exercises, so a failure names
// the rewrite to go and gate. `holes: 1` skips the second loop, which
// is only about run time.

const CASES = [
  // --- comparisons against boolean literals (fixed; regression cases)
  {
    rule: "booleans",
    name: "ne-false",
    holes: 1,
    body: "return a !== false;",
  },
  {
    rule: "booleans",
    name: "eq-true",
    holes: 1,
    body: "return a === true;",
  },
  {
    rule: "booleans",
    name: "eq-false",
    holes: 1,
    body: "return a === false;",
  },
  {
    rule: "booleans",
    name: "ne-true",
    holes: 1,
    body: "return a !== true;",
  },

  // --- negated relational operators (fixed; regression cases)
  {
    rule: "comparisons",
    name: "not-lt",
    body: "return !(a < b);",
  },
  {
    rule: "comparisons",
    name: "not-ge",
    body: "return !(a >= b);",
  },
  {
    rule: "comparisons",
    name: "not-eq",
    body: "return !(a === b);",
  },

  // --- length / size comparisons
  {
    rule: "comparisons",
    name: "length-ne-zero",
    holes: 1,
    body: "return a.length !== 0;",
  },
  {
    rule: "comparisons",
    name: "length-gt-zero",
    holes: 1,
    body: "return a.length > 0;",
  },
  {
    rule: "comparisons",
    name: "length-le-zero",
    holes: 1,
    body: "return a.length <= 0;",
  },
  {
    rule: "comparisons",
    name: "size-eq-zero",
    holes: 1,
    body: "return a.size === 0;",
  },

  // --- conditional shapes
  {
    rule: "conditionals",
    name: "cond-or-void",
    body: "return a ? b : void 0;",
  },
  {
    rule: "conditionals",
    name: "cond-self-then",
    body: "return a ? a : b;",
  },
  {
    rule: "conditionals",
    name: "cond-self-else",
    body: "return a ? b : a;",
  },
  {
    rule: "conditionals",
    name: "cond-negated-test",
    body: "return !a ? b : a;",
  },
  {
    rule: "conditionals",
    name: "nullish-from-cond",
    body: "return a == null ? b : a;",
  },
  {
    rule: "conditionals",
    name: "optional-chain-from-cond",
    holes: 1,
    body: "return a != null ? a.p : void 0;",
  },

  // --- arithmetic identities
  {
    rule: "evaluate",
    name: "add-zero-left",
    holes: 1,
    body: "return 0 + a;",
  },
  {
    rule: "evaluate",
    name: "add-zero-right",
    holes: 1,
    body: "return a + 0;",
  },
  {
    rule: "evaluate",
    name: "sub-zero",
    holes: 1,
    body: "return a - 0;",
  },
  {
    rule: "evaluate",
    name: "mul-one",
    holes: 1,
    body: "return a * 1;",
  },
  {
    rule: "evaluate",
    name: "double-negation",
    holes: 1,
    body: "return !!a;",
  },
  {
    rule: "evaluate",
    name: "double-negation-in-if",
    holes: 1,
    body: "if (!!a) { return 1; } return 2;",
  },

  // --- typeof
  {
    rule: "typeofs",
    name: "typeof-eq-undefined",
    holes: 1,
    body: "return typeof a === 'undefined';",
  },
  {
    rule: "typeofs",
    name: "typeof-ne-undefined",
    holes: 1,
    body: "return typeof a !== 'undefined';",
  },

  // --- method-call rewrites
  {
    rule: "properties",
    name: "to-string",
    holes: 1,
    body: "return a.toString();",
  },
  {
    rule: "properties",
    name: "has-own-property",
    body: "return a.hasOwnProperty(b);",
  },
  {
    rule: "properties",
    name: "has-own-property-call",
    body: "return Object.prototype.hasOwnProperty.call(a, b);",
  },
  {
    rule: "properties",
    name: "slice-call-copy",
    holes: 1,
    body: "return Array.prototype.slice.call(a, 0);",
  },
  {
    rule: "properties",
    name: "indirect-call",
    holes: 1,
    body: "return (0, a.toString)();",
  },
  {
    rule: "properties",
    name: "parse-int",
    holes: 1,
    body: "return Number.parseInt(a);",
  },

  // --- assignment shapes
  {
    rule: "reduce_vars",
    name: "nullish-assign",
    body: "let t = a; if (t == null) { t = b; } return t;",
  },
  {
    rule: "reduce_vars",
    name: "hoist-common-assign",
    body: "let t; if (a) { t = a; } else { t = b; } return t;",
  },

  // --- string / template
  {
    rule: "evaluate",
    name: "template-no-exprs",
    holes: 1,
    body: "return `text`;",
  },
  {
    rule: "evaluate",
    name: "template-with-hole",
    holes: 1,
    body: "return `k${a}`;",
  },
  {
    rule: "evaluate",
    name: "string-concat",
    holes: 1,
    body: "return 'a' + 'b' + a;",
  },

  // --- switch lowering
  {
    rule: "switches",
    name: "switch-two-cases",
    holes: 1,
    body: "switch (a) { case 0: return 'z'; case 1: return 'o'; default: return 'd'; }",
  },

  // --- the inliner's own claim
  {
    rule: "collapse_vars",
    name: "single-use-binding",
    body: "const t = a + 1; return t * b;",
  },

  // --- built-in method rewrites
  //
  // This block exists because of what it found. typebox's
  // `Array.from({ length: 256 }).map(…)` was compiled to
  // `[...{ length: 256 }].map(…)`, which throws: `Array.from` accepts an
  // array-LIKE and a spread needs an ITERABLE. The rewrite had a comment
  // saying only that the two-arg form must be left alone, and the
  // neighbouring `Array.prototype.slice.call` rewrite had already been
  // removed for EXACTLY this reason — so the knowledge was three lines
  // away and the rule still shipped.
  //
  // The reason it shipped is structural: this harness covers the rules
  // somebody wrote a case for, and nothing reports which rules have
  // none. peephole and fold carry ~235 rewrites between them. So every
  // rewrite whose validity depends on the RECEIVER'S TYPE gets a case
  // here, whether or not it currently looks suspect — that is the
  // subset where "assumes a type and checks nothing" can hide.
  {
    rule: "arrays",
    name: "array-from-single-arg",
    holes: 1,
    body: "return Array.from(a);",
  },
  {
    rule: "arrays",
    name: "array-proto-slice-call",
    holes: 1,
    body: "return Array.prototype.slice.call(a);",
  },
  {
    rule: "arrays",
    name: "array-proto-method-call",
    holes: 1,
    body: "return Array.prototype.indexOf.call(a, 'a');",
  },
  {
    rule: "arrays",
    name: "slice-zero",
    holes: 1,
    body: "return a.slice(0);",
  },
  {
    rule: "arrays",
    name: "empty-concat",
    holes: 1,
    body: "return [].concat(a);",
  },
  {
    rule: "objects",
    name: "object-assign-literal-target",
    body: "return Object.assign({ k: 1 }, a, b);",
  },
  {
    rule: "objects",
    name: "hasownproperty-call",
    holes: 1,
    body: "return Object.prototype.hasOwnProperty.call(a, 'p');",
  },
  {
    rule: "numbers",
    name: "number-parseint",
    holes: 1,
    body: "return Number.parseInt(a);",
  },
  {
    rule: "numbers",
    name: "number-parsefloat",
    holes: 1,
    body: "return Number.parseFloat(a);",
  },
  {
    rule: "numbers",
    name: "math-pow",
    body: "return Math.pow(a, b);",
  },

  // --- bitwise identities and annihilators
  //
  // This harness had no bitwise case at all, and six rules in that
  // table turned out to be wrong: it reports nothing about the rules
  // nobody wrote a case for, which is the same hole `Array.from(x)`
  // shipped through. The whole family is here now, not just the ones
  // that were broken, because what makes them wrong is a property of
  // the OPERATORS — they coerce, and an identity rewrite hands the
  // operand back uncoerced — so every rule over them is suspect until
  // a case says otherwise.
  //
  // The operands that matter: a string (`"alpha" & -1` is `0`), a
  // non-integer (`1.5 & -1` is `1`), a BigInt (`5n ^ 5n` is `0n`, and
  // mixing throws), a Symbol (throws). All four are in the domain.
  // --- unary double-application
  //
  // Not one case covered these either, and three of the four rules over
  // them were wrong. `-(-x)` and `~(~x)` were both gated on PURITY,
  // which is a statement about side effects and says nothing about the
  // COERCION each operator applies: `-(-"alpha")` is `NaN`, `~~1.5` is
  // `1`, `~~"alpha"` is `0`. The fuzzer found the first one at seed 480
  // (export shape) after these rules had shipped for months. `-(a - b)`
  // -> `b - a` was deleted rather than gated: the two differ at zero
  // (`-(1 - 1)` is `-0`), and nothing here can prove `a - b != 0`.
  {
    rule: "numbers",
    name: "neg-neg",
    holes: 1,
    body: "return - (- a);",
  },
  {
    rule: "numbers",
    name: "bitnot-bitnot",
    holes: 1,
    body: "return ~ (~ a);",
  },
  {
    rule: "numbers",
    name: "neg-of-difference",
    holes: 2,
    body: "return - (a - b);",
  },
  // The boolean-context form IS valid — `if (!!x)` coerces anyway — so
  // this case exists to keep the correct rule from being "fixed" too.
  {
    rule: "numbers",
    name: "not-not-in-condition",
    holes: 1,
    body: "if (!! a) { return 1; } return 2;",
  },
  {
    rule: "numbers",
    name: "and-minus-one",
    holes: 1,
    body: "return a & -1;",
  },
  {
    rule: "numbers",
    name: "minus-one-and",
    holes: 1,
    body: "return -1 & a;",
  },
  {
    rule: "numbers",
    name: "and-zero",
    holes: 1,
    body: "return a & 0;",
  },
  {
    rule: "numbers",
    name: "or-minus-one",
    holes: 1,
    body: "return a | -1;",
  },
  {
    rule: "numbers",
    name: "pow-zero",
    holes: 1,
    body: "return a ** 0;",
  },
  // The self-operand rules. `x | x`, `x & x`, `x ^ x` and `x - x` were
  // all gated on nothing but "both sides are the same variable", which
  // proves purity and proves nothing about the arithmetic.
  {
    rule: "numbers",
    name: "self-or",
    holes: 1,
    body: "return a | a;",
  },
  {
    rule: "numbers",
    name: "self-and",
    holes: 1,
    body: "return a & a;",
  },
  {
    rule: "numbers",
    name: "self-xor",
    holes: 1,
    body: "return a ^ a;",
  },
  {
    rule: "numbers",
    name: "self-sub",
    holes: 1,
    body: "return a - a;",
  },
  // The arithmetic identities that DID have a numeric gate, to pin the
  // BigInt hole: `is_number_valued` delegated to a classifier that
  // calls a BigInt literal a number, so `5n - 0` folded to `5n` where
  // the source throws.
  {
    rule: "numbers",
    name: "sub-zero",
    holes: 1,
    body: "return a - 0;",
  },
  {
    rule: "numbers",
    name: "mul-one",
    holes: 1,
    body: "return a * 1;",
  },
  {
    rule: "numbers",
    name: "div-one",
    holes: 1,
    body: "return a / 1;",
  },
  {
    rule: "numbers",
    name: "add-zero",
    holes: 1,
    body: "return a + 0;",
  },

  // --- a property READ is not free
  //
  // `is_pure_value` answered "pure" for `h.p` whenever `h` was pure,
  // which is a statement about evaluating `h`, not about reading `.p`
  // off it. Reading an accessor runs its body. Each of these four
  // dropped it, and each is a different rule doing so — a discarded
  // expression statement, the array-literal length fold, a comma whose
  // left operand is thrown away, and `void EXPR`.
  //
  // `a.tick` increments `a.hits`, so returning `a.hits` says whether
  // the read happened. Every other domain entry answers `undefined`
  // for both, which is stable across the three legs and costs nothing.
  {
    rule: "properties",
    name: "getter-read-as-statement",
    holes: 1,
    body: "a.tick; return a.hits;",
  },
  {
    rule: "properties",
    name: "getter-read-in-array-length",
    holes: 1,
    // Returns a SCALAR that encodes both halves. An array return
    // compared equal here even with the optimized body visibly reading
    // `[2, a.hits]` instead of running the getter — so the case looked
    // like coverage and was not. Anything asserting "the effect
    // happened" has to land in the compared value itself.
    body: "const n = [a.tick, 1].length; return n + a.hits * 10;",
  },
  {
    rule: "properties",
    name: "getter-read-in-discarded-comma",
    holes: 1,
    body: "const n = (a.tick, 9); return n + a.hits * 10;",
  },
  {
    rule: "properties",
    name: "getter-read-under-void",
    holes: 1,
    body: "void a.tick; return a.hits;",
  },
  {
    rule: "functions",
    name: "call-null-this",
    holes: 1,
    body: "const f = function () { return arguments.length; }; return f.call(null, a);",
  },
  {
    rule: "functions",
    name: "apply-null-this",
    holes: 1,
    body: "const f = function () { return arguments.length; }; return f.apply(null, a);",
  },

  // --- array-literal folds over a SPREAD element
  //
  // Second family with the same shape as the built-in methods above, and
  // the same reason for existing. Every `fold_array_method` case reads
  // `items` positionally — its length, its order, which element sits
  // where — and a `Spread` is one AST node standing for however many
  // values the spread yields at runtime.
  //
  // remeda's `reverse` is `return [...array].reverse()`. That is a
  // one-element `ArrayLit`, reversing one element is a no-op, and the
  // fold returned `[...array]`: `reverse([1, 2, 3])` gave `[1, 2, 3]`.
  // The `is_pure_value` guard each fold carries did not help, because a
  // spread of a variable IS pure — purity was never the question.
  //
  // The `.length` fold had already been given a spread guard, by the
  // fuzzer, and the lesson stopped at that one call site. So: a case per
  // fold that reads a position.
  {
    rule: "arrays",
    name: "spread-literal-reverse",
    holes: 1,
    body: "return [...a].reverse();",
  },
  {
    rule: "arrays",
    name: "spread-literal-length",
    holes: 1,
    body: "return [...a].length;",
  },
  {
    rule: "arrays",
    name: "spread-literal-index",
    holes: 1,
    body: "return [...a][0];",
  },
  {
    rule: "arrays",
    name: "spread-literal-indexof",
    holes: 1,
    body: "return [...a].indexOf(1);",
  },
  {
    rule: "arrays",
    name: "spread-literal-join",
    holes: 1,
    body: "return [...a].join(\"-\");",
  },
  {
    rule: "arrays",
    name: "spread-literal-includes",
    holes: 1,
    body: "return [...a].includes(1);",
  },
  {
    rule: "arrays",
    name: "spread-literal-slice",
    holes: 1,
    body: "return [...a].slice(1);",
  },
  {
    rule: "arrays",
    name: "spread-literal-concat",
    body: "return [...a].concat([b]);",
  },
  {
    rule: "arrays",
    name: "spread-literal-mixed",
    body: "return [1, ...a, 2].reverse();",
  },
];

// ---------------------------------------------------------------
// The generated program
// ---------------------------------------------------------------
//
// Identical for every case except `run`'s body, so a miscompilation of
// the harness itself would fail every case at once — which is how you
// tell it apart from a miscompilation of one rewrite.

function program(testCase) {
  const holes = testCase.holes ?? 2;
  const inner = holes === 2 ? "  for (const b of D) push(x, b);\n" : "  push(x, undefined);\n";
  return `// generated by scripts/verify_rule_equivalence.mjs — do not edit
const D: any[] = [
${DOMAIN.map((v) => `  ${v},`).join("\n")}
];

function run(a: any, b: any): any {
${testCase.body
  .split("\n")
  .map((line) => `  ${line}`)
  .join("\n")}
}

// Tagged, because JSON.stringify cannot tell \`undefined\` from a missing
// property and turns NaN / -0 / Infinity all into null — which are
// exactly the values a folding bug produces.
function enc(v: any): string {
  const t = typeof v;
  if (t === "symbol") return "symbol:" + String(v);
  if (t === "bigint") return "bigint:" + String(v);
  // NOT \`Object.is(v, -0)\`: the folder rewrites the \`-0\` literal to \`0\`,
  // which makes this encoder report every zero as negative and turns the
  // whole harness into a liar. \`1 / v\` needs no literal.
  if (t === "number") return "number:" + (v === 0 && 1 / v < 0 ? "-0" : String(v));
  if (t === "function") return "function";
  if (v === null) return "null";
  if (t === "object") return "object:" + Object.keys(v).join(",");
  return t + ":" + String(v);
}

const out: string[] = [];
function push(a: any, b: any): void {
  try {
    out.push(enc(run(a, b)));
  } catch (e: any) {
    out.push("threw:" + (e && e.name ? String(e.name) : "Error"));
  }
}

for (const x of D) {
${inner}}
console.log(out.join("\\n"));
`;
}

// ---------------------------------------------------------------
// Running
// ---------------------------------------------------------------

const WORK = fs.mkdtempSync(path.join(os.tmpdir(), "rule-equiv-"));

function run(command, args, cwd) {
  return spawnSync(command, args, { cwd, encoding: "utf8", maxBuffer: 1 << 26 });
}

function compile(input, output, flags) {
  const r = run(MTSC, [input, ...flags, "--out", output]);
  if (r.status !== 0 || !fs.existsSync(output)) {
    const line = (r.stdout || r.stderr || "").split("\n").find((l) => l.trim().length > 0);
    return { ok: false, why: line || `exit ${r.status}` };
  }
  return { ok: true };
}

function observe(file) {
  const r = run("node", [file]);
  if (r.status !== 0) {
    const line = (r.stderr || "").split("\n").find((l) => /Error/.test(l));
    return { ok: false, why: line || `exit ${r.status}` };
  }
  return { ok: true, out: r.stdout };
}

/// `run`'s body as the compiler left it. Comparing it between the plain
/// and optimized builds answers "did any rewrite actually fire", which
/// a passing case does not.
function extractRun(file) {
  const src = fs.readFileSync(file, "utf8");
  const m = src.match(/function run\(([^)]*)\)\s*\{/);
  if (!m) return null;
  let i = src.indexOf("{", m.index);
  let depth = 0;
  let inStr = null;
  for (let j = i; j < src.length; j++) {
    const c = src[j];
    if (inStr) {
      if (c === "\\") {
        j += 1;
        continue;
      }
      if (c === inStr) inStr = null;
      continue;
    }
    if (c === '"' || c === "'" || c === "`") {
      inStr = c;
      continue;
    }
    if (c === "{") depth += 1;
    else if (c === "}") {
      depth -= 1;
      if (depth === 0) return src.slice(i, j + 1).replace(/\s+/g, "");
    }
  }
  return null;
}

/// The first differing row, with the inputs that produced it. A case
/// covers hundreds of pairs and printing the whole list buries the one
/// that matters.
function firstDifference(left, right, holes) {
  const l = left.split("\n");
  const r = right.split("\n");
  const rows = Math.max(l.length, r.length);
  for (let i = 0; i < rows; i++) {
    if (l[i] === r[i]) continue;
    const inputs =
      holes === 2
        ? `a = ${DOMAIN[Math.floor(i / DOMAIN.length)]}, b = ${DOMAIN[i % DOMAIN.length]}`
        : `a = ${DOMAIN[i]}`;
    return { index: i, inputs, left: l[i], right: r[i] };
  }
  return null;
}

// ---------------------------------------------------------------
// Main
// ---------------------------------------------------------------

const argv = process.argv.slice(2);
let only = null;
let ruleFilter = null;
let verbose = false;
let update = false;
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === "--only") only = argv[++i];
  else if (argv[i] === "--rule") ruleFilter = argv[++i];
  else if (argv[i] === "--verbose") verbose = true;
  else if (argv[i] === "--update") update = true;
  else {
    console.error(`verify_rule_equivalence: unknown argument ${argv[i]}`);
    process.exit(2);
  }
}

const expected = fs.existsSync(EXPECTED) ? JSON.parse(fs.readFileSync(EXPECTED, "utf8")) : {};

console.log(`rewrite equivalence over ${DOMAIN.length} values\n`);

const results = {};
const counts = {};
let regressions = 0;
const unsound = [];

for (const testCase of CASES) {
  if (only && only !== testCase.name) continue;
  if (ruleFilter && ruleFilter !== testCase.rule) continue;

  const dir = path.join(WORK, testCase.name);
  fs.mkdirSync(dir, { recursive: true });
  const src = path.join(dir, "in.ts");
  fs.writeFileSync(src, program(testCase));

  const plain = path.join(dir, "plain.mjs");
  const opt = path.join(dir, "opt.mjs");

  let verdict;
  let detail = "";
  const holes = testCase.holes ?? 2;

  const reference = observe(src);
  const cPlain = compile(src, plain, PLAIN_FLAGS);
  const cOpt = compile(src, opt, OPT_FLAGS);

  if (!reference.ok) {
    verdict = "BADCASE";
    detail = `the case's own source does not run: ${reference.why}`;
  } else if (!cPlain.ok || !cOpt.ok) {
    verdict = "BROKEN";
    detail = `compile failed: ${cPlain.why ?? cOpt.why}`;
  } else {
    const oPlain = observe(plain);
    const oOpt = observe(opt);
    if (!oPlain.ok) {
      verdict = "LOWERING";
      detail = `unoptimized bundle threw: ${oPlain.why}`;
    } else if (oPlain.out !== reference.out) {
      const d = firstDifference(reference.out, oPlain.out, holes);
      verdict = "LOWERING";
      detail = d ? `${d.inputs}: reference ${d.left} vs plain ${d.right}` : "differs";
    } else if (!oOpt.ok) {
      verdict = "UNSOUND";
      detail = `optimized bundle threw: ${oOpt.why}`;
    } else if (oOpt.out !== reference.out) {
      const d = firstDifference(reference.out, oOpt.out, holes);
      verdict = "UNSOUND";
      detail = d ? `${d.inputs}: expected ${d.left}, got ${d.right}` : "differs";
    } else {
      const bPlain = extractRun(plain);
      const bOpt = extractRun(opt);
      if (bPlain === null || bOpt === null) {
        verdict = "ok";
        detail = "equivalent (body not locatable)";
      } else if (bPlain === bOpt) {
        verdict = "INERT";
        detail = "no rewrite fired — the case proves nothing";
      } else {
        verdict = "ok";
        detail = "equivalent";
      }
      if (verbose) {
        console.log(`         plain: ${bPlain}`);
        console.log(`         opt:   ${bOpt}`);
      }
    }
  }

  results[testCase.name] = verdict;
  counts[verdict] = (counts[verdict] ?? 0) + 1;

  const was = expected[testCase.name];
  let tag = "     ";
  if (was && was !== verdict) {
    if (verdict === "ok") tag = " NEW ";
    else {
      tag = "REGR!";
      regressions += 1;
    }
  }

  const mark = {
    ok: " ok  ",
    INERT: "inert",
    UNSOUND: "UNSND",
    LOWERING: "LOWER",
    BROKEN: "FAIL ",
    BADCASE: "??   ",
  }[verdict];
  console.log(
    `  [${mark}]${tag} ${testCase.rule.padEnd(16)} ${testCase.name.padEnd(26)} ${detail}`,
  );
  if (verdict === "UNSOUND") unsound.push({ ...testCase, detail });
}

console.log("");
console.log(
  `  ${counts.ok ?? 0} equivalent, ${counts.INERT ?? 0} inert, ` +
    `${counts.UNSOUND ?? 0} unsound, ${counts.LOWERING ?? 0} lowering, ` +
    `${counts.BROKEN ?? 0} broken, ${counts.BADCASE ?? 0} bad case(s)`,
);

if (unsound.length > 0) {
  console.log("\n  rewrites that are not equivalence-preserving:\n");
  for (const u of unsound) {
    console.log(`    ${u.rule.padEnd(16)} ${u.name}`);
    console.log(`      ${u.body.split("\n")[0]}`);
    console.log(`      ${u.detail}`);
  }
}

if (update) {
  fs.mkdirSync(path.dirname(EXPECTED), { recursive: true });
  fs.writeFileSync(EXPECTED, `${JSON.stringify(results, null, 2)}\n`);
  console.log(`\n  wrote ${path.relative(ROOT, EXPECTED)}`);
}

fs.rmSync(WORK, { recursive: true, force: true });

if ((counts.BADCASE ?? 0) > 0) {
  console.error("\n  a case's own source does not run — fix the case, not the compiler");
  process.exit(2);
}
if (regressions > 0) {
  console.error(`\n  ${regressions} regression(s) against ${path.relative(ROOT, EXPECTED)}`);
  process.exit(1);
}
