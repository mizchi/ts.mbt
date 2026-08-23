// Emit mangle-safety corpus cases from the safety model instead of
// writing them one at a time.
//
// The hand-written cases in `fixtures/mangle-safety/` each encode one
// situation somebody thought of. That is exactly the failure mode the
// analysis itself was rewritten to avoid: enumerating the cases you
// remembered leaves silent holes where the ones you didn't should have
// been. So this generator takes the *model* — a property name escapes
// through the export surface or through a side-effect sink, and the sink
// decides how deep the observation goes — and pays out the whole
// cross-product of it.
//
//   carrier × exit
//
// A carrier is how the property-bearing value gets built (object
// literal, function return, class instance, array element). An exit is
// how it leaves — or doesn't. Each case then carries two values with
// the same shape: one takes the exit, one stays home. The expectations
// are DERIVED, never restated:
//
//   exit depth `none`       → nothing is reserved, every name manglable
//   exit depth `direct`     → first-level keys only (`Object.keys`,
//                             `for-in` enumerate one level)
//   exit depth `recursive`  → the whole tree (`JSON.stringify`,
//                             `console.log`, a request body)
//   exit depth `external`   → the whole tree; a foreign callee can read
//                             anything
//
// So a `direct` exit is expected to keep the top-level key and to
// *mangle* the nested one, and a `recursive` exit is expected to keep
// both. Getting that wrong in either direction is a finding: renaming a
// kept name is a safety violation the differential run catches on its
// own, and keeping a manglable one is reported as a missed opportunity.
//
// Usage:
//   node scripts/generate_mangle_cases.mjs           # write the cases
//   node scripts/generate_mangle_cases.mjs --check   # fail if stale

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const OUT_DIR = path.join(ROOT, "fixtures", "mangle-safety", "generated");

// ---------------------------------------------------------------
// The names under test
// ---------------------------------------------------------------
//
// Deliberately unlike anything on the mangler's built-in reserved list,
// and distinct from each other so `propertyAppears` can't confuse two.
const TOP = "alphaTop"; //   first-level key on the escaping value
const WRAP = "alphaWrap"; //  first-level key holding the nested object
const DEEP = "alphaDeep"; //  second-level key, only reached recursively
const CTL = "omegaCtl"; //    key on the value that never leaves

// ---------------------------------------------------------------
// Carriers: how the escaping value is built
// ---------------------------------------------------------------
//
// `decl` binds `payload` at the top level. Top level matters: the
// export-surface walk resolves `obj.key` precisely for a top-level
// object literal, and widens to the whole object for a function-local
// one, which would reserve the control name and mask the result.
const CARRIERS = {
  literal: {
    what: "a top-level object literal",
    decl: () => `const payload = { ${TOP}: 1, ${WRAP}: { ${DEEP}: 2 } };`,
  },
  funcReturn: {
    what: "the return value of an internal function",
    decl: () =>
      [
        `function build() {`,
        `  return { ${TOP}: 1, ${WRAP}: { ${DEEP}: 2 } };`,
        `}`,
        `const payload = build();`,
      ].join("\n"),
  },
  classInstance: {
    what: "an instance of a bundle-internal class",
    decl: () =>
      [
        `class Holder {`,
        `  ${TOP}: number;`,
        `  ${WRAP}: { ${DEEP}: number };`,
        `  constructor() {`,
        `    this.${TOP} = 1;`,
        `    this.${WRAP} = { ${DEEP}: 2 };`,
        `  }`,
        `}`,
        `const payload = new Holder();`,
      ].join("\n"),
  },
  spread: {
    what: "an object literal assembled with a spread",
    decl: () =>
      [
        `const base = { ${TOP}: 1 };`,
        `const payload = { ...base, ${WRAP}: { ${DEEP}: 2 } };`,
      ].join("\n"),
  },
  conditional: {
    what: "one of two branches of a conditional",
    decl: () =>
      [
        // `Date.now()` keeps the fold pass from picking a branch.
        `const live = Date.now() > 0;`,
        `const payload = live`,
        `  ? { ${TOP}: 1, ${WRAP}: { ${DEEP}: 2 } }`,
        `  : { ${TOP}: 0, ${WRAP}: { ${DEEP}: 0 } };`,
      ].join("\n"),
  },
  mapValue: {
    what: "a value stored in and read back out of a `Map`",
    decl: () =>
      [
        `type Shape = { ${TOP}: number; ${WRAP}: { ${DEEP}: number } };`,
        `const store = new Map<string, Shape>();`,
        `store.set("k", { ${TOP}: 1, ${WRAP}: { ${DEEP}: 2 } });`,
        `const payload = store.get("k")!;`,
      ].join("\n"),
  },
  arrayElement: {
    what: "an object inside an array",
    decl: () => `const payload = [{ ${TOP}: 1, ${WRAP}: { ${DEEP}: 2 } }];`,
    // The exit observes the array, and an array's own keys are numeric.
    // So every name under test sits one level deeper than it does for
    // the other carriers, and a one-level enumeration (`Object.keys`,
    // `for-in`) exposes none of them.
    depthOffset: 1,
  },
};

// ---------------------------------------------------------------
// Exits: how the value leaves
// ---------------------------------------------------------------
//
// `depth` drives the derived expectation. `keeps` lists names the exit
// statement introduces on its own (a `RequestInit` literal's `method` /
// `body` belong to the host, not to the carrier). `files`, `json` and
// `stub` carry whatever the exit needs to actually run.
const EXITS = {
  none: {
    what: "never leaves the bundle",
    depth: "none",
    stmts: () => [],
  },
  consoleLog: {
    what: "reaches `console.log`",
    depth: "recursive",
    stmts: () => [`console.log(payloadRef);`],
  },
  jsonStringify: {
    what: "is serialized with `JSON.stringify` and exported",
    depth: "recursive",
    stmts: () => [`export const encoded = JSON.stringify(payloadRef);`],
    exports: ["encoded"],
  },
  fetchBody: {
    what: "is sent as a `fetch` request body",
    depth: "recursive",
    keeps: ["method", "body"],
    stmts: () => [
      `fetch("https://example.test/sink", {`,
      `  method: "POST",`,
      `  body: JSON.stringify(payloadRef),`,
      `});`,
    ],
  },
  externalCall: {
    what: "is handed to a function imported from an external package",
    depth: "external",
    imports: [`import { send } from "ext-sink";`],
    stmts: () => [`send(payloadRef);`],
    json: {
      externals: ["ext-sink"],
      stubs: {
        "ext-sink": [
          "export function send(value) {",
          "  // Read the names back out so a rename is observable.",
          "  console.log('ext-sink.send', JSON.stringify(value));",
          "}",
          "",
        ].join("\n"),
      },
    },
    files: {
      "lib.d.ts": ['declare module "ext-sink" {', "  export function send(value: unknown): void;", "}", ""].join(
        "\n",
      ),
    },
  },
  hostChain: {
    what: "is posted through a nested host-global chain",
    depth: "external",
    stmts: () => [`HostBridge.channel.post(payloadRef);`],
    json: {
      globalStubs: {
        HostBridge:
          "{ channel: { post: (value) => { console.log('HostBridge.post', JSON.stringify(value)); } } }",
      },
    },
    files: {
      "env.d.ts": [
        "declare const HostBridge: {",
        "  channel: { post(value: unknown): void };",
        "};",
        "",
      ].join("\n"),
    },
  },
  exportReturn: {
    what: "is returned from an exported function",
    // Door 1 rather than door 2: the consumer holds the value and can
    // read anything on it.
    depth: "recursive",
    stmts: () => [`export function handOut() {`, `  return payloadRef;`, `}`],
    exports: ["handOut"],
    driverEntries: () => ["  handedOut: mod.handOut(),"],
  },
  throwValue: {
    what: "is thrown",
    // `throw x` hands the value to whoever catches it — `.message`,
    // `.code`, anything.
    depth: "recursive",
    stmts: () => [`export function boom(): number {`, `  throw payloadRef;`, `}`],
    exports: ["boom"],
    driverEntries: () => [
      "  caught: (() => {",
      "    try {",
      "      mod.boom();",
      "      return null;",
      "    } catch (thrown) {",
      "      return thrown;",
      "    }",
      "  })(),",
    ],
  },
  structuredClone: {
    what: "is passed through `structuredClone`",
    // A host call nobody put on the pure allowlist. It has to fail
    // closed on the strength of the provenance rule alone — that is the
    // claim this case exists to check.
    depth: "external",
    stmts: () => [`export const cloned = structuredClone(payloadRef);`],
    exports: ["cloned"],
  },
  objectEntries: {
    what: "has its own entries enumerated with `Object.entries`",
    // Not `direct`: `entries` hands out the values alongside the keys,
    // so the names inside those values travel with them.
    depth: "recursive",
    stmts: () => [`export const pairs = Object.entries(payloadRef);`],
    exports: ["pairs"],
  },
  objectKeys: {
    what: "has its own keys enumerated with `Object.keys`",
    depth: "direct",
    stmts: () => [`export const names = Object.keys(payloadRef);`],
    exports: ["names"],
  },
  forIn: {
    what: "is enumerated with `for-in`",
    depth: "direct",
    stmts: () => [
      `const found: string[] = [];`,
      `for (const key in payloadRef) {`,
      `  found.push(key);`,
      `}`,
      `export const seen = found;`,
    ],
    exports: ["seen"],
  },
};

// ---------------------------------------------------------------
// Deriving the expectation
// ---------------------------------------------------------------

// The level each name under test sits at, relative to the value the
// exit observes. `offset` is the carrier's own indirection.
function levelOf(offset) {
  return { [TOP]: 1 + offset, [WRAP]: 1 + offset, [DEEP]: 2 + offset };
}

// Which of the carrier's names does an exit of this depth expose?
//
//   none       nothing leaves
//   direct     one level of keys (`Object.keys`, `for-in`)
//   recursive  the whole tree (`JSON.stringify`, `console.log`, a body)
//   external   the whole tree; a foreign callee can read anything
function keptNames(depth, offset) {
  const level = levelOf(offset);
  const reach = { none: 0, direct: 1, recursive: Infinity, external: Infinity }[depth];
  if (reach === undefined) throw new Error(`unknown exit depth ${depth}`);
  return [TOP, WRAP, DEEP].filter((n) => level[n] <= reach);
}

function mangledNames(depth, offset) {
  // The control value never leaves, whatever the exit does.
  const kept = new Set(keptNames(depth, offset));
  return [CTL, ...[TOP, WRAP, DEEP].filter((n) => !kept.has(n))];
}

// ---------------------------------------------------------------
// Emitting one case
// ---------------------------------------------------------------

function caseName(carrierKey, exitKey) {
  const kebab = (s) => s.replace(/[A-Z]/g, (c) => `-${c.toLowerCase()}`);
  return `${kebab(carrierKey)}-${kebab(exitKey)}`.replace(/^-/, "");
}

function renderCase(carrierKey, exitKey) {
  const carrier = CARRIERS[carrierKey];
  const exit = EXITS[exitKey];
  const offset = carrier.depthOffset ?? 0;
  const lines = [];

  lines.push(`// GENERATED by scripts/generate_mangle_cases.mjs — do not edit.`);
  lines.push(`//`);
  lines.push(`// Carrier: ${carrier.what}.`);
  lines.push(`// Exit:    ${exit.what} (observation depth: ${exit.depth}).`);
  lines.push(`//`);
  lines.push(`// Derived expectation: keep [${keptNames(exit.depth, offset).join(", ") || "nothing"}],`);
  lines.push(`// mangle [${mangledNames(exit.depth, offset).join(", ")}].`);
  lines.push("");
  for (const imp of exit.imports ?? []) lines.push(imp);
  if ((exit.imports ?? []).length > 0) lines.push("");
  lines.push(carrier.decl());
  const stmts = exit.stmts().map((l) => l.replace(/payloadRef/g, "payload"));
  if (stmts.length > 0) {
    lines.push("");
    lines.push(...stmts);
  }
  lines.push("");
  lines.push(`// The control: same kind of value, never leaves the bundle.`);
  lines.push(`const control = { ${CTL}: 7 };`);
  lines.push(`export const total = control.${CTL};`);
  lines.push("");

  const exports = ["total", ...(exit.exports ?? [])].sort();
  const meta = {
    origin: "generated — scripts/generate_mangle_cases.mjs",
    generated: true,
    what: `${carrier.what[0].toUpperCase()}${carrier.what.slice(1)} that ${exit.what}. Observation depth ${exit.depth}, so the expectation is derived, not authored.`,
    ...(exit.json ?? {}),
    exports,
    expectKeep: [...keptNames(exit.depth, offset), ...(exit.keeps ?? [])],
    expectMangle: mangledNames(exit.depth, offset),
    expectStatus: "pass",
  };

  // An exit that exports a *function* needs the driver to call it —
  // serializing the function itself observes no property name, which
  // would make the case hollow and the mutation self-check would say so.
  const entries = exit.driverEntries
    ? exit.driverEntries()
    : exports.map((n) => `  ${n}: mod.${n},`);
  const driver = [
    "// GENERATED by scripts/generate_mangle_cases.mjs — do not edit.",
    "export default async (mod) => ({",
    ...(exit.driverEntries ? ["  total: mod.total,"] : []),
    ...entries,
    "});",
    "",
  ].join("\n");

  return {
    name: caseName(carrierKey, exitKey),
    files: {
      "index.ts": lines.join("\n"),
      "case.json": `${JSON.stringify(meta, null, 2)}\n`,
      "driver.mjs": driver,
      ...(exit.files ?? {}),
    },
  };
}

function allCases() {
  const out = [];
  for (const carrierKey of Object.keys(CARRIERS)) {
    for (const exitKey of Object.keys(EXITS)) {
      out.push(renderCase(carrierKey, exitKey));
    }
  }
  return out;
}

// ---------------------------------------------------------------
// Write / check
// ---------------------------------------------------------------

const check = process.argv.includes("--check");
const cases = allCases();

if (check) {
  const stale = [];
  const expected = new Set(cases.map((c) => c.name));
  const present = fs.existsSync(OUT_DIR)
    ? fs.readdirSync(OUT_DIR, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name)
    : [];
  for (const name of present) {
    if (!expected.has(name)) stale.push(`${name}/ is not produced by the generator any more`);
  }
  for (const c of cases) {
    for (const [file, want] of Object.entries(c.files)) {
      const at = path.join(OUT_DIR, c.name, file);
      let got = null;
      try {
        got = fs.readFileSync(at, "utf8");
      } catch {
        stale.push(`${c.name}/${file} is missing`);
        continue;
      }
      if (got !== want) stale.push(`${c.name}/${file} differs from the generator's output`);
    }
    for (const file of fs.existsSync(path.join(OUT_DIR, c.name))
      ? fs.readdirSync(path.join(OUT_DIR, c.name))
      : []) {
      if (!(file in c.files)) stale.push(`${c.name}/${file} is not produced by the generator any more`);
    }
  }
  if (stale.length > 0) {
    console.error("generate_mangle_cases: the checked-in cases are stale\n");
    for (const s of stale) console.error(`  ✗ ${s}`);
    console.error("\n  Run `node scripts/generate_mangle_cases.mjs` and commit the result.");
    process.exit(1);
  }
  console.log(`generate_mangle_cases: ${cases.length} generated cases are up to date`);
  process.exit(0);
}

fs.rmSync(OUT_DIR, { recursive: true, force: true });
for (const c of cases) {
  const dir = path.join(OUT_DIR, c.name);
  fs.mkdirSync(dir, { recursive: true });
  for (const [file, content] of Object.entries(c.files)) {
    fs.writeFileSync(path.join(dir, file), content);
  }
}
console.log(
  `generate_mangle_cases: wrote ${cases.length} cases (${Object.keys(CARRIERS).length} carriers × ${Object.keys(EXITS).length} exits) to fixtures/mangle-safety/generated/`,
);
