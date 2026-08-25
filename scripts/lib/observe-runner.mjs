// Observe one module and print what it did, as JSON, on stdout.
//
// Run as a child process by `verify_mangle_safety.mjs` for each variant
// of a case: the plain `--bundle` output, the mangled output, and — as a
// compiler-independent reference — the original TypeScript executed
// through Node's type stripping. One runner for all three means the
// three observations are produced by identical code, so a difference
// between them is a difference in the *module*, never in how it was
// watched.
//
// Usage:
//   node [--experimental-strip-types] observe-runner.mjs <module> <options-json>
//
// Options (JSON object):
//   driver      path to a `driver.mjs` exporting `default (mod) => any`
//   globals     host globals to define as empty objects before loading
//   globalStubs `{ name: "<js expression>" }` host globals with a body
//   fakeTimers  run setTimeout callbacks on the microtask queue
//
// Output on stdout: `{"ok":true,"observed":{…}}` or
// `{"ok":false,"error":"…","observed":{…}}`. Anything the module prints
// itself is captured (console is recorded, not forwarded), so stdout
// stays machine-readable.

import { pathToFileURL } from "node:url";

const [modulePath, optionsJson] = process.argv.slice(2);
const options = JSON.parse(optionsJson ?? "{}");

// ---------------------------------------------------------------
// Serialization: stable, total, and cycle-safe.
// ---------------------------------------------------------------

// Own members a function/class carries (statics, plus the prototype's
// methods). Renaming one of those IS observable. `name` is excluded:
// renaming a local binding changes `Function.name` and no minifier
// preserves it.
function functionMembers(fn) {
  const out = new Set();
  for (const key of Object.getOwnPropertyNames(fn)) {
    if (key !== "length" && key !== "name" && key !== "prototype") out.add(key);
  }
  const proto = fn.prototype;
  if (proto) {
    for (const key of Object.getOwnPropertyNames(proto)) {
      if (key !== "constructor") out.add(key);
    }
  }
  return [...out].sort();
}

function serialize(value, seen = new Set()) {
  if (value === undefined) return { $: "undefined" };
  if (value === null) return null;
  const t = typeof value;
  if (t === "number" || t === "string" || t === "boolean") return value;
  if (t === "bigint") return { $: "bigint", v: value.toString() };
  if (t === "symbol") return { $: "symbol", v: String(value) };
  if (t === "function") return { $: "function", members: functionMembers(value) };
  if (seen.has(value)) return { $: "cycle" };
  seen.add(value);
  try {
    if (Array.isArray(value)) return value.map((v) => serialize(v, seen));
    if (value instanceof Map) {
      return {
        $: "Map",
        v: [...value].map(([k, v]) => [serialize(k, seen), serialize(v, seen)]),
      };
    }
    if (value instanceof Set) return { $: "Set", v: [...value].map((v) => serialize(v, seen)) };
    if (value instanceof Error) return { $: "Error", message: value.message };
    if (value instanceof Date) return { $: "Date", v: value.toISOString() };
    // Plain-ish object: sort keys so a property *order* change (which a
    // minifier may legitimately introduce) doesn't read as a diff,
    // while property *names* still do.
    const out = {};
    for (const key of Object.keys(value).sort()) out[key] = serialize(value[key], seen);
    const proto = Object.getPrototypeOf(value);
    if (proto && proto !== Object.prototype) {
      // Class instance: record the reachable member names too, since
      // renaming a public method is exactly the failure mode hunted here.
      const members = new Set();
      let p = proto;
      while (p && p !== Object.prototype) {
        for (const key of Object.getOwnPropertyNames(p)) {
          if (key !== "constructor") members.add(key);
        }
        p = Object.getPrototypeOf(p);
      }
      out.$members = [...members].sort();
    }
    return out;
  } finally {
    seen.delete(value);
  }
}

// ---------------------------------------------------------------
// Recording
// ---------------------------------------------------------------

const sinks = [];

globalThis.fetch = async (input, init) => {
  sinks.push({
    sink: "fetch",
    url: typeof input === "string" ? input : serialize(input),
    init: serialize(init),
  });
  return {
    ok: true,
    status: 200,
    text: async () => "stub-response",
    json: async () => ({}),
  };
};

for (const level of ["log", "warn", "error", "info"]) {
  console[level] = (...args) => {
    sinks.push({ sink: `console.${level}`, args: args.map((a) => serialize(a)) });
  };
}

if (options.fakeTimers) {
  globalThis.setTimeout = (fn, _ms, ...rest) => {
    Promise.resolve().then(() => fn(...rest));
    return 0;
  };
}

for (const name of options.globals ?? []) {
  if (!(name in globalThis)) globalThis[name] = {};
}

// A case can install a real stand-in for a host global, given as a
// JavaScript expression. An empty object is enough to keep a module
// loading, but a name only reached THROUGH a global (`MyGlobal.f({ x })`)
// is only observable if the stub actually does something with it.
for (const [name, source] of Object.entries(options.globalStubs ?? {})) {
  // eslint-disable-next-line no-new-func -- fixture-supplied stub
  globalThis[name] = new Function(`"use strict"; return (${source});`)();
}

// ---------------------------------------------------------------
// Run
// ---------------------------------------------------------------

function emit(payload) {
  process.stdout.write(JSON.stringify(payload));
}

try {
  const mod = await import(pathToFileURL(modulePath).href);
  let result;
  if (options.driver) {
    const driver = await import(pathToFileURL(options.driver).href);
    result = await driver.default(mod);
  } else {
    result = Object.fromEntries(
      Object.keys(mod)
        .sort()
        .map((k) => [k, mod[k]]),
    );
  }
  // Let any floating promise the module started settle, so a sink
  // reached asynchronously still lands in the recording.
  for (let i = 0; i < 8; i++) await new Promise((r) => setImmediate(r));
  emit({ ok: true, observed: { result: serialize(result), sinks } });
} catch (err) {
  const error = `${err?.name ?? "Error"}: ${err?.message ?? String(err)}`;
  emit({ ok: false, error, observed: { error, sinks } });
}
