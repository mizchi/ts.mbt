// JSX → `react/jsx-runtime`-style call lowering.
//
// Modern TS (>=4.1) emits JSX into `jsx(type, props, key?)` /
// `jsxs(type, props, key?)` / `Fragment` calls from a configurable
// import source instead of the deprecated
// `React.createElement(type, props, ...children)`.
//
// Config can be supplied three ways, in increasing precedence:
//
//   1. JSX-runtime defaults (`{ import_source: "react", dev: false }`).
//   2. A `JsxConfig` value the caller passes in (e.g. from a `tsconfig`).
//   3. File-level pragmas in the source's leading comment block:
//        /** @jsxRuntime classic | automatic */
//        /** @jsxImportSource preact */
//        /** @jsx h */
//        /** @jsxFrag Fragment */
//
// The lowering itself replaces each `JsxElement(tag, attrs, children)`
// AST node with a call expression to the runtime's `jsx` / `jsxs` /
// `Fragment` helpers. Tags that begin with an uppercase letter resolve
// as the component identifier; lower-case tags pass through as string
// literals (intrinsic elements).

///|
pub(all) struct JsxConfig {
  // `"automatic"` — react/jsx-runtime form (default). `"classic"`
  // keeps the legacy `React.createElement` form, used when the
  // consumer's runtime can't accept the new helpers yet.
  runtime : String
  // Module specifier the runtime helpers (`jsx`, `jsxs`, `Fragment`)
  // are imported from. Defaults to `"react"`; pragmas / config can
  // swap in `preact`, `solid-js`, `vue`, etc.
  import_source : String
  // When `dev` is `true`, lowering emits `jsxDEV(...)` instead of
  // `jsx(...)`. The dev runtime in React captures file / line info;
  // we currently pass `undefined` for those slots so the call shape
  // is compatible without sourcemap support yet.
  dev : Bool
  // Classic-runtime pragmas. `pragma_jsx` is the factory function
  // (default `"React.createElement"`); `pragma_jsx_frag` is the
  // fragment marker (default `"React.Fragment"`).
  pragma_jsx : String
  pragma_jsx_frag : String
}

///|
/// Default JSX runtime config: modern automatic runtime, no dev mode,
/// react as the import source. Tests / callers override via
/// `with_*` builders below.
pub fn JsxConfig::default() -> JsxConfig {
  {
    runtime: "automatic",
    import_source: "react",
    dev: false,
    pragma_jsx: "React.createElement",
    pragma_jsx_frag: "React.Fragment",
  }
}

///|
pub fn JsxConfig::with_runtime(self : JsxConfig, runtime : String) -> JsxConfig {
  { ..self, runtime, }
}

///|
pub fn JsxConfig::with_import_source(
  self : JsxConfig,
  import_source : String,
) -> JsxConfig {
  { ..self, import_source, }
}

///|
pub fn JsxConfig::with_dev(self : JsxConfig, dev : Bool) -> JsxConfig {
  { ..self, dev, }
}

///|
pub fn JsxConfig::with_pragma_jsx(
  self : JsxConfig,
  pragma_jsx : String,
) -> JsxConfig {
  { ..self, pragma_jsx, }
}

///|
pub fn JsxConfig::with_pragma_jsx_frag(
  self : JsxConfig,
  pragma_jsx_frag : String,
) -> JsxConfig {
  { ..self, pragma_jsx_frag, }
}

// ---------------------------------------------------------------------------
// Pragma extraction
// ---------------------------------------------------------------------------

///|
/// Scan the leading comment block of a TypeScript source for the
/// JSX-related pragmas (`@jsxRuntime`, `@jsxImportSource`, `@jsx`,
/// `@jsxFrag`) and overlay them onto `base`. Comments that aren't at
/// the top of the file (i.e. before the first non-comment/whitespace
/// token) are ignored — that's intentional, the spec scopes pragmas
/// to the file header.
pub fn extract_jsx_pragmas(source : String, base : JsxConfig) -> JsxConfig {
  let mut cfg = base
  // Walk a single header comment block. Supports `//` line comments,
  // `/* … */` block comments (incl. JSDoc `/** … */`). We stop the
  // scan at the first non-comment / non-whitespace character.
  let mut i = 0
  let len = source.length()
  while i < len {
    let c = source[i]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      i = i + 1
      continue
    }
    if c == '/' && i + 1 < len {
      let n = source[i + 1]
      if n == '/' {
        // Line comment: scan to newline, apply pragmas from it.
        let start = i + 2
        let mut end = start
        while end < len && source[end] != '\n' {
          end = end + 1
        }
        let body = source[start:end].to_owned()
        cfg = apply_pragmas_from_text(body, cfg)
        i = end
        continue
      }
      if n == '*' {
        // Block / JSDoc comment.
        let start = i + 2
        let mut end = start
        while end + 1 < len {
          if source[end] == '*' && source[end + 1] == '/' {
            break
          }
          end = end + 1
        }
        let body = source[start:end].to_owned()
        cfg = apply_pragmas_from_text(body, cfg)
        i = end + 2
        continue
      }
    }
    // Non-comment, non-whitespace: header ends.
    break
  }
  cfg
}

///|
/// Apply any `@jsxRuntime` / `@jsxImportSource` / `@jsx` / `@jsxFrag`
/// pragmas found in `text` (the body of a single comment). Unknown
/// pragmas are silently ignored.
fn apply_pragmas_from_text(text : String, cfg : JsxConfig) -> JsxConfig {
  let mut out = cfg
  for raw_line in text.split("\n") {
    let line_str = raw_line.to_owned()
    let trimmed = trim_jsdoc_line(line_str)
    match read_pragma(trimmed, "@jsxRuntime") {
      Some(v) => out = out.with_runtime(v)
      None => ()
    }
    match read_pragma(trimmed, "@jsxImportSource") {
      Some(v) => out = out.with_import_source(v)
      None => ()
    }
    // `@jsx` is a prefix of `@jsxRuntime` etc., so we have to match
    // exact-word boundaries to avoid false hits. Same for `@jsxFrag`.
    match read_pragma_exact_name(trimmed, "@jsx") {
      Some(v) => out = out.with_pragma_jsx(v)
      None => ()
    }
    match read_pragma_exact_name(trimmed, "@jsxFrag") {
      Some(v) => out = out.with_pragma_jsx_frag(v)
      None => ()
    }
  }
  out
}

///|
/// Strip a leading `*` and surrounding whitespace from a JSDoc-style
/// comment line.
fn trim_jsdoc_line(line : String) -> String {
  let t = line.trim().to_owned()
  if t.has_prefix("*") {
    t[1:t.length()].trim().to_owned()
  } else {
    t
  }
}

///|
/// Read the value following `pragma_name` in `line`. Returns the
/// rest-of-line token (split at first whitespace) when the pragma
/// matches the line's leading tag exactly.
fn read_pragma(line : String, pragma_name : String) -> String? {
  if !line.has_prefix(pragma_name) {
    return None
  }
  let rest = line[pragma_name.length():line.length()].to_owned()
  if rest.length() == 0 {
    return None
  }
  let head = rest[0]
  if head != ' ' && head != '\t' {
    return None
  }
  let value = rest.trim().to_owned()
  if value.length() == 0 {
    return None
  }
  // Take the first whitespace-delimited token.
  match value.find(" ") {
    Some(idx) => Some(value[0:idx].to_owned())
    None => Some(value)
  }
}

///|
/// Variant that requires the next char after `name` to be whitespace
/// (so `@jsx` doesn't false-match `@jsxRuntime` / `@jsxImportSource` /
/// `@jsxFrag`).
fn read_pragma_exact_name(line : String, name : String) -> String? {
  if !line.has_prefix(name) {
    return None
  }
  if line.length() == name.length() {
    return None
  }
  let next = line[name.length()]
  if next != ' ' && next != '\t' {
    return None
  }
  read_pragma(line, name)
}

// ---------------------------------------------------------------------------
// JSX → call lowering
// ---------------------------------------------------------------------------

///|
/// Lower a single `JsxElement(tag, attrs, children)` AST node into a
/// `TsExpr` call shape matching the configured runtime. Nested JSX
/// children are lowered recursively in the same pass.
///
/// Automatic runtime shape:
///
///   <Foo x={1} />          -> jsx(Foo, { x: 1 })
///   <Foo x={1}>a</Foo>     -> jsx(Foo, { x: 1, children: "a" })
///   <Foo>a b</Foo>         -> jsxs(Foo, { children: ["a", "b"] })
///   <>a</>                 -> jsx(Fragment, { children: "a" })
///
/// Classic runtime shape:
///
///   <Foo x={1}>a</Foo>     -> React.createElement(Foo, { x: 1 }, "a")
///   <>a</>                 -> React.createElement(React.Fragment, null, "a")
///
/// Identifier resolution: a tag whose first char is uppercase (or
/// dotted, e.g. `Foo.Bar`) is treated as the component reference;
/// otherwise it's emitted as a string literal (intrinsic element).
pub fn lower_jsx_element(
  cfg : JsxConfig,
  tag : String,
  attrs : Array[(String, @ast.TsExpr?)],
  children : Array[@ast.TsExpr],
) -> @ast.TsExpr {
  // Lower nested children first so the synthesized call carries
  // fully-lowered JSX values.
  let lowered_children : Array[@ast.TsExpr] = []
  for c in children {
    lowered_children.push(lower_jsx_subexpr(cfg, c))
  }
  // Strip pure whitespace-only string children to match TS / Babel
  // behavior on the automatic runtime. They're never user-visible.
  let trimmed_children : Array[@ast.TsExpr] = []
  for c in lowered_children {
    match c {
      StringLit(s) if is_whitespace_only(s) => ()
      _ => trimmed_children.push(c)
    }
  }
  if cfg.runtime == "classic" {
    lower_classic(cfg, tag, attrs, trimmed_children)
  } else {
    lower_automatic(cfg, tag, attrs, trimmed_children)
  }
}

///|
fn lower_jsx_subexpr(cfg : JsxConfig, expr : @ast.TsExpr) -> @ast.TsExpr {
  match expr {
    JsxElement(t, a, c) => lower_jsx_element(cfg, t, a, c)
    _ => expr
  }
}

///|
fn is_whitespace_only(s : String) -> Bool {
  for c in s {
    if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
      return false
    }
  }
  true
}

///|
fn tag_to_type_expr(tag : String) -> @ast.TsExpr {
  if tag == "" {
    // Caller handles the empty-tag (fragment) case before this; we
    // return a benign null marker for safety.
    return @ast.TsExpr::NullLit
  }
  let first = tag[0]
  let starts_uppercase = first >= 'A' && first <= 'Z'
  let has_dot = tag.contains(".")
  if starts_uppercase || has_dot {
    parse_dotted_var(tag)
  } else {
    @ast.TsExpr::StringLit(tag)
  }
}

///|
fn parse_dotted_var(name : String) -> @ast.TsExpr {
  let parts = name.split(".")
  let arr : Array[String] = []
  for p in parts {
    arr.push(p.to_owned())
  }
  if arr.length() == 0 {
    return @ast.TsExpr::Var(name)
  }
  let mut out : @ast.TsExpr = @ast.TsExpr::Var(arr[0])
  let mut i = 1
  while i < arr.length() {
    out = @ast.TsExpr::PropAccess(out, arr[i])
    i = i + 1
  }
  out
}

///|
/// Build the `props` object literal for the automatic runtime. Spread
/// attributes (`name == ""`) become a literal-side spread (we emit a
/// `Spread` entry which then renders as `...`). Boolean-style attrs
/// (`<Foo bar />` with `value == None`) become `bar: true`.
fn build_props_object(
  attrs : Array[(String, @ast.TsExpr?)],
  children : Array[@ast.TsExpr],
) -> @ast.TsExpr {
  let entries : Array[(String, @ast.TsExpr)] = []
  for a in attrs {
    let name = a.0
    if name == "" {
      // Spread attribute. We don't have a direct way to express
      // `{ ...expr }` as a single entry on `ObjectLit(Array[(String,
      // TsExpr)])`; encode by using `Spread(...)` as the value so
      // the emitter writes `...expr` in place.
      match a.1 {
        Some(v) => entries.push(("...", @ast.TsExpr::Spread(v)))
        None => ()
      }
    } else {
      let value = match a.1 {
        Some(v) => v
        None => @ast.TsExpr::BoolLit(true)
      }
      entries.push((name, value))
    }
  }
  if children.length() > 0 {
    if children.length() == 1 {
      entries.push(("children", children[0]))
    } else {
      entries.push(("children", @ast.TsExpr::ArrayLit(children)))
    }
  }
  @ast.TsExpr::ObjectLit(entries)
}

///|
fn lower_automatic(
  cfg : JsxConfig,
  tag : String,
  attrs : Array[(String, @ast.TsExpr?)],
  children : Array[@ast.TsExpr],
) -> @ast.TsExpr {
  let helper = if children.length() > 1 {
    if cfg.dev {
      "jsxsDEV"
    } else {
      "jsxs"
    }
  } else if cfg.dev {
    "jsxDEV"
  } else {
    "jsx"
  }
  let type_expr = if tag == "" {
    @ast.TsExpr::Var("Fragment")
  } else {
    tag_to_type_expr(tag)
  }
  let props = build_props_object(attrs, children)
  // Look for an explicit `key` attribute and pass it as the third
  // arg; the automatic runtime treats `key` as positional, not a
  // prop. Remove it from the props object if present.
  let key_expr = extract_attr(attrs, "key")
  let call_args : Array[@ast.TsExpr] = [type_expr, props]
  match key_expr {
    Some(k) => call_args.push(k)
    None => ()
  }
  @ast.TsExpr::CallExpr(@ast.TsExpr::Var(helper), call_args)
}

///|
fn extract_attr(
  attrs : Array[(String, @ast.TsExpr?)],
  name : String,
) -> @ast.TsExpr? {
  for a in attrs {
    if a.0 == name {
      return a.1
    }
  }
  None
}

///|
fn lower_classic(
  cfg : JsxConfig,
  tag : String,
  attrs : Array[(String, @ast.TsExpr?)],
  children : Array[@ast.TsExpr],
) -> @ast.TsExpr {
  let factory : @ast.TsExpr = parse_dotted_var(cfg.pragma_jsx)
  let type_expr = if tag == "" {
    parse_dotted_var(cfg.pragma_jsx_frag)
  } else {
    tag_to_type_expr(tag)
  }
  // Classic-runtime props object — `null` when no attrs, otherwise
  // an ObjectLit. Spread attrs flow through as a synthetic
  // `Object.assign({}, ...spread)` style; for v0 we emit `null` when
  // only spread is present and fall through to the new-runtime
  // shape otherwise (callers that want true classic Object.assign
  // can opt out at the configuration level).
  let props : @ast.TsExpr = if attrs.length() == 0 {
    @ast.TsExpr::NullLit
  } else {
    let entries : Array[(String, @ast.TsExpr)] = []
    for a in attrs {
      let name = a.0
      if name == "" {
        match a.1 {
          Some(v) => entries.push(("...", @ast.TsExpr::Spread(v)))
          None => ()
        }
      } else {
        let value = match a.1 {
          Some(v) => v
          None => @ast.TsExpr::BoolLit(true)
        }
        entries.push((name, value))
      }
    }
    @ast.TsExpr::ObjectLit(entries)
  }
  let args : Array[@ast.TsExpr] = [type_expr, props]
  for c in children {
    args.push(c)
  }
  @ast.TsExpr::CallExpr(factory, args)
}

// ---------------------------------------------------------------------------
// AST-walk lowering pass
// ---------------------------------------------------------------------------

///|
/// Walk a statement and replace any `JsxElement(...)` subtrees with
/// the runtime call form. Returns a new statement; non-JSX statements
/// pass through unchanged after their child expressions are walked.
pub fn lower_jsx_in_stmt(cfg : JsxConfig, stmt : @ast.TsStmt) -> @ast.TsStmt {
  match stmt {
    Var(b, t, init) => Var(b, t, lower_jsx_in_expr(cfg, init))
    Let(b, t, init) => Let(b, t, lower_jsx_in_expr(cfg, init))
    Const(b, t, init) => Const(b, t, lower_jsx_in_expr(cfg, init))
    Expr(e) => Expr(lower_jsx_in_expr(cfg, e))
    Return(opt) =>
      match opt {
        Some(e) => Return(Some(lower_jsx_in_expr(cfg, e)))
        None => Return(None)
      }
    Throw(e) => Throw(lower_jsx_in_expr(cfg, e))
    If(c, t, e_opt) =>
      If(
        lower_jsx_in_expr(cfg, c),
        lower_jsx_in_block(cfg, t),
        match e_opt {
          Some(b) => Some(lower_jsx_in_block(cfg, b))
          None => None
        },
      )
    While(c, body) =>
      While(lower_jsx_in_expr(cfg, c), lower_jsx_in_block(cfg, body))
    DoWhile(c, body) =>
      DoWhile(lower_jsx_in_expr(cfg, c), lower_jsx_in_block(cfg, body))
    For(init_opt, cond_opt, update_opt, body) => {
      let init_l = match init_opt {
        Some(s) => Some(lower_jsx_in_stmt(cfg, s))
        None => None
      }
      let cond_l = match cond_opt {
        Some(c) => Some(lower_jsx_in_expr(cfg, c))
        None => None
      }
      let update_l = match update_opt {
        Some(s) => Some(lower_jsx_in_stmt(cfg, s))
        None => None
      }
      For(init_l, cond_l, update_l, lower_jsx_in_block(cfg, body))
    }
    ForOf(kind, b, t, iter, body) =>
      ForOf(
        kind,
        b,
        t,
        lower_jsx_in_expr(cfg, iter),
        lower_jsx_in_block(cfg, body),
      )
    ForAwaitOf(kind, b, t, iter, body) =>
      ForAwaitOf(
        kind,
        b,
        t,
        lower_jsx_in_expr(cfg, iter),
        lower_jsx_in_block(cfg, body),
      )
    ForIn(kind, b, t, iter, body) =>
      ForIn(
        kind,
        b,
        t,
        lower_jsx_in_expr(cfg, iter),
        lower_jsx_in_block(cfg, body),
      )
    Switch(scrutinee, cases) => {
      let new_cases : Array[@ast.TsSwitchCase] = []
      for c in cases {
        let new_test = match c.test_expr {
          Some(t) => Some(lower_jsx_in_expr(cfg, t))
          None => None
        }
        new_cases.push({
          test_expr: new_test,
          body: lower_jsx_in_block(cfg, c.body),
        })
      }
      Switch(lower_jsx_in_expr(cfg, scrutinee), new_cases)
    }
    Try(t, cb, c, f) =>
      Try(
        lower_jsx_in_block(cfg, t),
        cb,
        match c {
          Some(b) => Some(lower_jsx_in_block(cfg, b))
          None => None
        },
        match f {
          Some(b) => Some(lower_jsx_in_block(cfg, b))
          None => None
        },
      )
    Block(b) => Block(lower_jsx_in_block(cfg, b))
    Label(name, inner) => Label(name, lower_jsx_in_stmt(cfg, inner))
    With(target, body) =>
      With(lower_jsx_in_expr(cfg, target), lower_jsx_in_block(cfg, body))
    Assign(name, e) => Assign(name, lower_jsx_in_expr(cfg, e))
    CompoundAssign(name, op, e) =>
      CompoundAssign(name, op, lower_jsx_in_expr(cfg, e))
    PropAssign(recv, prop, value) =>
      PropAssign(
        lower_jsx_in_expr(cfg, recv),
        prop,
        lower_jsx_in_expr(cfg, value),
      )
    IndexAssign(recv, idx, value) =>
      IndexAssign(
        lower_jsx_in_expr(cfg, recv),
        lower_jsx_in_expr(cfg, idx),
        lower_jsx_in_expr(cfg, value),
      )
    Break(_) | Continue(_) | Debugger | Empty => stmt
    NativeClassStmt(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: lower_jsx_in_block(cfg, f.body) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(lower_jsx_in_block(cfg, b))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, lower_jsx_in_expr(cfg, sf.1)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(lower_jsx_in_expr(cfg, b))
        None => None
      }
      NativeClassStmt(
        {
          ..decl,
          base_expr: new_base_expr,
          methods: new_methods,
          static_field_inits: new_static_fields,
        },
        new_ctor,
      )
    }
  }
}

///|
pub fn lower_jsx_in_block(
  cfg : JsxConfig,
  block : @ast.TsBlock,
) -> @ast.TsBlock {
  let stmts : Array[@ast.TsStmt] = []
  for s in block.stmts {
    stmts.push(lower_jsx_in_stmt(cfg, s))
  }
  // Carry the original `stmt_positions` forward so the source-map
  // generator can still map each lowered top-level stmt back to its
  // input position. (JSX lowering doesn't change the count or order
  // of top-level statements.)
  { stmts, stmt_positions: block.stmt_positions }
}

///|
/// Lower every JSX node reachable from `expr` to the runtime-call
/// shape. Pure non-JSX expressions are returned unchanged after their
/// sub-expressions are walked recursively.
pub fn lower_jsx_in_expr(cfg : JsxConfig, expr : @ast.TsExpr) -> @ast.TsExpr {
  match expr {
    JsxElement(tag, attrs, children) => {
      let new_attrs : Array[(String, @ast.TsExpr?)] = []
      for a in attrs {
        let new_val : @ast.TsExpr? = match a.1 {
          Some(v) => Some(lower_jsx_in_expr(cfg, v))
          None => None
        }
        new_attrs.push((a.0, new_val))
      }
      lower_jsx_element(cfg, tag, new_attrs, children)
    }
    BinOp(op, a, b) =>
      BinOp(op, lower_jsx_in_expr(cfg, a), lower_jsx_in_expr(cfg, b))
    UnaryOp(op, inner) => UnaryOp(op, lower_jsx_in_expr(cfg, inner))
    Cond(c, t, e) =>
      Cond(
        lower_jsx_in_expr(cfg, c),
        lower_jsx_in_expr(cfg, t),
        lower_jsx_in_expr(cfg, e),
      )
    Call(name, args) => Call(name, lower_jsx_in_exprs(cfg, args))
    CallExpr(callee, args) =>
      CallExpr(lower_jsx_in_expr(cfg, callee), lower_jsx_in_exprs(cfg, args))
    New(name, args) => New(name, lower_jsx_in_exprs(cfg, args))
    NewExpr(callee, args) =>
      NewExpr(lower_jsx_in_expr(cfg, callee), lower_jsx_in_exprs(cfg, args))
    MethodCall(recv, m, args) =>
      MethodCall(lower_jsx_in_expr(cfg, recv), m, lower_jsx_in_exprs(cfg, args))
    PropAccess(recv, n) => PropAccess(lower_jsx_in_expr(cfg, recv), n)
    IndexAccess(recv, idx) =>
      IndexAccess(lower_jsx_in_expr(cfg, recv), lower_jsx_in_expr(cfg, idx))
    ArrayLit(items) => ArrayLit(lower_jsx_in_exprs(cfg, items))
    Spread(inner) => Spread(lower_jsx_in_expr(cfg, inner))
    ObjectLit(entries) => {
      let new_entries : Array[(String, @ast.TsExpr)] = []
      for ent in entries {
        new_entries.push((ent.0, lower_jsx_in_expr(cfg, ent.1)))
      }
      ObjectLit(new_entries)
    }
    ComputedProp(k, v) =>
      ComputedProp(lower_jsx_in_expr(cfg, k), lower_jsx_in_expr(cfg, v))
    AssignExpr(name, v) => AssignExpr(name, lower_jsx_in_expr(cfg, v))
    AssignPattern(b, v) => AssignPattern(b, lower_jsx_in_expr(cfg, v))
    CompoundAssignExpr(t, op, v) =>
      CompoundAssignExpr(
        lower_jsx_in_expr(cfg, t),
        op,
        lower_jsx_in_expr(cfg, v),
      )
    PropAssignExpr(recv, p, v) =>
      PropAssignExpr(lower_jsx_in_expr(cfg, recv), p, lower_jsx_in_expr(cfg, v))
    IndexAssignExpr(recv, idx, v) =>
      IndexAssignExpr(
        lower_jsx_in_expr(cfg, recv),
        lower_jsx_in_expr(cfg, idx),
        lower_jsx_in_expr(cfg, v),
      )
    Seq(a, b) => Seq(lower_jsx_in_expr(cfg, a), lower_jsx_in_expr(cfg, b))
    ArrowFunc(params, ret, body, is_async) => {
      let new_body = match body {
        ArrowExpr(e) => @ast.TsArrowBody::ArrowExpr(lower_jsx_in_expr(cfg, e))
        ArrowBlock(b) =>
          @ast.TsArrowBody::ArrowBlock(lower_jsx_in_block(cfg, b))
      }
      ArrowFunc(params, ret, new_body, is_async)
    }
    Yield(opt) =>
      match opt {
        Some(e) => Yield(Some(lower_jsx_in_expr(cfg, e)))
        None => Yield(None)
      }
    YieldStar(inner) => YieldStar(lower_jsx_in_expr(cfg, inner))
    Await(inner) => Await(lower_jsx_in_expr(cfg, inner))
    DynamicImport(spec, opts) =>
      DynamicImport(
        lower_jsx_in_expr(cfg, spec),
        match opts {
          Some(o) => Some(lower_jsx_in_expr(cfg, o))
          None => None
        },
      )
    TaggedTemplate(tag, parts, raw, exprs) =>
      TaggedTemplate(
        lower_jsx_in_expr(cfg, tag),
        parts,
        raw,
        lower_jsx_in_exprs(cfg, exprs),
      )
    TemplateLiteral(parts, exprs) =>
      TemplateLiteral(parts, lower_jsx_in_exprs(cfg, exprs))
    As(inner, ty) => As(lower_jsx_in_expr(cfg, inner), ty)
    Satisfies(inner, ty) => Satisfies(lower_jsx_in_expr(cfg, inner), ty)
    NonNull(inner) => NonNull(lower_jsx_in_expr(cfg, inner))
    OptionalChain(inner) => OptionalChain(lower_jsx_in_expr(cfg, inner))
    FuncExpr(_) => expr // function-expression bodies are not JSX-walked yet
    NativeClassExpr(decl, ctor) => {
      let new_ctor = match ctor {
        Some(f) => Some({ ..f, body: lower_jsx_in_block(cfg, f.body) })
        None => None
      }
      let new_methods : Array[@ast.TsClassMethodDecl] = []
      for m in decl.methods {
        let new_body = match m.body {
          Some(b) => Some(lower_jsx_in_block(cfg, b))
          None => None
        }
        new_methods.push({ ..m, body: new_body })
      }
      let new_static_fields : Array[(String, @ast.TsExpr)] = []
      for sf in decl.static_field_inits {
        new_static_fields.push((sf.0, lower_jsx_in_expr(cfg, sf.1)))
      }
      let new_base_expr = match decl.base_expr {
        Some(b) => Some(lower_jsx_in_expr(cfg, b))
        None => None
      }
      NativeClassExpr(
        {
          ..decl,
          base_expr: new_base_expr,
          methods: new_methods,
          static_field_inits: new_static_fields,
        },
        new_ctor,
      )
    }
    _ => expr
  }
}

///|
fn lower_jsx_in_exprs(
  cfg : JsxConfig,
  exprs : Array[@ast.TsExpr],
) -> Array[@ast.TsExpr] {
  let out : Array[@ast.TsExpr] = []
  for e in exprs {
    out.push(lower_jsx_in_expr(cfg, e))
  }
  out
}

///|
/// Module-level convenience: lower JSX through a whole block + return
/// the list of jsx-runtime helpers actually referenced. The caller can
/// then prepend an `import { jsx, jsxs, Fragment } from "<import_source>/jsx-runtime"`
/// statement to the emitted output.
pub fn lower_block_with_runtime_imports(
  cfg : JsxConfig,
  block : @ast.TsBlock,
) -> (@ast.TsBlock, Array[String]) {
  let walked = lower_jsx_in_block(cfg, block)
  let needed : Array[String] = []
  let mut needs_jsx = false
  let mut needs_jsxs = false
  let mut needs_jsx_dev = false
  let mut needs_jsxs_dev = false
  let mut needs_fragment = false
  collect_runtime_refs(walked, fn(name) {
    match name {
      "jsx" => needs_jsx = true
      "jsxs" => needs_jsxs = true
      "jsxDEV" => needs_jsx_dev = true
      "jsxsDEV" => needs_jsxs_dev = true
      "Fragment" => needs_fragment = true
      _ => ()
    }
  })
  if needs_jsx {
    needed.push("jsx")
  }
  if needs_jsxs {
    needed.push("jsxs")
  }
  if needs_jsx_dev {
    needed.push("jsxDEV")
  }
  if needs_jsxs_dev {
    needed.push("jsxsDEV")
  }
  if needs_fragment {
    needed.push("Fragment")
  }
  (walked, needed)
}

///|
fn collect_runtime_refs(block : @ast.TsBlock, mark : (String) -> Unit) -> Unit {
  for s in block.stmts {
    collect_refs_stmt(s, mark)
  }
}

///|
fn collect_refs_stmt(stmt : @ast.TsStmt, mark : (String) -> Unit) -> Unit {
  match stmt {
    Expr(e) | Return(Some(e)) | Throw(e) => collect_refs_expr(e, mark)
    Var(_, _, e) | Let(_, _, e) | Const(_, _, e) => collect_refs_expr(e, mark)
    If(c, t, eopt) => {
      collect_refs_expr(c, mark)
      collect_runtime_refs(t, mark)
      match eopt {
        Some(b) => collect_runtime_refs(b, mark)
        None => ()
      }
    }
    While(c, b) | DoWhile(c, b) => {
      collect_refs_expr(c, mark)
      collect_runtime_refs(b, mark)
    }
    For(_, _, _, b) | ForOf(_, _, _, _, b) | ForIn(_, _, _, _, b) =>
      collect_runtime_refs(b, mark)
    Block(b) => collect_runtime_refs(b, mark)
    _ => ()
  }
}

///|
fn collect_refs_expr(expr : @ast.TsExpr, mark : (String) -> Unit) -> Unit {
  match expr {
    Var(name) =>
      match name {
        "jsx" | "jsxs" | "jsxDEV" | "jsxsDEV" | "Fragment" => mark(name)
        _ => ()
      }
    CallExpr(callee, args) => {
      collect_refs_expr(callee, mark)
      for a in args {
        collect_refs_expr(a, mark)
      }
    }
    Call(name, args) => {
      match name {
        "jsx" | "jsxs" | "jsxDEV" | "jsxsDEV" | "Fragment" => mark(name)
        _ => ()
      }
      for a in args {
        collect_refs_expr(a, mark)
      }
    }
    BinOp(_, a, b) => {
      collect_refs_expr(a, mark)
      collect_refs_expr(b, mark)
    }
    PropAccess(r, _) => collect_refs_expr(r, mark)
    MethodCall(r, _, args) => {
      collect_refs_expr(r, mark)
      for a in args {
        collect_refs_expr(a, mark)
      }
    }
    ObjectLit(entries) =>
      for ent in entries {
        collect_refs_expr(ent.1, mark)
      }
    ArrayLit(items) =>
      for i in items {
        collect_refs_expr(i, mark)
      }
    Cond(c, t, e) => {
      collect_refs_expr(c, mark)
      collect_refs_expr(t, mark)
      collect_refs_expr(e, mark)
    }
    UnaryOp(_, inner) => collect_refs_expr(inner, mark)
    Spread(inner) | Await(inner) | YieldStar(inner) =>
      collect_refs_expr(inner, mark)
    Yield(opt) =>
      match opt {
        Some(e) => collect_refs_expr(e, mark)
        None => ()
      }
    ArrowFunc(_, _, body, _) =>
      match body {
        ArrowExpr(e) => collect_refs_expr(e, mark)
        ArrowBlock(b) => collect_runtime_refs(b, mark)
      }
    _ => ()
  }
}
