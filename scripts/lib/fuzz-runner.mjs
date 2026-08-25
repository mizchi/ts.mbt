// The fuzzer's oracle, run as a child process.
//
// Reads a JSON request on stdin, writes a JSON array of outcomes on
// stdout. One process per batch: starting Node costs more than running
// any single generated program, so the campaign hands over a hundred at
// a time.
//
// Two execution shapes, because a property name can escape the bundle
// through two different doors and they are not observable the same way:
//
//   "script"  The program is a self-contained script that ends in a
//             `console.log`. Nothing is exported, so the mangler may
//             rename every property it cannot prove observable, and the
//             only thing that can betray a bad rename is a sink the
//             program itself calls. Executed in a fresh `vm` context.
//
//   "module"  The program is an ES module with exports. Those names are
//             the package ABI. Observation happens from OUT HERE, after
//             compilation, so the module under test never contains the
//             code that watches it — which is the whole point: an
//             observation compiled together with the module would make
//             the names reachable and the test vacuous.
//
// A separate process also contains the damage. A generated program that
// blows the stack or wedges the event loop takes this process with it,
// and the campaign records the batch as a harness error instead of dying.

import vm from "node:vm";
import { pathToFileURL } from "node:url";

// ---------------------------------------------------------------
// Tagged encoding
// ---------------------------------------------------------------
//
// `JSON.stringify` cannot tell `undefined` from an absent property, or
// `NaN`/`-0`/`Infinity` from `null`, and those are exactly the values a
// constant-folding bug produces. Every value is encoded as a tagged
// tuple instead, and the comparison is on the encoded form.

function encode(value, seen = new Map()) {
  if (value === undefined) return ["undefined"];
  if (value === null) return ["null"];
  const type = typeof value;
  if (type === "number") {
    if (Number.isNaN(value)) return ["number", "NaN"];
    if (Object.is(value, -0)) return ["number", "-0"];
    if (value === Infinity) return ["number", "+Infinity"];
    if (value === -Infinity) return ["number", "-Infinity"];
    return ["number", String(value)];
  }
  if (type === "string" || type === "boolean") return [type, value];
  if (type === "bigint") return ["bigint", String(value)];
  if (type === "symbol") return ["symbol", value.description ?? null];
  // A function's own members are observable — statics, and the methods
  // on its prototype. `name` is excluded on purpose: renaming a local
  // binding changes `Function.name` and no minifier preserves it, so
  // including it would report every successful mangle as a failure.
  if (type === "function") return ["function", functionMembers(value)];

  if (seen.has(value)) return ["reference", seen.get(value)];
  const id = seen.size;
  seen.set(value, id);
  if (Array.isArray(value)) {
    const items = [];
    for (let index = 0; index < value.length; index++) {
      items.push(Object.hasOwn(value, index) ? encode(value[index], seen) : ["hole"]);
    }
    return ["array", id, items];
  }
  if (value instanceof Error) return ["error", value.name, value.message];
  // Own enumerable keys, sorted. Sorting means a mangler that reorders
  // properties without renaming them is not reported; renaming one is.
  const entries = Object.keys(value)
    .sort()
    .map((key) => [key, encode(value[key], seen)]);
  // The prototype's methods are part of what a caller can reach, and
  // `Object.keys` cannot see them, so they are collected separately.
  //
  // `proto !== Object.prototype` is NOT the test, even though it reads
  // like it: the script shape runs in a `vm` context with its own
  // intrinsics, so a plain object made in there has a DIFFERENT
  // `Object.prototype` than this realm's. The comparison failed, the
  // whole of `Object.prototype` (`__defineGetter__`, `__proto__`, …)
  // got enumerated, and it showed up as a difference between the
  // reference leg (imported here) and the compiled legs (run in the vm)
  // — a mismatch reported against the compiler that was entirely mine.
  // The constructor's name is realm-independent.
  const proto = Object.getPrototypeOf(value);
  const protoIsPlain = !proto || proto.constructor?.name === "Object";
  const protoMembers = protoIsPlain
    ? []
    : Object.getOwnPropertyNames(proto)
        .filter((key) => key !== "constructor")
        .sort();
  return ["object", id, entries, protoMembers];
}

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

// ---------------------------------------------------------------
// Script shape
// ---------------------------------------------------------------

function runScript(source, timeoutMs) {
  const logs = [];
  const sandbox = {
    console: {
      log(...args) {
        logs.push(encode(args));
      },
    },
    // `structuredClone` is a host API, not a JS intrinsic: a fresh `vm`
    // context does not have one. The generator emits it as a sink, so it
    // has to be provided or every such program would throw and the seed
    // would be skipped.
    structuredClone: (value) => structuredClone(value),
  };
  try {
    vm.runInNewContext(source, sandbox, { timeout: timeoutMs, displayErrors: false });
    return { status: "completed", logs };
  } catch (error) {
    if (error && error.code === "ERR_SCRIPT_EXECUTION_TIMEOUT") {
      return { status: "timed_out" };
    }
    return {
      status: "threw",
      name: error && error.name ? String(error.name) : "Error",
      message: error && error.message ? String(error.message) : String(error),
    };
  }
}

// ---------------------------------------------------------------
// Module shape
// ---------------------------------------------------------------

// Fixed arguments for exported functions. Observation must be identical
// on both sides, so the driver cannot be random.
const CALL_ARGS = [
  [],
  [1, 2],
  ["alpha", 0],
];

/// Observe everything an exported binding exposes: the value itself,
/// what it returns when called, and what it looks like when
/// constructed. A property the mangler renamed shows up in the encoded
/// form of one of those.
async function observeModule(modulePath, timeoutMs) {
  try {
    const namespace = await withTimeout(import(pathToFileURL(modulePath).href), timeoutMs);
    return await observeNamespace(namespace);
  } catch (error) {
    if (error && error.message === "__fuzz_timeout__") return { status: "timed_out" };
    return {
      status: "threw",
      name: error && error.name ? String(error.name) : "Error",
      message: error && error.message ? String(error.message) : String(error),
    };
  }
}

/// Serialize everything a module namespace exposes. Shared by the
/// compiled and reference legs so a difference between them is a
/// difference in the module, never in how it was watched.
async function observeNamespace(namespace) {
  const observed = [];
  for (const name of Object.keys(namespace).sort()) {
    const value = namespace[name];
    observed.push([name, encode(value)]);
    if (typeof value !== "function") continue;
    for (const args of CALL_ARGS) {
      observed.push([`${name}()`, callSafely(() => encode(value(...args)))]);
      observed.push([`new ${name}()`, callSafely(() => encode(new value(...args)))]);
    }
  }
  return { status: "completed", logs: observed };
}

/// Run the ORIGINAL TypeScript, observed the same way its compiled form
/// would be: through `console.log` for the sink shape, through the
/// export surface for the module shape. Node's type stripping handles
/// the annotations, so nothing of ours touches the program.
async function observeReference(sourcePath, timeoutMs, kind) {
  const logs = [];
  const realLog = console.log;
  console.log = (...args) => {
    logs.push(encode(args));
  };
  try {
    const namespace = await withTimeout(import(pathToFileURL(sourcePath).href), timeoutMs);
    if (kind === "module") {
      console.log = realLog;
      return await observeNamespace(namespace);
    }
    return { status: "completed", logs };
  } catch (error) {
    if (error && error.message === "__fuzz_timeout__") return { status: "timed_out" };
    return {
      status: "threw",
      name: error && error.name ? String(error.name) : "Error",
      message: error && error.message ? String(error.message) : String(error),
    };
  } finally {
    console.log = realLog;
  }
}

/// A throwing export is itself an observation — as long as BOTH sides
/// throw the same way. Encoding the throw rather than propagating it
/// keeps one bad export from hiding every later one.
function callSafely(body) {
  try {
    return body();
  } catch (error) {
    return ["threw", error && error.name ? String(error.name) : "Error"];
  }
}

function withTimeout(promise, timeoutMs) {
  return Promise.race([
    promise,
    new Promise((_resolve, reject) =>
      setTimeout(() => reject(new Error("__fuzz_timeout__")), timeoutMs).unref?.(),
    ),
  ]);
}

// ---------------------------------------------------------------
// Request loop
// ---------------------------------------------------------------

async function main() {
  let input = "";
  process.stdin.setEncoding("utf8");
  for await (const chunk of process.stdin) input += chunk;
  const request = JSON.parse(input);
  const results = [];
  for (const testCase of request.cases) {
    // A reference-only request asks one question: does the ORIGINAL
    // program run? The campaign asks it when a baseline bundle failed,
    // to decide whether the generated program was going to fail anyway
    // (a skip) or whether our own compression broke it (a finding).
    //
    // No compiler of ours is involved: Node runs the TypeScript source
    // directly through its own type stripping. That is what makes the
    // answer evidence rather than an opinion.
    if (request.shape === "reference") {
      results.push({
        baseline: await observeReference(testCase.baselinePath, request.timeoutMs, testCase.kind),
      });
      continue;
    }
    if (request.shape === "module") {
      results.push({
        baseline: await observeModule(testCase.baselinePath, request.timeoutMs),
        candidate: await observeModule(testCase.candidatePath, request.timeoutMs),
      });
    } else {
      results.push({
        baseline: runScript(testCase.baseline, request.timeoutMs),
        candidate: runScript(testCase.candidate, request.timeoutMs),
      });
    }
  }
  process.stdout.write(JSON.stringify(results));
}

main().catch((error) => {
  process.stderr.write(String(error && error.stack ? error.stack : error));
  process.exit(1);
});
