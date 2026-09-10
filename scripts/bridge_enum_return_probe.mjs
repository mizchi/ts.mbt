// Does the JS emitted for a declaration that PROMISES a payload-bearing enum
// actually build one?
//
// A MoonBit `pub(all) enum` with a payload is `{ "$tag": i, "_0": v }` at the
// JS boundary — the repo's own generated constructor says so
// (`__ts_mbt_server_type_from_server(value) { return { "$tag": 0, "_0": value
// }; }`). A wrapper that hands back the raw JS value instead leaves a MoonBit
// `match` reading `$tag` off something that has none.
//
// Two sections, because a declaration's implementation lands in one of two
// places and each needs a different question asked:
//
//   A. a named `bridge.js` wrapper (`export function __ts_mbt_<name>(…)`),
//      which can call the `_from_js` helper by name;
//   B. an `extern "js" fn` whose body is an INLINE lambda (`#| (self) =>
//      self.path`), which cannot import that helper, so the conversion has to
//      be inlined into the body.
//
// The first version of this probe had only section A and matched
// `declare pub fn NAME(`, so every `Type::method` and `fn[T]` form was
// skipped — which is most of what a class-heavy package declares, and all
// four of the accessor sites that turned out to be broken.
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname, basename } from "node:path";

// The declared backlog. An occurrence not listed fails; a listed entry that no
// longer occurs is STALE and also fails, which is the only mechanism that keeps
// such a file from turning into a suppression list.
const DECLARED_FILE = "scripts/bridge_unconverted_enum_crossings.txt";
function readDeclared() {
  let text = "";
  try {
    text = readFileSync(DECLARED_FILE, "utf8");
  } catch {
    return new Map();
  }
  const out = new Map();
  for (const line of text.split("\n")) {
    const t = line.trim();
    if (!t || t.startsWith("#")) continue;
    const [pkg, decl, dir, kind, ...rest] = t.split("|").map((s) => s.trim());
    if (!pkg || !decl || !dir) continue;
    out.set(`${pkg}|${decl}|${dir}`, { kind, reason: rest.join(" | ") });
  }
  return out;
}
// The package's own directory name is the stable key — the corpus path differs
// between a scaffold, a fixture and an example for one generated package.
function packageKey(dir) {
  const parts = dir.split("/").filter((p) => p && p !== "_build");
  for (let i = parts.length - 1; i >= 0; i -= 1) {
    if (!["dist", "generated", "internal", "src"].includes(parts[i])) {
      return parts[i].replace(/^(scaffold_|bridge_fixture_)/, "").replace(/^typescript-to-moonbit-/, "").replace(/-/g, "_");
    }
  }
  return basename(dir);
}

function walk(d, out = []) {
  for (const e of readdirSync(d, { withFileTypes: true })) {
    const p = join(d, e.name);
    if (e.isDirectory()) {
      if (e.name !== "node_modules") walk(p, out);
    } else if (e.name === "bridge.mbti") out.push(p);
  }
  return out;
}

const snake = (s) =>
  s
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/[^A-Za-z0-9]/g, "_")
    .toLowerCase();

// Payload-BEARING enums only. A payload-free enum (`enum Mode { Read Write }`,
// from a TS numeric enum) is an integer tag on the MoonBit side, so a raw
// numeric passthrough is the correct wrapper — counting those was this
// probe's own first bug.
//
// Read from the `.mbti` AND every `.mbt` in the package, because the
// SYNTHESIZED unions — `Auto_ViewValue_or_TableValue`, the lowering of an
// inline `A | B` — are declared in `types.mbt` and never in the interface.
// Reading only the interface is what let this probe report 0 while
// `aliasedTable` was handing back a raw drizzle object under that very type.
function payloadEnums(src) {
  const enums = new Set();
  for (const m of src.matchAll(
    /^pub\(all\) enum ([A-Za-z_][\w]*) \{\n((?:  .*\n)*)\}/gm,
  )) {
    if (/^  [A-Za-z_][\w]*\(/m.test(m[2])) enums.add(m[1]);
  }
  return enums;
}

// The two directions are DIFFERENT QUESTIONS and have to be asked separately.
//
// The first version of this probe used one `/_from_js|_to_js|\$tag/` over the
// whole body, and that is how `__ts_mbt_aliased_table` passed: it converts its
// ARGUMENT (`.$tag === 0` dispatch, inlined) and hands the return back raw
// while declaring `-> Auto_ViewValue_or_TableValue`, so the `$tag` the pattern
// matched belonged to the parameter. "This body contains a conversion
// somewhere" is not "this body converts its return".
//
// Direction shows in the shape, whichever spelling the emitter used:
//   BUILDING a MoonBit value from JS writes the key   -> `"$tag":` / `_from_js(`
//   DISPATCHING on a MoonBit value reads it           -> `.$tag ===` / `_to_js(`
const BUILDS_MOONBIT_VALUE = /"\$tag":|_from_js\(/;
const READS_MOONBIT_VALUE = /\.\$tag\s*===|_to_js\(/;

// Section C's budget: a struct FIELD typed as a payload enum. Keyed per
// package rather than per occurrence, because there are hundreds and a
// four-hundred-line declaration file ranks nothing.
const STRUCT_BUDGET_FILE = "scripts/bridge_struct_enum_fields.txt";
function readStructBudget() {
  let text = "";
  try {
    text = readFileSync(STRUCT_BUDGET_FILE, "utf8");
  } catch {
    return null;
  }
  const out = new Map();
  for (const line of text.split("\n")) {
    const t = line.trim();
    if (!t || t.startsWith("#")) continue;
    const [pkg, reachable, convertible, erased] = t.split("|").map((s) => s.trim());
    if (!pkg) continue;
    out.set(pkg, {
      reachable: Number(reachable),
      convertible: Number(convertible),
      erased: Number(erased),
    });
  }
  return out;
}

// Names in `bridge.js` are the generator's snake_case, which DOUBLES the
// underscore at a PascalCase word boundary inside an already-underscored name
// (`Auto_BoolValue_or_X` -> `auto__bool_value_or__x`). Reconstructing that by
// hand is how the first two attempts at this count measured the wrong thing —
// the same substitution bug as the code being hunted, for the seventh time —
// so compare with underscores stripped and reconstruct nothing.
const underscoreless = (s) => s.replace(/_/g, "").toLowerCase();

let totalEnums = 0;
let wrapperDecls = 0;
let wrapperBad = 0;
let inlineDecls = 0;
let inlineBad = 0;
let structFields = 0;
let structReachable = 0;
let structConvertible = 0;
let structErased = 0;
const byPkg = [];
const structByPkg = [];

for (const mbti of walk("_build")) {
  const dir = dirname(mbti);
  const src = readFileSync(mbti, "utf8");
  let declSrc = src;
  for (const f of readdirSync(dir)) {
    if (f.endsWith(".mbt")) declSrc += "\n" + readFileSync(join(dir, f), "utf8");
  }
  const enums = payloadEnums(declSrc);
  totalEnums += enums.size;
  if (enums.size === 0) continue;
  const bad = [];

  // ---- Section A: named bridge.js wrappers -------------------------------
  let jsSrc = "";
  try {
    jsSrc = readFileSync(join(dir, "bridge.js"), "utf8");
  } catch {
    jsSrc = "";
  }
  if (jsSrc) {
    for (const m of src.matchAll(
      /^declare pub fn(?:\[[^\]]*\])? ([A-Za-z_][\w]*(?:::[A-Za-z_][\w]*)?)\(.*?\) -> ([A-Za-z_][\w]*)(\[[^\]]*\])?\??$/gm,
    )) {
      const [, fn, ret, typeArgs] = m;
      // A generic instantiation (`Foo[T]`) is not the bare enum name.
      if (typeArgs || !enums.has(ret)) continue;
      // `Type::method` binds as `__ts_mbt_<type>_<method>`
      // (`ffi_class_method_binding_name`); a plain name as `__ts_mbt_<name>`.
      const binding = fn.includes("::")
        ? "__ts_mbt_" + fn.split("::").map(snake).join("_")
        : "__ts_mbt_" + snake(fn);
      const w = jsSrc.match(
        new RegExp("export function " + binding + "\\(([^)]*)\\) \\{([^\\n]*)", "m"),
      );
      // No named wrapper: this declaration is implemented by an inline
      // extern, which section B reads directly. Not a finding here.
      if (!w) continue;
      wrapperDecls += 1;
      if (!BUILDS_MOONBIT_VALUE.test(w[2])) {
        wrapperBad += 1;
        bad.push({ kind: "wrapper", fn, ret, dir: "ret", detail: `-> ${ret}` });
      }
    }
  }

  // ---- Section B: inline extern lambda bodies ----------------------------
  // Both directions: a return promising the enum, and a parameter declared as
  // the enum whose `{$tag, _0}` is handed to JS unconverted.
  for (const file of readdirSync(dir)) {
    if (!file.endsWith(".mbt")) continue;
    const text = readFileSync(join(dir, file), "utf8");
    for (const m of text.matchAll(
      /^pub extern "js" fn(?:\[[^\]]*\])? ([A-Za-z_][\w:]*)\(([^)]*)\) -> ([A-Za-z_][\w]*)(\[[^\]]*\])?(\??)\s*=\n((?:\s*#\|.*\n)+)/gm,
    )) {
      const [, fn, params, ret, typeArgs, optional, body] = m;
      const missing = [];
      if (!typeArgs && enums.has(ret) && !BUILDS_MOONBIT_VALUE.test(body)) {
        missing.push(`ret ${ret}${optional}`);
      }
      for (const p of params.matchAll(/:\s*([A-Za-z_][\w]*)(\??)\s*(?:,|$)/g)) {
        if (enums.has(p[1]) && !READS_MOONBIT_VALUE.test(body)) {
          missing.push(`param ${p[1]}${p[2]}`);
        }
      }
      const crosses =
        (!typeArgs && enums.has(ret)) ||
        [...params.matchAll(/:\s*([A-Za-z_][\w]*)\??\s*(?:,|$)/g)].some((p) =>
          enums.has(p[1]),
        );
      if (!crosses) continue;
      inlineDecls += 1;
      if (missing.length > 0) {
        inlineBad += 1;
        for (const m2 of missing) {
          bad.push({
            kind: "inline",
            fn,
            ret,
            dir: m2.startsWith("param") ? "param" : "ret",
            detail: m2,
          });
        }
      }
    }
  }

  // ---- Section C: struct FIELDS typed as a payload enum ------------------
  //
  // Sections A and B ask about a FUNCTION's return. A struct field is the
  // third position a payload enum can occupy, and it is the one with no
  // machinery behind it at all: the corpus has 259 `_to_js` struct converters
  // and ZERO in the other direction, so a JS object handed to MoonBit as a
  // struct is used RAW. `Program::getSemanticDiagnostics` is
  // `(self, a, b) => self.getSemanticDiagnostics(a, b)` — it unwraps its
  // argument options and does nothing to the returned `Array[Diagnostic]` —
  // so `diag.messageText`, declared
  // `Auto_StringValue_or_DiagnosticMessageChainValue`, is a raw JS string and
  // a `match` on it reads `$tag` off something that has none.
  //
  // Two splits, because they rank different work.
  //
  // READ-REACHABLE: the struct appears in a RETURN position somewhere in the
  // package. Only then can a JS value arrive as this struct, so only then is
  // the read direction reachable at all; a struct that only ever crosses
  // MoonBit -> JS is served correctly by the `_to_js` converter that exists.
  //
  // CONVERTIBLE vs ERASED: whether the field's enum has a `_from_js` helper.
  // An erased one cannot be converted by any means, so widening the declared
  // type is the only honest answer. A convertible one could be fixed properly,
  // but only by a `_from_js` struct converter called at every struct-returning
  // position — machinery that does not exist.
  //
  // This is REPORTED against a per-package budget rather than failed outright:
  // the occurrences are pre-existing and in the hundreds, so a red gate here
  // would rank no work, which is the defect `docs/checker-priority.md` was
  // retired for. Growth fails; a drop is reported so the budget can follow.
  {
    const fromJsHelpers = new Set();
    for (const m of jsSrc.matchAll(
      /function __ts_mbt_tagged_union_([a-z_0-9]+)_from_js/g,
    )) {
      fromJsHelpers.add(underscoreless(m[1]));
    }
    let fields = 0;
    let reachable = 0;
    let convertible = 0;
    let erased = 0;
    const examples = [];
    for (const file of readdirSync(dir)) {
      if (!file.endsWith(".mbt")) continue;
      const text = readFileSync(join(dir, file), "utf8");
      for (const m of text.matchAll(
        /^pub\(all\) struct ([A-Za-z_][\w]*)(\[[^\]]*\])? \{\n((?:  .*\n)*)\}/gm,
      )) {
        const structName = m[1];
        // A return position, EXCLUDING the `%identity` upcast helpers.
        // `HTMLAttributes::asAriaAttributes(self) -> AriaAttributes =
        // "%identity"` is a MoonBit-side view of a value the caller
        // CONSTRUCTED, not a JS boundary crossing, so it does not make
        // `AriaAttributes` a struct a JS value can arrive as. Counting it did:
        // this test reported react_types' three aria fields as read-reachable
        // and the generator's AST-level pre-pass correctly disagreed, which is
        // how the over-count was found. Eighth time the instrument was the
        // thing that was wrong.
        const returnPattern = new RegExp(
          `-> (Array\\[)?${structName}(\\])?\\??( =|$)`,
        );
        const upcastPattern = new RegExp(`::as${structName}\\s*\\(`);
        const returned = declSrc
          .split("\n")
          .some(
            (line) =>
              returnPattern.test(line) &&
              !upcastPattern.test(line) &&
              !line.includes('"%identity"'),
          );
        for (const line of m[3].split("\n")) {
          const field = line.trim();
          if (field === "") continue;
          const sep = field.indexOf(" : ");
          if (sep < 0) continue;
          const declared = field.slice(sep + 3).trim();
          // A function-typed field carries the enum in its RETURN; a plain
          // one carries it directly. Filing this as "the function-typed
          // field" is what put the estimate at 8 against 438 — tenth time a
          // label stood in for the objective in this repo.
          const arrow = declared.lastIndexOf(") -> ");
          const carried = (
            declared.startsWith("(") && arrow >= 0
              ? declared.slice(arrow + 5)
              : declared
          )
            .replace(/\?$/, "")
            .trim();
          if (!enums.has(carried)) continue;
          fields += 1;
          if (!returned) continue;
          reachable += 1;
          if (fromJsHelpers.has(underscoreless(carried))) {
            convertible += 1;
          } else {
            erased += 1;
            if (examples.length < 3) {
              examples.push(`${structName}.${field.slice(0, sep)} : ${carried}`);
            }
          }
        }
      }
    }
    structFields += fields;
    structReachable += reachable;
    structConvertible += convertible;
    structErased += erased;
    if (fields > 0) {
      structByPkg.push({
        key: packageKey(dir),
        pkg: mbti.replace(/^_build\//, "").replace(/\/bridge\.mbti$/, ""),
        fields,
        reachable,
        convertible,
        erased,
        examples,
      });
    }
  }

  if (bad.length) {
    byPkg.push({
      pkg: mbti.replace(/^_build\//, "").replace(/\/bridge\.mbti$/, ""),
      key: packageKey(dir),
      bad,
    });
  }
}

const declared = readDeclared();
const seenKeys = new Set();
let undeclared = 0;
let declaredSeen = 0;
for (const p of byPkg) {
  for (const b of p.bad) {
    const key = `${p.key}|${b.fn}|${b.dir}`;
    seenKeys.add(key);
    if (declared.has(key)) declaredSeen += 1;
    else undeclared += 1;
  }
}
const stale = [...declared.keys()].filter((k) => !seenKeys.has(k));

console.log(`tagged-union enums declared:                  ${totalEnums}`);
console.log(`named bridge.js wrappers crossing one:        ${wrapperDecls}`);
console.log(`...building no enum value:                    ${wrapperBad}`);
console.log(`inline extern bodies crossing one:            ${inlineDecls}`);
console.log(`...missing a conversion:                      ${inlineBad}`);
console.log(`declared unconverted crossings:               ${declaredSeen}`);
console.log(`UNDECLARED unconverted crossings:             ${undeclared}`);
console.log(`stale declarations:                           ${stale.length}`);
console.log(`struct fields typed as a payload enum:        ${structFields}`);
console.log(`...in a struct JS can RETURN (read-reachable): ${structReachable}`);
console.log(`......enum has a _from_js (convertible):      ${structConvertible}`);
console.log(`......enum has none (only widening):          ${structErased}`);

for (const p of byPkg) {
  const rows = p.bad.filter((b) => !declared.has(`${p.key}|${b.fn}|${b.dir}`));
  if (rows.length === 0) continue;
  console.log(`\n  UNDECLARED in ${p.pkg}  (key: ${p.key})`);
  for (const b of rows) console.log(`    [${b.kind}] ${b.fn}: ${b.detail}`);
}
if (stale.length) {
  console.log("\nstale declarations (listed but no longer occurring):");
  for (const k of stale) console.log(`    ${k}`);
}
if (undeclared === 0 && stale.length === 0 && declaredSeen > 0) {
  const byKind = {};
  for (const p of byPkg) {
    for (const b of p.bad) {
      const d = declared.get(`${p.key}|${b.fn}|${b.dir}`);
      if (d) (byKind[d.kind] ??= []).push(`${p.key} ${b.fn}`);
    }
  }
  console.log("\ndeclared backlog by kind:");
  for (const [k, v] of Object.entries(byKind).sort((a, b) => b[1].length - a[1].length)) {
    console.log(`  ${String(k).padEnd(16)} ${v.length}`);
  }
}
// ---- Section C's budget ----------------------------------------------------
const structBudget = readStructBudget();
let structGrew = 0;
let structShrank = 0;
if (structBudget === null) {
  console.log(`\nno ${STRUCT_BUDGET_FILE}; struct-field counts are reported only`);
} else {
  const lines = [];
  for (const p of structByPkg) {
    const b = structBudget.get(p.key);
    if (b === undefined) {
      structGrew += 1;
      lines.push(
        `    UNDECLARED package ${p.key}: reachable ${p.reachable} (convertible ${p.convertible}, erased ${p.erased})`,
      );
      continue;
    }
    // Only `reachable` and `erased` are gated upward. `convertible` RISING is
    // an improvement — it means a field moved out of the unfixable half — and
    // gating it was backwards: teaching the from_js builder to use a closed
    // union's last case as the `else` moved 10 fields from erased to
    // convertible and the gate reported five packages as having GROWN.
    if (p.reachable > b.reachable || p.erased > b.erased) {
      structGrew += 1;
      lines.push(
        `    GREW ${p.key}: reachable ${b.reachable}->${p.reachable}, erased ${b.erased}->${p.erased} (convertible ${b.convertible}->${p.convertible})`,
      );
    } else if (
      p.reachable < b.reachable ||
      p.convertible !== b.convertible ||
      p.erased < b.erased
    ) {
      structShrank += 1;
      lines.push(
        `    dropped ${p.key}: reachable ${b.reachable}->${p.reachable}, convertible ${b.convertible}->${p.convertible}, erased ${b.erased}->${p.erased} — lower the budget`,
      );
    }
  }
  for (const key of structBudget.keys()) {
    if (!structByPkg.some((p) => p.key === key)) {
      structShrank += 1;
      lines.push(`    stale ${key}: no struct field carries a payload enum any more`);
    }
  }
  if (lines.length) {
    console.log("\nstruct-field budget:");
    for (const l of lines) console.log(l);
  }
}
console.log("\nread-reachable struct fields by package (the ranking):");
for (const p of [...structByPkg].sort((a, b) => b.erased - a.erased)) {
  // every package with a field, so the budget file can be built from this
  console.log(
    `  ${p.key.padEnd(24)} reachable ${String(p.reachable).padStart(3)}  convertible ${String(p.convertible).padStart(3)}  erased ${String(p.erased).padStart(3)}`,
  );
  for (const e of p.examples) console.log(`      ${e}`);
}

process.exitCode =
  undeclared > 0 || stale.length > 0 || structGrew > 0 ? 1 : 0;
