// Identifier mangling pass.
//
// This is the type-aware mangling that's the eventual goal of the
// transform stack (the packelyze retry). Scope of this pass:
//
//   - Rename function-local declarations (`let`, `const`, `var`,
//     parameters, nested function names) to short two-letter
//     identifiers (`a`, `b`, …, `aa`, `ab`, …).
//   - `let` / `const` are renamed per lexical block frame, so
//     non-overlapping `if` / `while` / `try` / bare-`{}` blocks can
//     reuse the same short slot. `var` is pre-hoisted to the
//     enclosing function frame, matching JS scoping.
//   - Reserved-by-default: every top-level binding stays put (the
//     bundle's exports + every name visible at module scope), plus
//     every JS builtin / DOM global the engine might look up.
//   - All references in the same function — `Var`, `PropAccess`
//     receivers, call-site `Call(name, …)`, assignment targets,
//     destructuring patterns — get renamed in lockstep.
//
// Property mangling is opt-in via `cfg.mangle_properties` and runs
// as a separate pass on top of the identifier rename.
//
//   block ──► mangle_block(block, cfg) ──► block (with locals renamed)
//
// `cfg.reserved` augments the default reserved set. `cfg.preserve_top_level`
// (`true` by default) makes every top-level binding stay so library
// consumers can still call `export const greet = ...` after the
// transform — flip to `false` for sealed application bundles where the
// module-level surface is itself private.

///|
pub(all) struct ManglerConfig {
  // Extra names that must never get mangled. Combined with the
  // built-in reserved set (globals, JS keywords, common DOM
  // identifiers).
  reserved : Array[String]
  // When `true` (default) every identifier introduced at the top
  // level of `mangle_block` is added to the reserved set before the
  // pass starts. Use `false` to mangle top-level names too — only
  // safe once the caller has its own re-export shim list.
  preserve_top_level : Bool
  // OPT-IN: when `true`, property keys (`obj.foo`, `obj["foo"]`,
  // object literal `{ foo: … }`, destructure patterns
  // `{ foo } = obj`, method calls `obj.foo(…)`) get renamed too.
  // Off by default because it's not safe-by-default: any property
  // shared with external code (DOM, browser APIs, third-party
  // libraries, JSON serialization) must be in the reserved set,
  // or the consumer's accesses break silently. The built-in
  // `mangler_builtin_reserved_properties` covers the common
  // surface; users extend it via `reserved_properties`.
  mangle_properties : Bool
  // Additional property names to keep verbatim when
  // `mangle_properties=true`. Combined with the built-in property
  // reserved set.
  reserved_properties : Array[String]
}

///|
pub fn ManglerConfig::default() -> ManglerConfig {
  {
    reserved: [],
    preserve_top_level: true,
    mangle_properties: false,
    reserved_properties: [],
  }
}

///|
pub fn ManglerConfig::with_reserved(
  self : ManglerConfig,
  names : Array[String],
) -> ManglerConfig {
  let merged : Array[String] = []
  for n in self.reserved {
    merged.push(n)
  }
  for n in names {
    merged.push(n)
  }
  { ..self, reserved: merged }
}

///|
pub fn ManglerConfig::with_preserve_top_level(
  self : ManglerConfig,
  preserve : Bool,
) -> ManglerConfig {
  { ..self, preserve_top_level: preserve }
}

///|
pub fn ManglerConfig::with_mangle_properties(
  self : ManglerConfig,
  enable : Bool,
) -> ManglerConfig {
  { ..self, mangle_properties: enable }
}

///|
pub fn ManglerConfig::with_reserved_properties(
  self : ManglerConfig,
  names : Array[String],
) -> ManglerConfig {
  let merged : Array[String] = []
  for n in self.reserved_properties {
    merged.push(n)
  }
  for n in names {
    merged.push(n)
  }
  { ..self, reserved_properties: merged }
}

// ---------------------------------------------------------------------------
// Built-in reserved set
// ---------------------------------------------------------------------------

///|
/// Names every browser / Node engine looks up at runtime. Renaming
/// any of these would silently break the program, so the mangler
/// treats them as reserved unconditionally.
let mangler_builtin_reserved : Array[String] = [
  // JS / ECMAScript globals
  "undefined", "null", "true", "false", "this", "globalThis", "Object", "Array",
  "Function", "Boolean", "Number", "String", "Symbol", "BigInt", "RegExp", "Date",
  "Error", "TypeError", "RangeError", "SyntaxError", "ReferenceError", "EvalError",
  "URIError", "AggregateError", "Math", "JSON", "Promise", "Map", "Set", "WeakMap",
  "WeakSet", "WeakRef", "FinalizationRegistry", "Proxy", "Reflect", "Int8Array",
  "Uint8Array", "Uint8ClampedArray", "Int16Array", "Uint16Array", "Int32Array", "Uint32Array",
  "Float32Array", "Float64Array", "BigInt64Array", "BigUint64Array", "ArrayBuffer",
  "SharedArrayBuffer", "DataView", "Atomics", "Iterator", "AsyncIterator", "Generator",
  "AsyncGenerator", "Infinity", "NaN", "isNaN", "isFinite", "parseInt", "parseFloat",
  "encodeURI", "decodeURI", "encodeURIComponent", "decodeURIComponent", "escape",
  "unescape", "eval",
  // Browser globals
   "window", "document", "location", "navigator", "history", "console", "alert",
  "confirm", "prompt", "fetch", "XMLHttpRequest", "WebSocket", "setTimeout", "setInterval",
  "clearTimeout", "clearInterval", "requestAnimationFrame", "cancelAnimationFrame",
  "queueMicrotask",
  // Module / runtime
   "require", "module", "exports", "__dirname", "__filename", "Buffer", "process",
  // React / JSX runtime (so JSX-lowering output keeps working)
   "jsx", "jsxs", "jsxDEV", "jsxsDEV", "Fragment", "React",
  // Keywords that can't be used as identifiers anyway
   "let", "const", "var", "function", "class", "if", "else", "return", "for", "while",
  "do", "switch", "case", "default", "break", "continue", "throw", "try", "catch",
  "finally", "new", "delete", "typeof", "instanceof", "void", "in", "of", "yield",
  "await", "async", "import", "export", "from", "as", "extends", "super", "static",
  "public", "private", "protected", "readonly", "implements", "interface", "type",
  "namespace", "module", "declare", "abstract", "with", "debugger", "enum",
]

///|
/// Property keys we never rename even when `mangle_properties` is
/// `true`. Covers the common surface: Object/Array/String/Number
/// prototypes, Promise, JSON, DOM, React, common iterator protocol
/// hooks. Users extend via `reserved_properties`.
let mangler_builtin_reserved_properties : Array[String] = [
  // Object / inheritance
  "constructor", "prototype", "hasOwnProperty", "isPrototypeOf", "propertyIsEnumerable",
  "toString", "valueOf", "toLocaleString", "__proto__", "__defineGetter__", "__defineSetter__",
  // Array / iterable
   "length", "push", "pop", "shift", "unshift", "slice", "splice", "concat", "join",
  "reverse", "sort", "indexOf", "lastIndexOf", "includes", "find", "findIndex", "findLast",
  "findLastIndex", "filter", "map", "reduce", "reduceRight", "forEach", "every",
  "some", "flat", "flatMap", "keys", "values", "entries", "fill", "copyWithin", "at",
  // String
   "charAt", "charCodeAt", "codePointAt", "startsWith", "endsWith", "padStart", "padEnd",
  "trim", "trimStart", "trimEnd", "trimLeft", "trimRight", "toUpperCase", "toLowerCase",
  "toLocaleUpperCase", "toLocaleLowerCase", "replace", "replaceAll", "split", "match",
  "matchAll", "search", "substring", "substr", "repeat", "normalize", "raw",
  // Number / Math
   "toFixed", "toPrecision", "toExponential", "toLocaleString",
  // Math statics — every method on the global `Math` object.
  // Phase 5 retires the External-binding wildcard fallback;
  // without these listed, bundles that call `Math.floor(...)` /
  // `Math.min(...)` ended up renaming the method down to one
  // letter and crashing at runtime.
   "abs", "acos", "acosh", "asin", "asinh", "atan", "atan2", "atanh", "cbrt", "ceil",
  "clz32", "cos", "cosh", "exp", "expm1", "floor", "fround", "hypot", "imul", "log",
  "log10", "log1p", "log2", "max", "min", "pow", "random", "round", "sign", "sin",
  "sinh", "sqrt", "tan", "tanh", "trunc",
  // Math constants
   "E", "LN2", "LN10", "LOG2E", "LOG10E", "PI", "SQRT1_2", "SQRT2",
  // Number statics
   "isInteger", "isFinite", "isNaN", "isSafeInteger", "parseFloat", "parseInt", "EPSILON",
  "MAX_SAFE_INTEGER", "MIN_SAFE_INTEGER", "MAX_VALUE", "MIN_VALUE", "POSITIVE_INFINITY",
  "NEGATIVE_INFINITY", "NaN",
  // Object statics (the ones not already covered above)
   "assign", "create", "defineProperty", "defineProperties", "freeze", "fromEntries",
  "getOwnPropertyDescriptor", "getOwnPropertyDescriptors", "getOwnPropertyNames",
  "getOwnPropertySymbols", "getPrototypeOf", "is", "isExtensible", "isFrozen", "isSealed",
  "preventExtensions", "seal", "setPrototypeOf",
  // Array statics
   "from", "isArray", "of",
  // Date statics
   "now", "UTC",
  // String statics
   "fromCharCode", "fromCodePoint",
  // Symbol well-knowns the runtime reads off Symbol itself
   "for", "keyFor", "hasInstance", "isConcatSpreadable", "match", "matchAll", "replace",
  "search", "species", "split", "toPrimitive", "toStringTag", "unscopables", "dispose",
  "asyncDispose",
  // Function
   "call", "apply", "bind", "name", "arguments", "caller",
  // Promise
   "then", "catch", "finally", "all", "allSettled", "race", "any", "resolve", "reject",
  "withResolvers",
  // JSON
   "parse", "stringify", "toJSON",
  // Map / Set
   "size", "has", "get", "set", "delete", "clear", "add",
  // Iterator protocol
   "next", "return", "throw", "done", "value",
  // Symbol well-knowns (the property access forms)
   "iterator", "asyncIterator",
  // DOM / events
   "addEventListener", "removeEventListener", "dispatchEvent", "target", "currentTarget",
  "preventDefault", "stopPropagation", "stopImmediatePropagation", "type", "bubbles",
  "cancelable", "innerHTML", "outerHTML", "innerText", "outerText", "textContent",
  "appendChild", "removeChild", "replaceChild", "insertBefore", "cloneNode", "childNodes",
  "children", "firstChild", "lastChild", "firstElementChild", "lastElementChild",
  "parentNode", "parentElement", "nextSibling", "previousSibling", "nextElementSibling",
  "previousElementSibling", "nodeType", "nodeName", "nodeValue", "tagName", "id",
  "className", "classList", "style", "dataset", "attributes", "getAttribute", "setAttribute",
  "removeAttribute", "hasAttribute", "querySelector", "querySelectorAll", "getElementById",
  "getElementsByTagName", "getElementsByClassName", "scrollTop", "scrollLeft", "scrollWidth",
  "scrollHeight", "offsetTop", "offsetLeft", "offsetWidth", "offsetHeight", "clientTop",
  "clientLeft", "clientWidth", "clientHeight", "getBoundingClientRect", "matches",
  "closest",
  // Web Storage / URL / fetch
   "localStorage", "sessionStorage", "setItem", "getItem", "removeItem", "key", "url",
  "method", "headers", "body", "status", "statusText", "ok", "redirected", "json",
  "text", "blob", "arrayBuffer", "formData", "clone",
  // React
   "render", "props", "state", "setState", "forceUpdate", "ref", "key", "children",
  "context", "displayName", "defaultProps", "propTypes", "contextType", "shouldComponentUpdate",
  "componentDidMount", "componentDidUpdate", "componentWillUnmount", "getSnapshotBeforeUpdate",
  "componentDidCatch", "getDerivedStateFromError", "getDerivedStateFromProps", "useState",
  "useEffect", "useLayoutEffect", "useMemo", "useCallback", "useRef", "useContext",
  "useReducer", "useImperativeHandle", "useDebugValue", "useDeferredValue", "useTransition",
  "useId", "useSyncExternalStore", "useInsertionEffect",
  // Node.js common
   "stdout", "stderr", "stdin", "env", "argv", "exit", "pid", "cwd", "chdir", "platform",
  "version", "versions", "readFile", "writeFile", "readFileSync", "writeFileSync",
  "exists", "existsSync", "mkdir", "mkdirSync", "rmdir", "unlink", "stat", "statSync",
  "createReadStream", "createWriteStream",
  // RegExp instance methods + properties
   "test", "exec", "source", "flags", "global", "ignoreCase", "multiline", "sticky",
  "unicode", "unicodeSets", "dotAll", "hasIndices", "lastIndex",
  // Error / standard exception members
   "message", "cause", "stack", "fileName", "lineNumber", "columnNumber",
  // Async / generator iterator protocol (`Symbol.asyncIterator` access too)
   "asyncIterator",
  // Date instance methods
   "getDate", "getDay", "getFullYear", "getHours", "getMilliseconds", "getMinutes",
  "getMonth", "getSeconds", "getTime", "getTimezoneOffset", "getUTCDate", "getUTCDay",
  "getUTCFullYear", "getUTCHours", "getUTCMilliseconds", "getUTCMinutes", "getUTCMonth",
  "getUTCSeconds", "getYear", "setDate", "setFullYear", "setHours", "setMilliseconds",
  "setMinutes", "setMonth", "setSeconds", "setTime", "setUTCDate", "setUTCFullYear",
  "setUTCHours", "setUTCMilliseconds", "setUTCMinutes", "setUTCMonth", "setUTCSeconds",
  "setYear", "toDateString", "toISOString", "toJSON", "toTimeString", "toUTCString",
  // Console / Hono / common Web APIs
   "log", "info", "warn", "error", "debug", "trace", "table", "group", "groupEnd",
  "dir", "count", "time", "timeEnd", "assert",
  // Common reserved
   "default",
]

// ---------------------------------------------------------------------------
// Property name renaming
// ---------------------------------------------------------------------------

///|
/// Collect every property key referenced in the block. Used by the
/// property-mangling pass to figure out which names are eligible
/// for renaming.
fn collect_property_names(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for stmt in block.stmts {
    collect_props_in_stmt(stmt, out)
  }
}

///|
fn collect_props_in_stmt(stmt : @ast.TsStmt, out : Map[String, Bool]) -> Unit {
  match stmt {
    Var(b, _, e) | Let(b, _, e) | Const(b, _, e) => {
      collect_props_in_binding(b, out)
      collect_props_in_expr(e, out)
    }
    Expr(e) | Throw(e) => collect_props_in_expr(e, out)
    Return(opt) =>
      match opt {
        Some(e) => collect_props_in_expr(e, out)
        None => ()
      }
    Assign(_, e) | CompoundAssign(_, _, e) => collect_props_in_expr(e, out)
    PropAssign(recv, prop, value) => {
      out[prop] = true
      collect_props_in_expr(recv, out)
      collect_props_in_expr(value, out)
    }
    IndexAssign(recv, idx, value) => {
      collect_props_in_expr(recv, out)
      collect_props_in_expr(idx, out)
      collect_props_in_expr(value, out)
    }
    If(c, t, e_opt) => {
      collect_props_in_expr(c, out)
      collect_property_names(t, out)
      match e_opt {
        Some(b) => collect_property_names(b, out)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) => {
      collect_props_in_expr(c, out)
      collect_property_names(b, out)
    }
    For(init_opt, cond_opt, update_opt, body) => {
      match init_opt {
        Some(s) => collect_props_in_stmt(s, out)
        None => ()
      }
      match cond_opt {
        Some(c) => collect_props_in_expr(c, out)
        None => ()
      }
      match update_opt {
        Some(s) => collect_props_in_stmt(s, out)
        None => ()
      }
      collect_property_names(body, out)
    }
    ForOf(_, b, _, iter, body)
    | ForAwaitOf(_, b, _, iter, body)
    | ForIn(_, b, _, iter, body) => {
      collect_props_in_binding(b, out)
      collect_props_in_expr(iter, out)
      collect_property_names(body, out)
    }
    Switch(scrutinee, cases) => {
      collect_props_in_expr(scrutinee, out)
      for c in cases {
        match c.test_expr {
          Some(t) => collect_props_in_expr(t, out)
          None => ()
        }
        collect_property_names(c.body, out)
      }
    }
    Try(t, _, c, f) => {
      collect_property_names(t, out)
      match c {
        Some(b) => collect_property_names(b, out)
        None => ()
      }
      match f {
        Some(b) => collect_property_names(b, out)
        None => ()
      }
    }
    Block(b) => collect_property_names(b, out)
    Label(_, inner) => collect_props_in_stmt(inner, out)
    With(target, body) => {
      collect_props_in_expr(target, out)
      collect_property_names(body, out)
    }
    Break(_) | Continue(_) | Empty | Debugger => ()
    NativeClassStmt(decl, ctor) => {
      // Collect method names so they become candidates in the rename
      // map and are also shortened when called via `this.method()`.
      for m in decl.methods {
        out[m.name] = true
        match m.body {
          Some(b) => collect_property_names(b, out)
          None => ()
        }
      }
      for p in decl.properties {
        out[p.name] = true
      }
      for sf in decl.static_field_inits {
        out[sf.0] = true
        collect_props_in_expr(sf.1, out)
      }
      match ctor {
        Some(f) => collect_property_names(f.body, out)
        None => ()
      }
    }
  }
}

///|
fn collect_props_in_binding(
  binding : @ast.TsBinding,
  out : Map[String, Bool],
) -> Unit {
  match binding {
    Ident(_) => ()
    Array(ab) => {
      for elem in ab.items {
        match elem {
          Some(be) => {
            collect_props_in_binding(be.binding, out)
            match be.default {
              Some(d) => collect_props_in_expr(d, out)
              None => ()
            }
          }
          None => ()
        }
      }
      match ab.rest {
        Some(r) => collect_props_in_binding(r, out)
        None => ()
      }
    }
    Object(ob) =>
      for p in ob.props {
        out[p.key] = true
        collect_props_in_binding(p.binding, out)
        match p.default {
          Some(d) => collect_props_in_expr(d, out)
          None => ()
        }
      }
    Target(e) => collect_props_in_expr(e, out)
  }
}

///|
fn collect_props_in_expr(expr : @ast.TsExpr, out : Map[String, Bool]) -> Unit {
  match expr {
    PropAccess(recv, name) => {
      out[name] = true
      collect_props_in_expr(recv, out)
    }
    MethodCall(recv, method, args) => {
      out[method] = true
      collect_props_in_expr(recv, out)
      for a in args {
        collect_props_in_expr(a, out)
      }
    }
    ObjectLit(entries) =>
      for ent in entries {
        if ent.0 != "..." {
          out[ent.0] = true
        }
        collect_props_in_expr(ent.1, out)
      }
    PropAssignExpr(recv, prop, value) => {
      out[prop] = true
      collect_props_in_expr(recv, out)
      collect_props_in_expr(value, out)
    }
    IndexAssignExpr(recv, idx, value) => {
      collect_props_in_expr(recv, out)
      collect_props_in_expr(idx, out)
      collect_props_in_expr(value, out)
    }
    Call(_, args) | New(_, args) =>
      for a in args {
        collect_props_in_expr(a, out)
      }
    CallExpr(callee, args) | NewExpr(callee, args) => {
      collect_props_in_expr(callee, out)
      for a in args {
        collect_props_in_expr(a, out)
      }
    }
    IndexAccess(recv, idx) => {
      collect_props_in_expr(recv, out)
      collect_props_in_expr(idx, out)
    }
    BinOp(_, l, r) => {
      collect_props_in_expr(l, out)
      collect_props_in_expr(r, out)
    }
    UnaryOp(_, inner) => collect_props_in_expr(inner, out)
    Cond(c, t, e) => {
      collect_props_in_expr(c, out)
      collect_props_in_expr(t, out)
      collect_props_in_expr(e, out)
    }
    ArrayLit(items) =>
      for i in items {
        collect_props_in_expr(i, out)
      }
    Spread(inner) | Await(inner) | YieldStar(inner) =>
      collect_props_in_expr(inner, out)
    Yield(opt) =>
      match opt {
        Some(e) => collect_props_in_expr(e, out)
        None => ()
      }
    Seq(a, b) => {
      collect_props_in_expr(a, out)
      collect_props_in_expr(b, out)
    }
    ComputedProp(k, v) => {
      collect_props_in_expr(k, out)
      collect_props_in_expr(v, out)
    }
    AssignExpr(_, value)
    | CompoundAssignExpr(_, _, value)
    | AssignPattern(_, value) => collect_props_in_expr(value, out)
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_props_in_expr(e, out)
        ArrowBlock(b) => collect_property_names(b, out)
      }
    FuncExpr(f) => collect_property_names(f.body, out)
    DynamicImport(spec, opts) => {
      collect_props_in_expr(spec, out)
      match opts {
        Some(o) => collect_props_in_expr(o, out)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      collect_props_in_expr(tag, out)
      for e in exprs {
        collect_props_in_expr(e, out)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_props_in_expr(e, out)
      }
    As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner) => collect_props_in_expr(inner, out)
    NativeClassExpr(decl, ctor) => {
      for m in decl.methods {
        out[m.name] = true
        match m.body {
          Some(b) => collect_property_names(b, out)
          None => ()
        }
      }
      for p in decl.properties {
        out[p.name] = true
      }
      for sf in decl.static_field_inits {
        out[sf.0] = true
        collect_props_in_expr(sf.1, out)
      }
      match ctor {
        Some(f) => collect_property_names(f.body, out)
        None => ()
      }
    }
    _ => ()
  }
}

///|
/// Build a `original_name → mangled_name` map for every property
/// name referenced in `block` that isn't in the reserved set.
/// Mangled names are assigned in observation order so the output is
/// deterministic across runs.
fn build_property_rename_map(
  block : @ast.TsBlock,
  reserved : Map[String, Bool],
) -> Map[String, String] {
  let names : Map[String, Bool] = {}
  collect_property_names(block, names)
  // Filter to mangleable names, then sort so the mapping is stable
  // across iteration orders.
  let candidates : Array[String] = []
  for entry in names {
    let n = entry.0
    if reserved.contains(n) {
      continue
    }
    // Internal parser sentinels (`@@spread:N`, `@@computed:N`,
    // `@@get:NAME`, `@@set:NAME`) are NOT property names — they
    // tag where the emit should produce spread / computed-key /
    // accessor shorthand. Renaming them to short keys turns the
    // sentinel into a regular key and the emit's pattern match
    // misses it, producing invalid output like
    // `{a:[a]:42}` for `{[s]: 42}`.
    if n.has_prefix("@@") {
      continue
    }
    candidates.push(n)
  }
  candidates.sort()
  let map : Map[String, String] = {}
  let mut counter = 0
  for n in candidates {
    let mut candidate = next_short_name(counter)
    counter = counter + 1
    while reserved.contains(candidate) {
      candidate = next_short_name(counter)
      counter = counter + 1
    }
    map[n] = candidate
  }
  map
}

// ---------------------------------------------------------------------------
// Scope tracking
// ---------------------------------------------------------------------------

///|
priv struct ScopeFrame {
  parent : ScopeFrame?
  // Map from original name to its mangled rename. A missing entry
  // means the name is reserved (no rename) or resolved through a
  // parent scope.
  renames : Map[String, String]
  // Every short name already taken in this scope or any of its
  // ancestors — used so generated names don't shadow a still-
  // reachable binding.
  used : Map[String, Bool]
  // Counter for the next short name to allocate.
  mut counter : Int
  // Reserved-name set — shared across the whole scope tree so nested
  // functions / arrow bodies see the same names as the root.
  reserved : Map[String, Bool]
  // When true, `is_used_in_chain` stops here instead of walking up.
  // Used for function-scope frames so params can shadow outer bindings.
  is_function_scope : Bool
}

///|
fn ScopeFrame::new_root(reserved : Map[String, Bool]) -> ScopeFrame {
  let used : Map[String, Bool] = {}
  for entry in reserved {
    let (n, _) = entry
    used[n] = true
  }
  {
    parent: None,
    renames: {},
    used,
    counter: 0,
    reserved,
    is_function_scope: false,
  }
}

///|
fn ScopeFrame::child(parent : ScopeFrame) -> ScopeFrame {
  // Previously this copied parent.used into the new frame so the
  // bind-collision check could read it as a single hash lookup. For
  // a bundle with 200+ modules concatenated into one root frame,
  // the root's used set grows into the thousands and every nested
  // scope pays an O(|parent.used|) creation cost. Walking the chain
  // on lookup is cheaper for shallow / typical scope trees.
  //
  // Counter starts at the parent's so child allocations land
  // ABOVE every name the parent has already taken, dodging
  // collisions without needing the eager copy.
  {
    parent: Some(parent),
    renames: {},
    used: {},
    counter: parent.counter,
    reserved: parent.reserved,
    is_function_scope: false,
  }
}

///|
/// True when any frame in the chain starting at `self` records
/// `name` as already used. Stops at function-scope frames because
/// function params/locals can legally shadow outer bindings.
fn ScopeFrame::is_used_in_chain(self : ScopeFrame, name : String) -> Bool {
  let mut cur : ScopeFrame? = Some(self)
  while cur is Some(frame) {
    if frame.used.contains(name) {
      return true
    }
    // Stop at function scope boundaries — params/locals inside a function
    // can shadow outer bindings, so we don't need to check further up.
    if frame.is_function_scope {
      return false
    }
    cur = frame.parent
  }
  false
}

///|
/// Create a fresh scope for a function body. Starts the counter at 0 so
/// params get short 1-char names. Pre-marks the short names of any
/// outer-scope variables referenced inside `body` as occupied, preventing
/// params from accidentally shadowing a captured outer binding.
fn ScopeFrame::function_child(
  parent : ScopeFrame,
  body : @ast.TsBlock,
) -> ScopeFrame {
  // Collect all Var references inside the body (non-recursive: stops at
  // nested function boundaries so we only see free vars of this level).
  let refs : Map[String, Bool] = {}
  collect_var_refs_block(body, refs)
  // For each referenced name, look up its short name via the parent chain.
  // If it was renamed, pre-occupy that short name in the new scope so the
  // param allocator skips it.
  let used : Map[String, Bool] = {}
  for name, _ in refs {
    // Mark the resolved short name (even when unchanged) so inner-scope
    // param allocation never shadows an outer free variable. Without this,
    // a var like `a` that the parent kept as `a` is NOT added to `used`,
    // and a nested function's first parameter gets renamed to `a`, silently
    // shadowing the captured outer `a`. E.g. Effect's `dual/case 3`:
    //   function(a, c, d) { ... function(a) { b(a, a, c) } } // BUG
    // The inner param `a` shadows outer `a`; `b(a,a,c)` passes self twice.
    used[parent.resolve(name)] = true
  }
  {
    parent: Some(parent),
    renames: {},
    used,
    counter: 0,
    reserved: parent.reserved,
    is_function_scope: true,
  }
}

///|
/// Collect all `Var(name)` references in `block`, not descending into
/// nested function / arrow bodies (they have independent scopes).
fn collect_var_refs_block(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    collect_var_refs_stmt(s, out)
  }
}

///|
fn collect_var_refs_stmt(stmt : @ast.TsStmt, out : Map[String, Bool]) -> Unit {
  match stmt {
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) =>
      collect_var_refs_expr(e, out)
    Assign(name, e) => {
      out[name] = true
      collect_var_refs_expr(e, out)
    }
    CompoundAssign(name, _, e) => {
      out[name] = true
      collect_var_refs_expr(e, out)
    }
    IndexAssign(t, k, v) => {
      collect_var_refs_expr(t, out)
      collect_var_refs_expr(k, out)
      collect_var_refs_expr(v, out)
    }
    PropAssign(t, _, v) => {
      collect_var_refs_expr(t, out)
      collect_var_refs_expr(v, out)
    }
    Expr(e) => collect_var_refs_expr(e, out)
    Return(Some(e)) => collect_var_refs_expr(e, out)
    Return(None) => ()
    Throw(e) => collect_var_refs_expr(e, out)
    Try(b, _, catch_b, finally_b) => {
      collect_var_refs_block(b, out)
      match catch_b {
        Some(cb) => collect_var_refs_block(cb, out)
        None => ()
      }
      match finally_b {
        Some(fb) => collect_var_refs_block(fb, out)
        None => ()
      }
    }
    If(cond, then_b, else_b) => {
      collect_var_refs_expr(cond, out)
      collect_var_refs_block(then_b, out)
      match else_b {
        Some(eb) => collect_var_refs_block(eb, out)
        None => ()
      }
    }
    While(cond, b) | DoWhile(cond, b) => {
      collect_var_refs_expr(cond, out)
      collect_var_refs_block(b, out)
    }
    For(init, cond, update, b) => {
      match init {
        Some(s) => collect_var_refs_stmt(s, out)
        None => ()
      }
      match cond {
        Some(e) => collect_var_refs_expr(e, out)
        None => ()
      }
      match update {
        Some(s) => collect_var_refs_stmt(s, out)
        None => ()
      }
      collect_var_refs_block(b, out)
    }
    ForOf(_, _, _, e, b) | ForIn(_, _, _, e, b) | ForAwaitOf(_, _, _, e, b) => {
      collect_var_refs_expr(e, out)
      collect_var_refs_block(b, out)
    }
    Switch(e, cases) => {
      collect_var_refs_expr(e, out)
      for c in cases {
        match c.test_expr {
          Some(te) => collect_var_refs_expr(te, out)
          None => ()
        }
        collect_var_refs_block(c.body, out)
      }
    }
    Block(b) => collect_var_refs_block(b, out)
    Label(_, s) => collect_var_refs_stmt(s, out)
    NativeClassStmt(_, _) => () // class body has its own scope
    With(e, b) => {
      collect_var_refs_expr(e, out)
      collect_var_refs_block(b, out)
    }
    Empty | Break(_) | Continue(_) | Debugger => ()
  }
}

///|
fn collect_var_refs_expr(expr : @ast.TsExpr, out : Map[String, Bool]) -> Unit {
  match expr {
    Var(name) => out[name] = true
    BinOp(_, a, b) => {
      collect_var_refs_expr(a, out)
      collect_var_refs_expr(b, out)
    }
    UnaryOp(_, e) => collect_var_refs_expr(e, out)
    Call(callee, args) => {
      // `callee` is the bare identifier being called (`init(...)`).
      // It is a free reference just like any other `Var`, so a nested
      // function that calls an outer binding must mark its short name
      // occupied or a local could shadow it.
      out[callee] = true
      for a in args {
        collect_var_refs_expr(a, out)
      }
    }
    CallExpr(f, args) => {
      collect_var_refs_expr(f, out)
      for a in args {
        collect_var_refs_expr(a, out)
      }
    }
    Cond(c, t, f) => {
      collect_var_refs_expr(c, out)
      collect_var_refs_expr(t, out)
      collect_var_refs_expr(f, out)
    }
    ArrayLit(elems) =>
      for e in elems {
        collect_var_refs_expr(e, out)
      }
    Spread(e) => collect_var_refs_expr(e, out)
    ObjectLit(pairs) =>
      for pair in pairs {
        collect_var_refs_expr(pair.1, out)
      }
    ComputedProp(k, v) => {
      collect_var_refs_expr(k, out)
      collect_var_refs_expr(v, out)
    }
    IndexAccess(t, k) => {
      collect_var_refs_expr(t, out)
      collect_var_refs_expr(k, out)
    }
    PropAccess(t, _) => collect_var_refs_expr(t, out)
    New(callee, args) => {
      out[callee] = true
      for a in args {
        collect_var_refs_expr(a, out)
      }
    }
    NewExpr(c, args) => {
      collect_var_refs_expr(c, out)
      for a in args {
        collect_var_refs_expr(a, out)
      }
    }
    MethodCall(t, _, args) => {
      collect_var_refs_expr(t, out)
      for a in args {
        collect_var_refs_expr(a, out)
      }
    }
    AssignExpr(name, e) => {
      out[name] = true
      collect_var_refs_expr(e, out)
    }
    AssignPattern(_, e) => collect_var_refs_expr(e, out)
    CompoundAssignExpr(t, _, v) => {
      collect_var_refs_expr(t, out)
      collect_var_refs_expr(v, out)
    }
    PropAssignExpr(t, _, v) => {
      collect_var_refs_expr(t, out)
      collect_var_refs_expr(v, out)
    }
    IndexAssignExpr(t, k, v) => {
      collect_var_refs_expr(t, out)
      collect_var_refs_expr(k, out)
      collect_var_refs_expr(v, out)
    }
    Seq(a, b) => {
      collect_var_refs_expr(a, out)
      collect_var_refs_expr(b, out)
    }
    // Recurse into function/arrow bodies to collect outer-scope references
    // that inner closures capture. This is used by function_child to pre-
    // occupy short names of outer bindings that inner closures reference —
    // preventing the inner closure's local name from shadowing the outer name.
    ArrowFunc(params, _, body, _) => {
      for p in params {
        match p.default {
          Some(d) => collect_var_refs_expr(d, out)
          None => ()
        }
      }
      match body {
        ArrowExpr(e) => collect_var_refs_expr(e, out)
        ArrowBlock(b) => collect_var_refs_block(b, out)
      }
    }
    FuncExpr(f) => {
      for p in f.params {
        match p.default {
          Some(d) => collect_var_refs_expr(d, out)
          None => ()
        }
      }
      collect_var_refs_block(f.body, out)
    }
    Await(e) => collect_var_refs_expr(e, out)
    Yield(Some(e)) => collect_var_refs_expr(e, out)
    YieldStar(e) => collect_var_refs_expr(e, out)
    DynamicImport(e, _) => collect_var_refs_expr(e, out)
    TaggedTemplate(tag, _, _, exprs) => {
      collect_var_refs_expr(tag, out)
      for e in exprs {
        collect_var_refs_expr(e, out)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        collect_var_refs_expr(e, out)
      }
    As(e, _) | Satisfies(e, _) | NonNull(e) | PureCall(e) | OptionalChain(e) =>
      collect_var_refs_expr(e, out)
    NativeClassExpr(_, _) => ()
    JsxElement(_, attrs, children) => {
      for attr in attrs {
        match attr.1 {
          Some(e) => collect_var_refs_expr(e, out)
          None => ()
        }
      }
      for c in children {
        collect_var_refs_expr(c, out)
      }
    }
    NumberLit(_)
    | IntLit(_)
    | BigIntLit(_)
    | BoolLit(_)
    | StringLit(_)
    | NullLit
    | ArrayHole
    | ImportMeta
    | Yield(None) => ()
  }
}

///|
/// Resolve `name` through the scope chain; returns the mangled
/// identifier (or the original when nothing was registered).
fn ScopeFrame::resolve(self : ScopeFrame, name : String) -> String {
  let mut cur : ScopeFrame? = Some(self)
  while cur is Some(frame) {
    match frame.renames.get(name) {
      Some(renamed) => return renamed
      None => cur = frame.parent
    }
  }
  name
}

///|
/// Register `name` as declared in this scope. Returns the chosen
/// mangled name (the original when the name is in the reserved set
/// or any ancestor frame has it as used and we can't safely
/// generate a new one).
fn ScopeFrame::bind(
  self : ScopeFrame,
  name : String,
  reserved : Map[String, Bool],
) -> String {
  // Idempotency: if this frame already chose a rename for `name`
  // (e.g. via the function-declaration hoist pre-pass) return it
  // instead of allocating a fresh short slot. Multiple `bind` calls
  // for the same name in the same frame would otherwise pick
  // different shorts and break references.
  match self.renames.get(name) {
    Some(existing) => return existing
    None => ()
  }
  // Reserved names stay put. They still mark themselves as used so
  // subsequent declarations don't pick a colliding short name.
  if reserved.contains(name) {
    self.used[name] = true
    self.renames[name] = name
    return name
  }
  // Allocate the next free short name. Bump `counter` until the
  // generated name isn't already used in this frame's chain or in
  // the reserved set.
  let mut candidate = next_short_name(self.counter)
  self.counter = self.counter + 1
  while self.is_used_in_chain(candidate) || reserved.contains(candidate) {
    candidate = next_short_name(self.counter)
    self.counter = self.counter + 1
  }
  self.used[candidate] = true
  self.renames[name] = candidate
  candidate
}

///|
/// Generate the `n`th short identifier in lexicographic order.
///
/// First-character alphabet (52 chars): `a-z` then `A-Z`. Subsequent-
/// character alphabet (62 chars): the first set + `0-9`. The
/// encoding is bijective from `n` to a non-empty identifier:
///
///   0..52    → single char (`a`, `b`, …, `z`, `A`, …, `Z`)
///   52..3276 → two chars (`aa`, `ab`, …, `Z9`)
///   3276..   → three chars (`aaa`, …)
///
/// The first character can't be a digit, so the leading position
/// uses the smaller alphabet. JS reserved keywords (`do`, `if`,
/// `in`, `as`, …) sit in `mangler_builtin_reserved` and the caller
/// skips them by bumping the counter — `next_short_name` itself is
/// pure index-to-name.
fn next_short_name(n : Int) -> String {
  let first_alpha = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  let subseq_alpha = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  // 1. Find the length L such that n falls in the L-char band:
  //    capacity(L) = 52 * 62^(L-1).
  let mut len = 1
  let mut consumed = 0
  let mut band = 52
  while n >= consumed + band {
    consumed = consumed + band
    band = band * 62
    len = len + 1
  }
  // 2. m = position within this band.
  let mut m = n - consumed
  // 3. Decompose m into digits, low-to-high.
  let digits : Array[Int] = []
  for _i in 0..<(len - 1) {
    digits.push(m % 62)
    m = m / 62
  }
  // The high digit picks from the 52-char first-alphabet.
  digits.push(m)
  // 4. Emit high → low.
  let buf = StringBuilder::new()
  let mut i = digits.length() - 1
  let n_digits = digits.length()
  while i >= 0 {
    let c = digits[i]
    if i == n_digits - 1 {
      buf.write_char(first_alpha[c].to_int().unsafe_to_char())
    } else {
      buf.write_char(subseq_alpha[c].to_int().unsafe_to_char())
    }
    i = i - 1
  }
  buf.to_string()
}

// ---------------------------------------------------------------------------
// Public entrypoint
// ---------------------------------------------------------------------------

///|
/// Run the local-identifier mangling pass over `block`. Returns a
/// new `TsBlock` with every function-local name renamed to a short
/// `a` / `b` / … identifier. Top-level bindings stay put when
/// `cfg.preserve_top_level` is `true`.
/// Variant of `mangle_block` that also returns the root scope's
/// final rename map so callers (typically the bundle layer
/// emitting `export default <name>` at the tail) can look up the
/// new short name for a known top-level binding.
pub fn mangle_block_with_renames(
  block : @ast.TsBlock,
  cfg : ManglerConfig,
) -> (@ast.TsBlock, Map[String, String]) {
  let (out, root) = mangle_block_impl(block, cfg)
  let renames : Map[String, String] = {}
  for entry in root.renames {
    renames[entry.0] = entry.1
  }
  (out, renames)
}

///|
pub fn mangle_block(block : @ast.TsBlock, cfg : ManglerConfig) -> @ast.TsBlock {
  let (out, _) = mangle_block_impl(block, cfg)
  out
}

///|
fn mangle_block_impl(
  block : @ast.TsBlock,
  cfg : ManglerConfig,
) -> (@ast.TsBlock, ScopeFrame) {
  // Reserved set = built-ins ∪ explicit ∪ (top-level decls when
  // `preserve_top_level`).
  let reserved : Map[String, Bool] = {}
  for n in mangler_builtin_reserved {
    reserved[n] = true
  }
  for n in cfg.reserved {
    reserved[n] = true
  }
  if cfg.preserve_top_level {
    collect_top_level_decls(block, reserved)
  }
  let root = ScopeFrame::new_root(reserved)
  // Predeclare top-level names in the root frame so child scopes can
  // see them but don't pick conflicting short names.
  for entry in reserved {
    let _ = root.bind(entry.0, reserved)
  }
  // Hoist every `var`-declared name into the module-level frame
  // before the recursive walk so cross-block references still
  // resolve once block-scoped frames take over inside `if` / `while`
  // / `try` bodies.
  hoist_var_decls_into_scope(block, root, reserved)
  // Pre-bind top-level function declarations so a forward
  // reference (a call site that precedes the `function f() {}`
  // declaration in source order) resolves to the SAME rename as
  // the declaration. The same logic already runs inside
  // `rename_block_inline_in` for nested blocks, but the top-level
  // walk below uses `rename_stmt` directly, bypassing it.
  //
  // Also pre-bind every other top-level `Let` / `Const` / `Var`
  // / `NativeClassStmt` binding so cross-IIFE forward references
  // (a method body inside an earlier class IIFE that names a
  // class declared later in the source — common pattern in
  // drizzle-orm's circular sql<->column refs) resolve to the
  // same rename as the eventual declaration site.
  for s in block.stmts {
    match s {
      Let(@ast.TsBinding::Ident(name), _, _)
      | Const(@ast.TsBinding::Ident(name), _, _)
      | Var(@ast.TsBinding::Ident(name), _, _) =>
        if not(root.renames.contains(name)) {
          let _ = root.bind(name, reserved)
        }
      NativeClassStmt(decl, _) =>
        if decl.name != "" && not(root.renames.contains(decl.name)) {
          let _ = root.bind(decl.name, reserved)
        }
      _ => ()
    }
  }
  // Identifier-mangling pass first (so any synthesized identifiers
  // can't collide with property names we're about to rename).
  let new_stmts : Array[@ast.TsStmt] = []
  for stmt in block.stmts {
    new_stmts.push(rename_stmt(stmt, root, reserved))
  }
  let renamed : @ast.TsBlock = {
    stmts: new_stmts,
    stmt_positions: block.stmt_positions,
  }
  // Optional property-name pass on top of the identifier rename.
  let final_block = if cfg.mangle_properties {
    let prop_reserved : Map[String, Bool] = {}
    for n in mangler_builtin_reserved_properties {
      prop_reserved[n] = true
    }
    for n in cfg.reserved_properties {
      prop_reserved[n] = true
    }
    let prop_map = build_property_rename_map(renamed, prop_reserved)
    rename_properties_in_block(renamed, prop_map)
  } else {
    renamed
  }
  (final_block, root)
}

///|
fn collect_top_level_decls(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for stmt in block.stmts {
    match stmt {
      Var(@ast.TsBinding::Ident(n), _, _)
      | Let(@ast.TsBinding::Ident(n), _, _)
      | Const(@ast.TsBinding::Ident(n), _, _) => out[n] = true
      Var(b, _, _) | Let(b, _, _) | Const(b, _, _) =>
        collect_binding_names(b, out)
      NativeClassStmt(decl, _) => if decl.name != "" { out[decl.name] = true }
      _ => ()
    }
  }
}

///|
fn collect_binding_names(
  binding : @ast.TsBinding,
  out : Map[String, Bool],
) -> Unit {
  match binding {
    Ident(n) => out[n] = true
    Array(ab) => {
      for elem in ab.items {
        match elem {
          Some(be) => collect_binding_names(be.binding, out)
          None => ()
        }
      }
      match ab.rest {
        Some(r) => collect_binding_names(r, out)
        None => ()
      }
    }
    Object(ob) => {
      for p in ob.props {
        collect_binding_names(p.binding, out)
      }
      match ob.rest {
        Some(n) => out[n] = true
        None => ()
      }
    }
    Target(_) => ()
  }
}

// ---------------------------------------------------------------------------
// var-hoisting
// ---------------------------------------------------------------------------
//
// `var` declarations are function-scoped: `if (cond) { var x = 1; }` makes
// `x` visible in the surrounding function regardless of which branch ran.
// Block-scope-aware renaming therefore has to pre-bind every `var` name
// (and the names introduced by destructured-`var` patterns) into the
// enclosing function frame *before* the walk dives into child block
// frames, otherwise a reference after the block fails to resolve.
//
// The walker stops descending at function / arrow boundaries — those
// open their own function-scope frame and run their own hoist pass.

///|
fn hoist_var_names_from_binding(
  binding : @ast.TsBinding,
  out : Map[String, Bool],
) -> Unit {
  match binding {
    Ident(n) => out[n] = true
    Array(ab) => {
      for elem in ab.items {
        match elem {
          Some(be) => hoist_var_names_from_binding(be.binding, out)
          None => ()
        }
      }
      match ab.rest {
        Some(r) => hoist_var_names_from_binding(r, out)
        None => ()
      }
    }
    Object(ob) => {
      for p in ob.props {
        hoist_var_names_from_binding(p.binding, out)
      }
      match ob.rest {
        Some(n) => out[n] = true
        None => ()
      }
    }
    Target(_) => ()
  }
}

///|
fn hoist_var_names_from_stmt(
  stmt : @ast.TsStmt,
  out : Map[String, Bool],
) -> Unit {
  match stmt {
    Var(b, _, _) => hoist_var_names_from_binding(b, out)
    Let(_, _, _) | Const(_, _, _) => ()
    If(_, t, e_opt) => {
      hoist_var_names_from_block(t, out)
      match e_opt {
        Some(b) => hoist_var_names_from_block(b, out)
        None => ()
      }
    }
    While(_, b) | DoWhile(_, b) => hoist_var_names_from_block(b, out)
    For(init_opt, _, _, body) => {
      match init_opt {
        Some(s) => hoist_var_names_from_stmt(s, out)
        None => ()
      }
      hoist_var_names_from_block(body, out)
    }
    ForOf(kind, b, _, _, body)
    | ForAwaitOf(kind, b, _, _, body)
    | ForIn(kind, b, _, _, body) => {
      if kind is Var {
        hoist_var_names_from_binding(b, out)
      }
      hoist_var_names_from_block(body, out)
    }
    Switch(_, cases) =>
      for c in cases {
        hoist_var_names_from_block(c.body, out)
      }
    Try(try_b, _, catch_b, finally_b) => {
      hoist_var_names_from_block(try_b, out)
      match catch_b {
        Some(b) => hoist_var_names_from_block(b, out)
        None => ()
      }
      match finally_b {
        Some(b) => hoist_var_names_from_block(b, out)
        None => ()
      }
    }
    Block(b) => hoist_var_names_from_block(b, out)
    Label(_, inner) => hoist_var_names_from_stmt(inner, out)
    With(_, body) => hoist_var_names_from_block(body, out)
    _ => ()
  }
}

///|
fn hoist_var_names_from_block(
  block : @ast.TsBlock,
  out : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    hoist_var_names_from_stmt(s, out)
  }
}

///|
/// Pre-bind every `var`-declared name visible in `block` into `scope`,
/// so subsequent block-scope frames resolve `Var(...)` references back
/// to this function-level binding. Idempotent on duplicates.
fn hoist_var_decls_into_scope(
  block : @ast.TsBlock,
  scope : ScopeFrame,
  reserved : Map[String, Bool],
) -> Unit {
  let names : Map[String, Bool] = {}
  hoist_var_names_from_block(block, names)
  // Sort so the rename map is deterministic across compiler runs.
  let sorted : Array[String] = []
  for entry in names {
    sorted.push(entry.0)
  }
  sorted.sort()
  for n in sorted {
    if scope.renames.contains(n) {
      continue
    }
    let _ = scope.bind(n, reserved)
  }
}

// ---------------------------------------------------------------------------
// AST walker
// ---------------------------------------------------------------------------

///|
fn rename_stmt(
  stmt : @ast.TsStmt,
  scope : ScopeFrame,
  reserved : Map[String, Bool],
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, init) =>
      // `var` names were pre-bound by `hoist_var_decls_into_scope` at the
      // enclosing function frame; resolve through the chain instead of
      // re-binding so a `var` inside a child block scope still maps to
      // the function-level rename.
      Var(rename_binding_lhs(b, scope), t, rename_expr(init, scope))
    Let(b, t, init) =>
      Let(rename_binding_decl(b, scope, reserved), t, rename_expr(init, scope))
    Const(b, t, init) =>
      Const(
        rename_binding_decl(b, scope, reserved),
        t,
        rename_expr(init, scope),
      )
    Expr(e) => Expr(rename_expr(e, scope))
    Return(opt) =>
      match opt {
        Some(e) => Return(Some(rename_expr(e, scope)))
        None => Return(None)
      }
    Throw(e) => Throw(rename_expr(e, scope))
    Assign(name, e) => Assign(scope.resolve(name), rename_expr(e, scope))
    CompoundAssign(name, op, e) =>
      CompoundAssign(scope.resolve(name), op, rename_expr(e, scope))
    PropAssign(recv, prop, value) =>
      PropAssign(rename_expr(recv, scope), prop, rename_expr(value, scope))
    IndexAssign(recv, idx, value) =>
      IndexAssign(
        rename_expr(recv, scope),
        rename_expr(idx, scope),
        rename_expr(value, scope),
      )
    If(cond, then_b, else_opt) => {
      // Each arm opens its own block-level frame so `let` / `const`
      // bindings introduced in one branch don't leak short-name slots
      // into the other. `var` bindings were already hoisted to the
      // enclosing function scope and resolve through the chain.
      let then_scope = ScopeFrame::child(scope)
      let then_renamed = rename_block_inline_in(then_b, then_scope, reserved)
      let else_renamed = match else_opt {
        Some(b) => {
          let else_scope = ScopeFrame::child(scope)
          Some(rename_block_inline_in(b, else_scope, reserved))
        }
        None => None
      }
      If(rename_expr(cond, scope), then_renamed, else_renamed)
    }
    While(c, b) => {
      let inner = ScopeFrame::child(scope)
      While(rename_expr(c, scope), rename_block_inline_in(b, inner, reserved))
    }
    DoWhile(c, b) => {
      let inner = ScopeFrame::child(scope)
      DoWhile(rename_expr(c, scope), rename_block_inline_in(b, inner, reserved))
    }
    For(init_opt, cond_opt, update_opt, body) => {
      // `for (let i = 0; …; …) { … }` creates a new lexical scope.
      let inner = ScopeFrame::child(scope)
      // The parser wraps multi-decl init (`for (let i = 0, n = arr.length;
      // …)`) as a `Block` of single-binding decls. The generic
      // `Block(b)` rename would spawn ANOTHER child scope and the
      // bindings would never make it into `inner` — so `cond` /
      // `update` would see the original names. Detect that shape
      // and rename each inner decl directly in `inner`.
      let new_init = match init_opt {
        Some(Block(b)) => {
          let new_stmts : Array[@ast.TsStmt] = []
          for s in b.stmts {
            new_stmts.push(rename_stmt(s, inner, reserved))
          }
          Some(
            @ast.TsStmt::Block({
              stmts: new_stmts,
              stmt_positions: b.stmt_positions,
            }),
          )
        }
        Some(s) => Some(rename_stmt(s, inner, reserved))
        None => None
      }
      let new_cond = match cond_opt {
        Some(c) => Some(rename_expr(c, inner))
        None => None
      }
      let new_update = match update_opt {
        Some(s) => Some(rename_stmt(s, inner, reserved))
        None => None
      }
      let new_body = rename_block_inline(body, inner, reserved)
      For(new_init, new_cond, new_update, new_body)
    }
    ForOf(kind, b, t, iter, body) => {
      let inner = ScopeFrame::child(scope)
      let new_binding = rename_for_binding(kind, b, inner, reserved)
      let new_iter = rename_expr(iter, scope)
      let new_body = rename_block_inline_in(body, inner, reserved)
      ForOf(kind, new_binding, t, new_iter, new_body)
    }
    ForAwaitOf(kind, b, t, iter, body) => {
      let inner = ScopeFrame::child(scope)
      let new_binding = rename_for_binding(kind, b, inner, reserved)
      let new_iter = rename_expr(iter, scope)
      let new_body = rename_block_inline_in(body, inner, reserved)
      ForAwaitOf(kind, new_binding, t, new_iter, new_body)
    }
    ForIn(kind, b, t, iter, body) => {
      let inner = ScopeFrame::child(scope)
      let new_binding = rename_for_binding(kind, b, inner, reserved)
      let new_iter = rename_expr(iter, scope)
      let new_body = rename_block_inline_in(body, inner, reserved)
      ForIn(kind, new_binding, t, new_iter, new_body)
    }
    Switch(scrutinee, cases) => {
      let new_scrutinee = rename_expr(scrutinee, scope)
      let new_cases : Array[@ast.TsSwitchCase] = []
      // All case bodies share the same lexical scope when the
      // `case` labels aren't individually wrapped in `{…}` braces.
      // TypeScript's own compiler source has `case A: const x = …;
      // case B: const y = …;` patterns — each `const` is a fresh
      // source name but shares the switch's scope. Use ONE shared
      // child frame for the cases so the renames don't collide.
      let inner = ScopeFrame::child(scope)
      for c in cases {
        let new_test = match c.test_expr {
          Some(t) => Some(rename_expr(t, scope))
          None => None
        }
        new_cases.push({
          test_expr: new_test,
          body: rename_block_inline_in(c.body, inner, reserved),
        })
      }
      Switch(new_scrutinee, new_cases)
    }
    Try(try_b, catch_bind, catch_b, finally_b) => {
      let try_scope = ScopeFrame::child(scope)
      let new_try = rename_block_inline_in(try_b, try_scope, reserved)
      let (new_bind, new_catch) = match (catch_bind, catch_b) {
        (Some(b), Some(cb)) => {
          let inner = ScopeFrame::child(scope)
          let renamed_bind = rename_binding_decl(b, inner, reserved)
          (
            Some(renamed_bind),
            Some(rename_block_inline_in(cb, inner, reserved)),
          )
        }
        (None, Some(cb)) => {
          let inner = ScopeFrame::child(scope)
          (None, Some(rename_block_inline_in(cb, inner, reserved)))
        }
        _ => (None, None)
      }
      let new_finally = match finally_b {
        Some(fb) => {
          let finally_scope = ScopeFrame::child(scope)
          Some(rename_block_inline_in(fb, finally_scope, reserved))
        }
        None => None
      }
      Try(new_try, new_bind, new_catch, new_finally)
    }
    Block(b) =>
      // Parser packs multi-declarator `let a = 1, b = 2;` into a
      // synthetic `Block([Let(a, …), Let(b, …)])` — the binders
      // share the surrounding scope, not a new block scope. When
      // every stmt is the same lexical decl kind, treat the block
      // as transparent (rename in the outer scope) so subsequent
      // `let` / `const` in the same scope can't collide with the
      // multi-decl names. Without this, the inner scope drops the
      // `i` / `g` renames at block exit and the next `const out`
      // re-uses `i`'s slot — invalid duplicate declaration.
      if is_synthetic_multi_decl_block(b) {
        Block(rename_block_inline_in(b, scope, reserved))
      } else {
        let inner = ScopeFrame::child(scope)
        Block(rename_block_inline_in(b, inner, reserved))
      }
    Label(name, inner) => Label(name, rename_stmt(inner, scope, reserved))
    With(target, body) => {
      // `with` extends the scope chain dynamically; the static rename
      // still needs lexical `let` / `const` bindings to live in their
      // own frame so cross-block reuse is allowed.
      let inner = ScopeFrame::child(scope)
      With(
        rename_expr(target, scope),
        rename_block_inline_in(body, inner, reserved),
      )
    }
    Break(_) | Continue(_) | Empty | Debugger => stmt
    NativeClassStmt(decl, ctor_body) =>
      NativeClassStmt(
        rename_class_decl_idents(decl, scope),
        match ctor_body {
          Some(f) => Some(rename_function_expr(f, scope))
          None => None
        },
      )
  }
}

///|
/// Rename `block` using the given scope without spawning a new
/// frame. Callers that need a fresh block-scope frame should
/// allocate it via `ScopeFrame::child(scope)` and pass that to
/// `rename_block_inline_in` directly — this helper is kept for the
/// rare callers where the caller already represents the scope they
/// want the body to inhabit (e.g. the function-body root frame).
fn is_synthetic_multi_decl_block(b : @ast.TsBlock) -> Bool {
  if b.stmts.length() < 2 {
    return false
  }
  let kind = match b.stmts[0] {
    Let(_, _, _) => "let"
    Const(_, _, _) => "const"
    Var(_, _, _) => "var"
    _ => return false
  }
  for s in b.stmts {
    match s {
      Let(_, _, _) => if kind != "let" { return false }
      Const(_, _, _) => if kind != "const" { return false }
      Var(_, _, _) => if kind != "var" { return false }
      _ => return false
    }
  }
  true
}

///|
fn rename_block_inline(
  block : @ast.TsBlock,
  scope : ScopeFrame,
  reserved : Map[String, Bool],
) -> @ast.TsBlock {
  rename_block_inline_in(block, scope, reserved)
}

///|
fn rename_block_inline_in(
  block : @ast.TsBlock,
  scope : ScopeFrame,
  reserved : Map[String, Bool],
) -> @ast.TsBlock {
  // Hoist function declarations: in JS, `function f() {}` is
  // visible from the start of its containing scope, so an earlier
  // `return f();` should resolve to the SAME rename as the later
  // declaration. Pre-bind every `<kind>(Ident(name), _, FuncExpr)`
  // before the recursive walk so the call site and the declaration
  // both pick up the same short name.
  //
  // Also pre-bind every other top-level `Let` / `Const` / `Var` /
  // `NativeClassStmt`. Closures inside an earlier-evaluated object
  // literal can reference a later declaration — TypeScript's
  // `transpileWorker` builds `compilerHost = { getSourceFile: …
  // inputFileName … }` before declaring `const inputFileName = …`.
  // The closure call only runs after the function returns, so the
  // forward ref is fine at runtime; the rename must agree at
  // both sites.
  // `var` decls are NOT pre-bound here — they hoist to the enclosing
  // function frame via `hoist_var_decls_into_scope`. Adding a fresh
  // bind here at the block level would shadow that function-frame
  // binding and split the var name into two renames (e.g. the var
  // body becomes `var a = 1` but post-block `return counter` looks
  // up the function-frame name `b` instead).
  fn prebind_stmts(stmts : Array[@ast.TsStmt]) -> Unit {
    for s in stmts {
      match s {
        Let(@ast.TsBinding::Ident(name), _, _)
        | Const(@ast.TsBinding::Ident(name), _, _) =>
          if not(scope.renames.contains(name)) {
            let _ = scope.bind(name, reserved)
          }
        NativeClassStmt(decl, _) =>
          if decl.name != "" && not(scope.renames.contains(decl.name)) {
            let _ = scope.bind(decl.name, reserved)
          }
        // Synthetic multi-decl blocks (e.g. `let a = 1, b = 2`) are wrapped
        // in a Block whose stmts are all the same lexical-decl kind. Recurse
        // so the enclosed names are pre-bound in the outer scope before the
        // body walk begins — otherwise a closure defined earlier in the block
        // captures the unshortened name while the declaration gets a short
        // name, producing a ReferenceError at runtime.
        Block(b) =>
          if is_synthetic_multi_decl_block(b) {
            prebind_stmts(b.stmts)
          }
        _ => ()
      }
    }
  }
  prebind_stmts(block.stmts)
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(rename_stmt(s, scope, reserved))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
/// Pick the right binding strategy for a `for-of` / `for-in` /
/// `for-await-of` header. `Let` / `Const` introduce a fresh block-
/// scoped binding; `Var` was already hoisted to the enclosing function
/// frame so its name must resolve through the scope chain; `Assign`
/// refers to an existing variable and behaves the same way.
fn rename_for_binding(
  kind : @ast.TsForOfKind,
  binding : @ast.TsBinding,
  inner : ScopeFrame,
  reserved : Map[String, Bool],
) -> @ast.TsBinding {
  match kind {
    Let | Const => rename_binding_decl(binding, inner, reserved)
    Var | Assign => rename_binding_lhs(binding, inner)
  }
}

///|
fn rename_binding_decl(
  binding : @ast.TsBinding,
  scope : ScopeFrame,
  reserved : Map[String, Bool],
) -> @ast.TsBinding {
  match binding {
    Ident(n) => Ident(scope.bind(n, reserved))
    Array(ab) => {
      let new_items : Array[@ast.TsBindingElem?] = []
      for elem in ab.items {
        match elem {
          Some(be) => {
            let new_inner = rename_binding_decl(be.binding, scope, reserved)
            let new_default : @ast.TsExpr? = match be.default {
              Some(d) => Some(rename_expr(d, scope))
              None => None
            }
            new_items.push(Some({ binding: new_inner, default: new_default }))
          }
          None => new_items.push(None)
        }
      }
      let new_rest : @ast.TsBinding? = match ab.rest {
        Some(r) => Some(rename_binding_decl(r, scope, reserved))
        None => None
      }
      Array({ items: new_items, rest: new_rest })
    }
    Object(ob) => {
      let new_props : Array[@ast.TsObjectBindingProp] = []
      for p in ob.props {
        let new_inner = rename_binding_decl(p.binding, scope, reserved)
        let new_default : @ast.TsExpr? = match p.default {
          Some(d) => Some(rename_expr(d, scope))
          None => None
        }
        new_props.push({
          key: p.key,
          key_expr: p.key_expr,
          binding: new_inner,
          default: new_default,
        })
      }
      let new_rest : String? = match ob.rest {
        Some(n) => Some(scope.bind(n, reserved))
        None => None
      }
      Object({ props: new_props, rest: new_rest })
    }
    Target(e) => Target(rename_expr(e, scope))
  }
}

// ---------------------------------------------------------------------------
// Expression walker
// ---------------------------------------------------------------------------

///|
fn rename_expr(expr : @ast.TsExpr, scope : ScopeFrame) -> @ast.TsExpr {
  match expr {
    Var(name) => Var(scope.resolve(name))
    Call(name, args) => {
      // `Call(name, …)` is a free-function call site; the name is a
      // variable reference, so it follows the scope chain.
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr(a, scope))
      }
      Call(scope.resolve(name), new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr(a, scope))
      }
      CallExpr(rename_expr(callee, scope), new_args)
    }
    New(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr(a, scope))
      }
      New(scope.resolve(name), new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr(a, scope))
      }
      NewExpr(rename_expr(callee, scope), new_args)
    }
    MethodCall(recv, method, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_expr(a, scope))
      }
      // Property name is left untouched — property mangling is a
      // separate pass that needs type info to be safe.
      MethodCall(rename_expr(recv, scope), method, new_args)
    }
    PropAccess(recv, name) => PropAccess(rename_expr(recv, scope), name)
    IndexAccess(recv, idx) =>
      IndexAccess(rename_expr(recv, scope), rename_expr(idx, scope))
    BinOp(op, l, r) => BinOp(op, rename_expr(l, scope), rename_expr(r, scope))
    UnaryOp(op, inner) => UnaryOp(op, rename_expr(inner, scope))
    Cond(c, t, e) =>
      Cond(rename_expr(c, scope), rename_expr(t, scope), rename_expr(e, scope))
    ArrayLit(items) => {
      let out : Array[@ast.TsExpr] = []
      for i in items {
        out.push(rename_expr(i, scope))
      }
      ArrayLit(out)
    }
    Spread(inner) => Spread(rename_expr(inner, scope))
    ObjectLit(entries) => {
      let out : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        out.push((ent.0, rename_expr(ent.1, scope)))
      }
      ObjectLit(out)
    }
    ComputedProp(k, v) =>
      ComputedProp(rename_expr(k, scope), rename_expr(v, scope))
    AssignExpr(name, value) =>
      AssignExpr(scope.resolve(name), rename_expr(value, scope))
    AssignPattern(b, value) =>
      // Destructuring assignment to an existing pattern; the LHS is
      // an *assignment* not a declaration, so the names resolve via
      // the scope chain rather than introducing new bindings.
      AssignPattern(rename_binding_lhs(b, scope), rename_expr(value, scope))
    CompoundAssignExpr(target, op, value) =>
      CompoundAssignExpr(
        rename_expr(target, scope),
        op,
        rename_expr(value, scope),
      )
    PropAssignExpr(recv, prop, value) =>
      PropAssignExpr(rename_expr(recv, scope), prop, rename_expr(value, scope))
    IndexAssignExpr(recv, idx, value) =>
      IndexAssignExpr(
        rename_expr(recv, scope),
        rename_expr(idx, scope),
        rename_expr(value, scope),
      )
    Seq(a, b) => Seq(rename_expr(a, scope), rename_expr(b, scope))
    ArrowFunc(params, ret_ty, body, is_async) => {
      // New function scope — params get short names starting from 0.
      let inner = match body {
        ArrowBlock(b) => ScopeFrame::function_child(scope, b)
        ArrowExpr(_) => {
          // Expression body: synthesize a block with a single Return
          // so we can reuse function_child's free-var collection.
          let refs : Map[String, Bool] = {}
          match body {
            ArrowExpr(e) => collect_var_refs_expr(e, refs)
            _ => ()
          }
          let used : Map[String, Bool] = {}
          for name, _ in refs {
            let short = scope.resolve(name)
            if short != name {
              used[short] = true
            }
          }
          {
            parent: Some(scope),
            renames: {},
            used,
            counter: 0,
            reserved: scope.reserved,
            is_function_scope: true,
          }
        }
      }
      let new_params = rename_param_list(params, inner, inner.reserved)
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(rename_expr(e, inner))
        ArrowBlock(b) => {
          hoist_var_decls_into_scope(b, inner, inner.reserved)
          @ast.TsArrowBody::ArrowBlock(
            rename_block_inline_in(b, inner, inner.reserved),
          )
        }
      }
      ArrowFunc(new_params, ret_ty, new_body, is_async)
    }
    FuncExpr(f) => FuncExpr(rename_function_expr(f, scope))
    Yield(opt) =>
      match opt {
        Some(e) => Yield(Some(rename_expr(e, scope)))
        None => Yield(None)
      }
    YieldStar(inner) => YieldStar(rename_expr(inner, scope))
    Await(inner) => Await(rename_expr(inner, scope))
    DynamicImport(spec, opts) =>
      DynamicImport(
        rename_expr(spec, scope),
        match opts {
          Some(o) => Some(rename_expr(o, scope))
          None => None
        },
      )
    TaggedTemplate(tag, parts, raw, exprs) => {
      let out : Array[@ast.TsExpr] = []
      for e in exprs {
        out.push(rename_expr(e, scope))
      }
      TaggedTemplate(rename_expr(tag, scope), parts, raw, out)
    }
    TemplateLiteral(parts, exprs) => {
      let out : Array[@ast.TsExpr] = []
      for e in exprs {
        out.push(rename_expr(e, scope))
      }
      TemplateLiteral(parts, out)
    }
    As(inner, ty) => As(rename_expr(inner, scope), ty)
    Satisfies(inner, ty) => Satisfies(rename_expr(inner, scope), ty)
    NonNull(inner) => NonNull(rename_expr(inner, scope))
    OptionalChain(inner) => OptionalChain(rename_expr(inner, scope))
    PureCall(inner) => PureCall(rename_expr(inner, scope))
    JsxElement(_, _, _) => expr // JSX should be lowered before mangling
    NativeClassExpr(decl, ctor_body) =>
      NativeClassExpr(
        rename_class_decl_idents(decl, scope),
        match ctor_body {
          Some(f) => Some(rename_function_expr(f, scope))
          None => None
        },
      )
    _ => expr
  }
}

///|
/// Same as `rename_binding_decl` but treats `Ident(n)` as an
/// assignment-LHS reference instead of a declaration — the name
/// resolves through `scope.resolve` rather than introducing a new
/// binding. Used by `AssignPattern(b, value)`.
fn rename_binding_lhs(
  binding : @ast.TsBinding,
  scope : ScopeFrame,
) -> @ast.TsBinding {
  match binding {
    Ident(n) => Ident(scope.resolve(n))
    Array(ab) => {
      let new_items : Array[@ast.TsBindingElem?] = []
      for elem in ab.items {
        match elem {
          Some(be) => {
            let new_inner = rename_binding_lhs(be.binding, scope)
            let new_default : @ast.TsExpr? = match be.default {
              Some(d) => Some(rename_expr(d, scope))
              None => None
            }
            new_items.push(Some({ binding: new_inner, default: new_default }))
          }
          None => new_items.push(None)
        }
      }
      let new_rest : @ast.TsBinding? = match ab.rest {
        Some(r) => Some(rename_binding_lhs(r, scope))
        None => None
      }
      Array({ items: new_items, rest: new_rest })
    }
    Object(ob) => {
      let new_props : Array[@ast.TsObjectBindingProp] = []
      for p in ob.props {
        let new_inner = rename_binding_lhs(p.binding, scope)
        let new_default : @ast.TsExpr? = match p.default {
          Some(d) => Some(rename_expr(d, scope))
          None => None
        }
        new_props.push({
          key: p.key,
          key_expr: p.key_expr,
          binding: new_inner,
          default: new_default,
        })
      }
      let new_rest : String? = match ob.rest {
        Some(n) => Some(scope.resolve(n))
        None => None
      }
      Object({ props: new_props, rest: new_rest })
    }
    Target(e) => Target(rename_expr(e, scope))
  }
}

///|
/// Identifier-mangle a class declaration: rename `base_names`
/// through the scope chain, walk each method's body, and walk
/// decorators. Property names are not touched here — that's the
/// job of `rename_properties_in_class_decl`.
fn rename_dotted_base_name(name : String, scope : ScopeFrame) -> String {
  match name.find(".") {
    Some(i) => scope.resolve(name.substring(end=i)) + name.substring(start=i)
    None => scope.resolve(name)
  }
}

///|
fn is_define_prop_call(recv : @ast.TsExpr, method : String) -> Bool {
  match recv {
    @ast.TsExpr::Var("Object") =>
      method == "defineProperty" || method == "defineProperties"
    @ast.TsExpr::Var("Reflect") => method == "defineProperty"
    _ => false
  }
}

///|
fn rename_class_decl_idents(
  decl : @ast.TsClassDecl,
  scope : ScopeFrame,
) -> @ast.TsClassDecl {
  // The class declaration's own name participates in the scope's
  // value namespace just like a `let` / `function` binding. Resolve
  // through the chain — the top-level pre-bind pass already
  // allocated a rename for it, so this picks up that decision.
  let new_name = if decl.name != "" {
    scope.resolve(decl.name)
  } else {
    decl.name
  }
  let new_base_names : Array[String] = []
  for b in decl.base_names {
    // `extends ns.default` is stored as the dotted string
    // `"ns.default"` in `base_names`; `scope.resolve` doesn't know
    // to split on `.` — it would look up `"ns.default"` as a whole
    // name, miss the rename for `ns`, and emit
    // `class X extends reader_1.default {}` against a renamed
    // `var Cv = require_reader()` binding. Resolve only the leading
    // segment.
    new_base_names.push(rename_dotted_base_name(b, scope))
  }
  let new_methods : Array[@ast.TsClassMethodDecl] = []
  for m in decl.methods {
    let (new_body, new_params, new_defaults) = match m.body {
      Some(b) => {
        // Use a fresh function scope so params/locals get short 1-char names.
        let inner = ScopeFrame::function_child(scope, b)
        // Rename each param and record the mapping in the inner scope.
        let renamed_params : Array[(String, @ast.TsType)] = []
        let renamed_defaults : Array[@ast.TsExpr?] = []
        for i, p in m.params {
          let new_name = if p.0 == "" {
            ""
          } else {
            inner.bind(p.0, inner.reserved)
          }
          renamed_params.push((new_name, p.1))
          if i < m.param_defaults.length() {
            let d = m.param_defaults[i]
            let new_d = match d {
              Some(expr) => Some(rename_expr(expr, inner))
              None => None
            }
            renamed_defaults.push(new_d)
          }
        }
        hoist_var_decls_into_scope(b, inner, inner.reserved)
        let new_b = rename_block_inline_in(b, inner, inner.reserved)
        (Some(new_b), renamed_params, renamed_defaults)
      }
      None => (None, m.params, m.param_defaults)
    }
    let new_key_expr = match m.key_expr {
      Some(e) => Some(rename_expr(e, scope))
      None => None
    }
    new_methods.push({
      ..m,
      body: new_body,
      params: new_params,
      param_defaults: new_defaults,
      key_expr: new_key_expr,
    })
  }
  let new_decorators : Array[@ast.TsExpr] = []
  for d in decl.decorators {
    new_decorators.push(rename_expr(d, scope))
  }
  let new_base_expr = match decl.base_expr {
    Some(e) => Some(rename_expr(e, scope))
    None => None
  }
  let new_static_inits : Array[(String, @ast.TsExpr)] = []
  for entry in decl.static_field_inits {
    new_static_inits.push((entry.0, rename_expr(entry.1, scope)))
  }
  {
    ..decl,
    name: new_name,
    base_names: new_base_names,
    base_expr: new_base_expr,
    static_field_inits: new_static_inits,
    methods: new_methods,
    decorators: new_decorators,
  }
}

///|
fn rename_function_expr(f : @ast.TsFunc, scope : ScopeFrame) -> @ast.TsFunc {
  // `function name(…)` as a function EXPRESSION (e.g.
  // `module.exports = function isExtglob(s) {…}`) binds `name`
  // only inside the body — outside callers see the value via the
  // enclosing assignment / binding. If the body never references
  // its own name, drop it so emit prints `function(s) {…}` and
  // the long source-derived name stops surviving into the
  // minified bundle. `try_emit_function_decl` (the
  // `Let(Ident, _, FuncExpr)` → real `function X() {}` shape)
  // bypasses the FuncExpr name entirely, so this rewrite is safe
  // there too.
  let new_name = if f.name == "" || block_references_name(f.body, f.name) {
    f.name
  } else {
    ""
  }
  let inner = ScopeFrame::function_child(scope, f.body)
  let new_params = rename_param_list(f.params, inner, inner.reserved)
  // Hoist `var` names from the body into the function frame so
  // block-scoped child frames can resolve them through the chain.
  hoist_var_decls_into_scope(f.body, inner, inner.reserved)
  let new_body = rename_block_inline_in(f.body, inner, inner.reserved)
  {
    name: new_name,
    type_params: f.type_params,
    const_type_params: f.const_type_params,
    params: new_params,
    return_type: f.return_type,
    body: new_body,
    is_generator: f.is_generator,
    is_async: f.is_async,
  }
}

///|
fn rename_param_list(
  params : Array[@ast.TsParam],
  scope : ScopeFrame,
  reserved : Map[String, Bool],
) -> Array[@ast.TsParam] {
  let out : Array[@ast.TsParam] = []
  for p in params {
    let new_binding : @ast.TsBinding? = match p.binding {
      Some(b) => Some(rename_binding_decl(b, scope, reserved))
      None => None
    }
    let new_name = match new_binding {
      Some(@ast.TsBinding::Ident(n)) => n
      _ => if p.name == "" { "" } else { scope.bind(p.name, reserved) }
    }
    let new_default : @ast.TsExpr? = match p.default {
      Some(d) => Some(rename_expr(d, scope))
      None => None
    }
    out.push({
      name: new_name,
      binding: new_binding,
      is_rest: p.is_rest,
      type_: p.type_,
      default: new_default,
    })
  }
  out
}

// ---------------------------------------------------------------------------
// Property-name rewriting (opt-in)
// ---------------------------------------------------------------------------

///|
/// Apply `prop_map` (`original → mangled`) to every property-name
/// site reachable from `block`. Sites that the property-rename pass
/// covers:
///
///   - `PropAccess(recv, name)`            — receiver.member
///   - `MethodCall(recv, method, args)`    — receiver.method(...)
///   - `PropAssign(recv, prop, value)`     — receiver.prop = value
///   - `PropAssignExpr(...)`               — same in expr position
///   - `ObjectLit([(key, value), ...])`    — { key: value }
///   - `Object({ props: [{ key, ... }] })` destructure — { key } = ...
///
/// `IndexAccess(recv, StringLit("name"))` could be safely rewritten
/// too — it's an alternate spelling of the same access — but we
/// leave it for a follow-up, since callers who *want* string-index
/// access typically intend it to bypass mangling.
fn rename_properties_in_block(
  block : @ast.TsBlock,
  prop_map : Map[String, String],
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(rename_properties_in_stmt(s, prop_map))
  }
  { stmts, stmt_positions: block.stmt_positions }
}

///|
fn rename_properties_in_stmt(
  stmt : @ast.TsStmt,
  prop_map : Map[String, String],
) -> @ast.TsStmt {
  match stmt {
    Var(b, t, init) =>
      Var(
        rename_properties_in_binding(b, prop_map),
        t,
        rename_properties_in_expr(init, prop_map),
      )
    Let(b, t, init) =>
      Let(
        rename_properties_in_binding(b, prop_map),
        t,
        rename_properties_in_expr(init, prop_map),
      )
    Const(b, t, init) =>
      Const(
        rename_properties_in_binding(b, prop_map),
        t,
        rename_properties_in_expr(init, prop_map),
      )
    Expr(e) => Expr(rename_properties_in_expr(e, prop_map))
    Return(opt) =>
      match opt {
        Some(e) => Return(Some(rename_properties_in_expr(e, prop_map)))
        None => Return(None)
      }
    Throw(e) => Throw(rename_properties_in_expr(e, prop_map))
    Assign(name, e) => Assign(name, rename_properties_in_expr(e, prop_map))
    CompoundAssign(name, op, e) =>
      CompoundAssign(name, op, rename_properties_in_expr(e, prop_map))
    PropAssign(recv, prop, value) =>
      PropAssign(
        rename_properties_in_expr(recv, prop_map),
        rename_prop_key(prop, prop_map),
        rename_properties_in_expr(value, prop_map),
      )
    IndexAssign(recv, idx, value) =>
      IndexAssign(
        rename_properties_in_expr(recv, prop_map),
        rename_properties_in_expr(idx, prop_map),
        rename_properties_in_expr(value, prop_map),
      )
    If(c, t, e_opt) =>
      If(
        rename_properties_in_expr(c, prop_map),
        rename_properties_in_block(t, prop_map),
        match e_opt {
          Some(b) => Some(rename_properties_in_block(b, prop_map))
          None => None
        },
      )
    While(c, b) =>
      While(
        rename_properties_in_expr(c, prop_map),
        rename_properties_in_block(b, prop_map),
      )
    DoWhile(c, b) =>
      DoWhile(
        rename_properties_in_expr(c, prop_map),
        rename_properties_in_block(b, prop_map),
      )
    For(init_opt, cond_opt, update_opt, body) =>
      For(
        match init_opt {
          Some(s) => Some(rename_properties_in_stmt(s, prop_map))
          None => None
        },
        match cond_opt {
          Some(c) => Some(rename_properties_in_expr(c, prop_map))
          None => None
        },
        match update_opt {
          Some(s) => Some(rename_properties_in_stmt(s, prop_map))
          None => None
        },
        rename_properties_in_block(body, prop_map),
      )
    ForOf(kind, b, t, iter, body) =>
      ForOf(
        kind,
        rename_properties_in_binding(b, prop_map),
        t,
        rename_properties_in_expr(iter, prop_map),
        rename_properties_in_block(body, prop_map),
      )
    ForAwaitOf(kind, b, t, iter, body) =>
      ForAwaitOf(
        kind,
        rename_properties_in_binding(b, prop_map),
        t,
        rename_properties_in_expr(iter, prop_map),
        rename_properties_in_block(body, prop_map),
      )
    ForIn(kind, b, t, iter, body) =>
      ForIn(
        kind,
        rename_properties_in_binding(b, prop_map),
        t,
        rename_properties_in_expr(iter, prop_map),
        rename_properties_in_block(body, prop_map),
      )
    Switch(scrutinee, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        new_cases.push({
          test_expr: match c.test_expr {
            Some(t) => Some(rename_properties_in_expr(t, prop_map))
            None => None
          },
          body: rename_properties_in_block(c.body, prop_map),
        })
      }
      Switch(rename_properties_in_expr(scrutinee, prop_map), new_cases)
    }
    Try(t, cb, c, f) =>
      Try(
        rename_properties_in_block(t, prop_map),
        cb,
        match c {
          Some(b) => Some(rename_properties_in_block(b, prop_map))
          None => None
        },
        match f {
          Some(b) => Some(rename_properties_in_block(b, prop_map))
          None => None
        },
      )
    Block(b) => Block(rename_properties_in_block(b, prop_map))
    Label(name, inner) =>
      Label(name, rename_properties_in_stmt(inner, prop_map))
    With(target, body) =>
      With(
        rename_properties_in_expr(target, prop_map),
        rename_properties_in_block(body, prop_map),
      )
    Break(_) | Continue(_) | Empty | Debugger => stmt
    NativeClassStmt(decl, ctor_body) =>
      NativeClassStmt(
        rename_properties_in_class_decl(decl, prop_map),
        match ctor_body {
          Some(f) =>
            Some({ ..f, body: rename_properties_in_block(f.body, prop_map) })
          None => None
        },
      )
  }
}

///|
/// Property-mangle a class declaration: rename method names + walk
/// method bodies, rename property declaration names, and walk the
/// constructor body (called separately for the IIFE-class shape).
fn rename_properties_in_class_decl(
  decl : @ast.TsClassDecl,
  prop_map : Map[String, String],
) -> @ast.TsClassDecl {
  let new_methods : Array[@ast.TsClassMethodDecl] = []
  for m in decl.methods {
    let renamed_name = match prop_map.get(m.name) {
      Some(short) => short
      None => m.name
    }
    let new_body = match m.body {
      Some(b) => Some(rename_properties_in_block(b, prop_map))
      None => None
    }
    new_methods.push({ ..m, name: renamed_name, body: new_body })
  }
  let new_props : Array[@ast.TsClassPropertyDecl] = []
  for p in decl.properties {
    let renamed_name = match prop_map.get(p.name) {
      Some(short) => short
      None => p.name
    }
    new_props.push({ ..p, name: renamed_name })
  }
  { ..decl, methods: new_methods, properties: new_props }
}

///|
fn rename_properties_in_expr(
  expr : @ast.TsExpr,
  prop_map : Map[String, String],
) -> @ast.TsExpr {
  match expr {
    PropAccess(recv, name) =>
      PropAccess(
        rename_properties_in_expr(recv, prop_map),
        rename_prop_key(name, prop_map),
      )
    MethodCall(recv, method, args) => {
      let new_args : Array[@ast.TsExpr] = []
      // `Object.defineProperty(obj, "key", desc)` / `Reflect.defineProperty(obj, "key", desc)`:
      // the second argument names a property that the runtime
      // writes onto `obj`. The mangler renames every `obj.key`
      // / `obj["key"]` access, so the string literal here MUST
      // be renamed in lockstep — otherwise the property is
      // stored under its original name but read under the mangled
      // one, surfacing as `Cannot read properties of undefined`
      // in `_zod`-style instance brands.
      let renames_define_prop_key = is_define_prop_call(recv, method) &&
        args.length() >= 2
      for i, a in args {
        if i == 1 && renames_define_prop_key {
          match a {
            @ast.TsExpr::StringLit(s) =>
              new_args.push(
                @ast.TsExpr::StringLit(rename_prop_key(s, prop_map)),
              )
            _ => new_args.push(rename_properties_in_expr(a, prop_map))
          }
        } else {
          new_args.push(rename_properties_in_expr(a, prop_map))
        }
      }
      MethodCall(
        rename_properties_in_expr(recv, prop_map),
        rename_prop_key(method, prop_map),
        new_args,
      )
    }
    PropAssignExpr(recv, prop, value) =>
      PropAssignExpr(
        rename_properties_in_expr(recv, prop_map),
        rename_prop_key(prop, prop_map),
        rename_properties_in_expr(value, prop_map),
      )
    ObjectLit(entries) => {
      let out : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        let new_key = if ent.0 == "..." {
          ent.0
        } else {
          rename_prop_key(ent.0, prop_map)
        }
        out.push((new_key, rename_properties_in_expr(ent.1, prop_map)))
      }
      ObjectLit(out)
    }
    Call(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_properties_in_expr(a, prop_map))
      }
      Call(name, new_args)
    }
    CallExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_properties_in_expr(a, prop_map))
      }
      CallExpr(rename_properties_in_expr(callee, prop_map), new_args)
    }
    New(name, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_properties_in_expr(a, prop_map))
      }
      New(name, new_args)
    }
    NewExpr(callee, args) => {
      let new_args : Array[@ast.TsExpr] = []
      for a in args {
        new_args.push(rename_properties_in_expr(a, prop_map))
      }
      NewExpr(rename_properties_in_expr(callee, prop_map), new_args)
    }
    IndexAccess(recv, idx) =>
      IndexAccess(
        rename_properties_in_expr(recv, prop_map),
        rename_properties_in_expr(idx, prop_map),
      )
    IndexAssignExpr(recv, idx, value) =>
      IndexAssignExpr(
        rename_properties_in_expr(recv, prop_map),
        rename_properties_in_expr(idx, prop_map),
        rename_properties_in_expr(value, prop_map),
      )
    BinOp(op, l, r) =>
      BinOp(
        op,
        rename_properties_in_expr(l, prop_map),
        rename_properties_in_expr(r, prop_map),
      )
    UnaryOp(op, inner) =>
      UnaryOp(op, rename_properties_in_expr(inner, prop_map))
    Cond(c, t, e) =>
      Cond(
        rename_properties_in_expr(c, prop_map),
        rename_properties_in_expr(t, prop_map),
        rename_properties_in_expr(e, prop_map),
      )
    ArrayLit(items) => {
      let out : Array[@ast.TsExpr] = []
      for i in items {
        out.push(rename_properties_in_expr(i, prop_map))
      }
      ArrayLit(out)
    }
    Spread(inner) => Spread(rename_properties_in_expr(inner, prop_map))
    ComputedProp(k, v) =>
      ComputedProp(
        rename_properties_in_expr(k, prop_map),
        rename_properties_in_expr(v, prop_map),
      )
    AssignExpr(name, value) =>
      AssignExpr(name, rename_properties_in_expr(value, prop_map))
    AssignPattern(b, value) =>
      AssignPattern(
        rename_properties_in_binding(b, prop_map),
        rename_properties_in_expr(value, prop_map),
      )
    CompoundAssignExpr(target, op, value) =>
      CompoundAssignExpr(
        rename_properties_in_expr(target, prop_map),
        op,
        rename_properties_in_expr(value, prop_map),
      )
    Seq(a, b) =>
      Seq(
        rename_properties_in_expr(a, prop_map),
        rename_properties_in_expr(b, prop_map),
      )
    ArrowFunc(params, ret, body, is_async) => {
      let new_params : Array[@ast.TsParam] = []
      for p in params {
        let new_binding : @ast.TsBinding? = match p.binding {
          Some(b) => Some(rename_properties_in_binding(b, prop_map))
          None => None
        }
        let new_default : @ast.TsExpr? = match p.default {
          Some(d) => Some(rename_properties_in_expr(d, prop_map))
          None => None
        }
        new_params.push({
          name: p.name,
          binding: new_binding,
          is_rest: p.is_rest,
          type_: p.type_,
          default: new_default,
        })
      }
      let new_body = match body {
        ArrowExpr(e) =>
          @ast.TsArrowBody::ArrowExpr(rename_properties_in_expr(e, prop_map))
        ArrowBlock(b) =>
          @ast.TsArrowBody::ArrowBlock(rename_properties_in_block(b, prop_map))
      }
      ArrowFunc(new_params, ret, new_body, is_async)
    }
    FuncExpr(f) => {
      let new_params : Array[@ast.TsParam] = []
      for p in f.params {
        let new_binding : @ast.TsBinding? = match p.binding {
          Some(b) => Some(rename_properties_in_binding(b, prop_map))
          None => None
        }
        let new_default : @ast.TsExpr? = match p.default {
          Some(d) => Some(rename_properties_in_expr(d, prop_map))
          None => None
        }
        new_params.push({
          name: p.name,
          binding: new_binding,
          is_rest: p.is_rest,
          type_: p.type_,
          default: new_default,
        })
      }
      FuncExpr({
        name: f.name,
        type_params: f.type_params,
        const_type_params: f.const_type_params,
        params: new_params,
        return_type: f.return_type,
        body: rename_properties_in_block(f.body, prop_map),
        is_generator: f.is_generator,
        is_async: f.is_async,
      })
    }
    Yield(opt) =>
      match opt {
        Some(e) => Yield(Some(rename_properties_in_expr(e, prop_map)))
        None => Yield(None)
      }
    YieldStar(inner) => YieldStar(rename_properties_in_expr(inner, prop_map))
    Await(inner) => Await(rename_properties_in_expr(inner, prop_map))
    DynamicImport(spec, opts) =>
      DynamicImport(
        rename_properties_in_expr(spec, prop_map),
        match opts {
          Some(o) => Some(rename_properties_in_expr(o, prop_map))
          None => None
        },
      )
    TaggedTemplate(tag, parts, raw, exprs) => {
      let out : Array[@ast.TsExpr] = []
      for e in exprs {
        out.push(rename_properties_in_expr(e, prop_map))
      }
      TaggedTemplate(rename_properties_in_expr(tag, prop_map), parts, raw, out)
    }
    TemplateLiteral(parts, exprs) => {
      let out : Array[@ast.TsExpr] = []
      for e in exprs {
        out.push(rename_properties_in_expr(e, prop_map))
      }
      TemplateLiteral(parts, out)
    }
    As(inner, ty) => As(rename_properties_in_expr(inner, prop_map), ty)
    Satisfies(inner, ty) =>
      Satisfies(rename_properties_in_expr(inner, prop_map), ty)
    NonNull(inner) => NonNull(rename_properties_in_expr(inner, prop_map))
    OptionalChain(inner) =>
      OptionalChain(rename_properties_in_expr(inner, prop_map))
    NativeClassExpr(decl, ctor_body) =>
      NativeClassExpr(
        rename_properties_in_class_decl(decl, prop_map),
        match ctor_body {
          Some(f) =>
            Some({ ..f, body: rename_properties_in_block(f.body, prop_map) })
          None => None
        },
      )
    PureCall(inner) => PureCall(rename_properties_in_expr(inner, prop_map))
    _ => expr
  }
}

///|
fn rename_properties_in_binding(
  binding : @ast.TsBinding,
  prop_map : Map[String, String],
) -> @ast.TsBinding {
  match binding {
    Ident(_) => binding
    Array(ab) => {
      let new_items : Array[@ast.TsBindingElem?] = []
      for elem in ab.items {
        match elem {
          Some(be) => {
            let new_inner = rename_properties_in_binding(be.binding, prop_map)
            let new_default : @ast.TsExpr? = match be.default {
              Some(d) => Some(rename_properties_in_expr(d, prop_map))
              None => None
            }
            new_items.push(Some({ binding: new_inner, default: new_default }))
          }
          None => new_items.push(None)
        }
      }
      let new_rest : @ast.TsBinding? = match ab.rest {
        Some(r) => Some(rename_properties_in_binding(r, prop_map))
        None => None
      }
      Array({ items: new_items, rest: new_rest })
    }
    Object(ob) => {
      // Object-destructure key: rename the key, but preserve the
      // local binding so the JS stays equivalent. Shorthand `{ key }`
      // (where `prop.binding == Ident(key)`) becomes `{ mangled: key }`.
      let new_props : Array[@ast.TsObjectBindingProp] = []
      for p in ob.props {
        let new_key = rename_prop_key(p.key, prop_map)
        let key_was_renamed = new_key != p.key
        let new_inner = rename_properties_in_binding(p.binding, prop_map)
        let new_default : @ast.TsExpr? = match p.default {
          Some(d) => Some(rename_properties_in_expr(d, prop_map))
          None => None
        }
        // If we renamed the key AND the binding was the implicit
        // shorthand (`{ key }` → `binding == Ident(key)`), emit it
        // explicitly as `{ new_key: key }` so the local binding
        // continues to use the original name.
        new_props.push({
          key: new_key,
          key_expr: p.key_expr,
          binding: if key_was_renamed && p.binding is Ident(b) && b == p.key {
            @ast.TsBinding::Ident(b)
          } else {
            new_inner
          },
          default: new_default,
        })
      }
      Object({ props: new_props, rest: ob.rest })
    }
    Target(e) => Target(rename_properties_in_expr(e, prop_map))
  }
}

///|
fn rename_prop_key(name : String, prop_map : Map[String, String]) -> String {
  match prop_map.get(name) {
    Some(renamed) => renamed
    None => name
  }
}
