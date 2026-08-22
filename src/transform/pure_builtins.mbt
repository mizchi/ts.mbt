// The allowlist half of the inverted sink rule.
//
// `sink_catalog.mbt` used to work the other way round: it enumerated
// the calls known to leak property names (`fetch`, `console.*`,
// `JSON.stringify`, a call on an imported binding) and let everything
// else through. Enumerating the dangerous half of a host API surface
// can't ever be finished — `postMessage`, `structuredClone`,
// `Response.json`, IndexedDB, the next Web API — so every name nobody
// thought of was a silent hole where a property got renamed while a
// foreign consumer still read it by its old name.
//
// `callee_provenance.mbt` inverts that: a call escapes unless its
// callee is provably bundle-internal. That makes the unknown case fail
// closed, and it makes THIS file load-bearing — without an allowlist,
// `xs.map(f)`, `Math.max(a, b)` and `Promise.all(ps)` would all count
// as escapes and nothing in a real bundle would stay manglable.
//
// Two different kinds of call live in the tables below, and it's worth
// keeping the distinction in mind when adding one:
//
//   * *name-blind* built-ins. `Math.max(a, b)` sees numbers,
//     `parseInt(s)` sees a string, `new Map(pairs)` reads its argument
//     by index. No property of the argument is ever read by name, so
//     nothing about the argument's shape escapes.
//   * built-ins whose observation is *already modelled precisely*
//     somewhere else. `Object.keys(x)` is recorded as a `DirectKeys`
//     sink and `JSON.stringify(x)` / `console.log(x)` as `Recursive`
//     ones, which reserve exactly the names those calls can expose.
//     Letting the generic foreign-call rule fire on them as well would
//     replace an exact reservation with the `*` wildcard and switch
//     property mangling off for the whole bundle.
//
// Anything NOT listed here is foreign, which is the point.

///|
/// `NS.m(...)` where `NS` is a host global — does this call keep the
/// argument's property names inside the bundle?
///
/// Caveat, stated here because it is the one way the table can be
/// wrong: the match is on the *name* `NS`. A module that imports a
/// binding shadowing a built-in namespace (`import { Map } from
/// "immutable"`) gets the built-in's answer. Callers guard against a
/// locally *declared* shadow (see `classify_callee`), but an import
/// header introduces no statement-level binding for the symbol graph
/// to find.
fn is_pure_static_member(ns : String, m : String) -> Bool {
  match ns {
    // Every `Math` member takes and returns numbers.
    "Math" => true
    // Already modelled: every `console` argument is recorded as a
    // `Recursive` sink.
    "console" => true
    // `stringify` is modelled as `Recursive`; `parse` is name-blind on
    // the way in (its RESULT is host-shaped — see
    // `returns_host_shaped`).
    "JSON" => m == "parse" || m == "stringify"
    "Object" =>
      match m {
        // Modelled as `DirectKeys` sinks.
        "keys"
        | "values"
        | "entries"
        | "fromEntries"
        | "assign"
        | "defineProperty" => true
        // Touch the prototype chain or the object's extensibility, not
        // its property names.
        "freeze"
        | "isFrozen"
        | "seal"
        | "isSealed"
        | "preventExtensions"
        | "isExtensible"
        | "is"
        | "getPrototypeOf"
        | "setPrototypeOf" => true
        // Deliberately absent: `create(proto, descriptors)`,
        // `getOwnPropertyNames`, `getOwnPropertyDescriptor(s)`,
        // `defineProperties`, `groupBy`. Each reads or writes names we
        // don't model, so they stay foreign and reserve the wildcard.
        _ => false
      }
    "Number" =>
      match m {
        "isInteger"
        | "isFinite"
        | "isNaN"
        | "isSafeInteger"
        | "parseFloat"
        | "parseInt" => true
        _ => false
      }
    "String" =>
      match m {
        "fromCharCode" | "fromCodePoint" | "raw" => true
        _ => false
      }
    "Array" =>
      // `from` reads `length` and the iterator protocol; both names are
      // on the mangler's built-in reserved list already.
      match m {
        "isArray" | "of" | "from" => true
        _ => false
      }
    "Promise" =>
      match m {
        "all" | "allSettled" | "any" | "race" | "resolve" | "reject" => true
        _ => false
      }
    "Date" =>
      match m {
        "now" | "parse" | "UTC" => true
        _ => false
      }
    "Symbol" =>
      match m {
        "for" | "keyFor" => true
        _ => false
      }
    _ => false
  }
}

///|
/// Bare `f(...)` calls on a host global that keep their arguments'
/// property names inside the bundle.
fn is_pure_global_function(name : String) -> Bool {
  match name {
    "parseInt" | "parseFloat" | "isNaN" | "isFinite" => true
    "encodeURI" | "encodeURIComponent" | "decodeURI" | "decodeURIComponent" =>
      true
    "atob" | "btoa" | "escape" | "unescape" => true
    // Coercion constructors called as plain functions. `String(x)`
    // reaches `x.toString()`, which is on the built-in reserved list.
    "String"
    | "Number"
    | "Boolean"
    | "BigInt"
    | "Symbol"
    | "Array"
    | "Object" => true
    // Timers hand the callback back to bundle-internal code and
    // forward the trailing arguments to it verbatim, never reading
    // them by name.
    "setTimeout" | "clearTimeout" | "setInterval" | "clearInterval" => true
    "setImmediate" | "clearImmediate" | "queueMicrotask" => true
    "requestAnimationFrame" | "cancelAnimationFrame" => true
    _ => false
  }
}

///|
/// `new X(...)` where the resulting value is a container of
/// bundle-owned values rather than a host object with a host-owned
/// shape.
///
/// This matters twice over: the constructor arguments don't escape,
/// AND the constructed value stays internal, so `const m = new Map();
/// m.set(k, payload)` keeps `payload` manglable. Treating `new Map()`
/// as a foreign call — which the provenance rule would do by default,
/// `Map` being a host global — would poison that whole idiom.
///
/// Host APIs whose constructor arguments DO carry names
/// (`new URLSearchParams(obj)`, `new Response(body, init)`,
/// `new Request(url, init)`, `new Headers(obj)`, `new FormData()`) are
/// deliberately absent, as are `Function` and `Proxy`.
fn is_pure_builtin_constructor(name : String) -> Bool {
  match name {
    "Map" | "Set" | "WeakMap" | "WeakSet" | "WeakRef" => true
    "Array" | "Object" | "String" | "Number" | "Boolean" => true
    "Date" | "RegExp" | "Promise" => true
    "Error"
    | "TypeError"
    | "RangeError"
    | "SyntaxError"
    | "ReferenceError"
    | "EvalError"
    | "URIError"
    | "AggregateError" => true
    "ArrayBuffer" | "SharedArrayBuffer" | "DataView" => true
    "Int8Array"
    | "Uint8Array"
    | "Uint8ClampedArray"
    | "Int16Array"
    | "Uint16Array"
    | "Int32Array"
    | "Uint32Array"
    | "Float32Array"
    | "Float64Array"
    | "BigInt64Array"
    | "BigUint64Array" => true
    _ => false
  }
}

///|
/// Of the pure calls above, the ones whose RESULT still has a shape
/// the host owns.
///
/// `JSON.parse(text)` is the whole reason this exists: it is name-blind
/// on the way in and completely host-shaped on the way out — the keys
/// of the result come from a string produced at runtime, so every name
/// the bundle reads off it has to survive mangling.
fn returns_host_shaped(ns : String, m : String) -> Bool {
  ns == "JSON" && m == "parse"
}
