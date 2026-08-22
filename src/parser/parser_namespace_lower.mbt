// Runtime-namespace lowering.
//
// `namespace N { … }` (and its `module N { … }` spelling) declares a
// value, not just a type: the body's exported members have to exist at
// runtime under `N`. The statement parser used to skip these bodies
// wholesale, which left every `N.member` reference in the emitted
// JavaScript with nothing declaring `N` — a `ReferenceError` on load,
// with no diagnostic.
//
// The lowering mirrors what TypeScript emits:
//
//   namespace N {
//     const secret = 1;
//     export function f() { return secret; }
//   }
//
//   var N = N || {};
//   (function (N) {
//     const secret = 1;
//     function f() { return secret; }
//     N.f = f;
//   })(N);
//
// `var` (not `let`) plus `N || {}` is what makes declaration merging
// work: a second `namespace N { … }` block reuses the same object.
//
// Ambient forms (`declare namespace`, `declare module "x"`,
// `declare global`) are NOT lowered — they declare types only and are
// erased, which is exactly right. They never reach here: the `declare`
// prefix routes them elsewhere.

///|
/// A lowered namespace: the statement to emit, the name it binds, and
/// any enums its body declared (the caller registers those so
/// const-enum inlining can still see them).
struct LoweredNamespace {
  name : String
  stmt : @ast.TsStmt
  enums : Array[@ast.TsEnumDecl]
}

///|
/// Parse `namespace N { … }` / `module N { … }` at statement position
/// and return its runtime lowering.
///
/// The body is parsed exactly once. Parsing it a second time for the
/// type side is what makes nested namespaces blow up exponentially —
/// a 3 MB source with one top-level `namespace` never finished.
///
/// Returns `None` — leaving the caller to skip the declaration — for
/// the forms this lowering does not model: a quoted module name
/// (`module "foo" { … }`, only meaningful as an ambient declaration), a
/// dotted path (`namespace A.B { … }`), and a body that fails to parse
/// as runtime code.
fn Parser::parse_lowered_namespace(
  self : Parser,
) -> LoweredNamespace? raise ParseError {
  let keyword = match self.peek().kind {
    Ident(name) if name == "namespace" || name == "module" => name
    _ => return None
  }
  // `global { … }` is an augmentation, never a runtime value.
  if keyword == "global" {
    return None
  }
  let saved_pos = self.pos
  let _ = self.advance()
  // A quoted name means an ambient external module declaration.
  let name = match self.peek().kind {
    Ident(_) => self.parse_binding_ident()
    _ => {
      self.pos = saved_pos
      return None
    }
  }
  // `namespace A.B { … }` nests one namespace inside another. Bail
  // rather than model it half-way.
  if self.check(Dot) {
    self.pos = saved_pos
    return None
  }
  if !self.check(LBrace) {
    self.pos = saved_pos
    return None
  }
  let body_source = self.parse_declaration_block_source()
  if body_source.trim() == "" {
    // An empty namespace still declares the object.
    return Some({ name, stmt: namespace_object_decl(name), enums: [] })
  }
  let parsed = try Parser::from_source_with_jsx(
      body_source, self.allow_jsx,
    ).parse_module_block() catch {
    _ => return None
  } noraise {
    block => block
  }
  Some({
    name,
    stmt: lower_namespace_block(name, parsed),
    enums: parsed.enums,
  })
}

///|
/// `var N = N || {};` — the namespace object, reused when a later block
/// merges into the same name.
fn namespace_object_decl(name : String) -> @ast.TsStmt {
  @ast.TsStmt::Var(
    @ast.TsBinding::Ident(name),
    @ast.TsType::Any,
    @ast.TsExpr::BinOp(
      @ast.TsBinOp::Or,
      @ast.TsExpr::Var(name),
      @ast.TsExpr::ObjectLit([]),
    ),
  )
}

///|
/// Build `Block([var N = N || {}, (function (N) { … })(N)])`.
fn lower_namespace_block(
  name : String,
  body : @ast.TsModuleBlock,
) -> @ast.TsStmt {
  let inner : Array[@ast.TsStmt] = []
  for stmt in body.block.stmts {
    inner.push(stmt)
  }
  // Names the body declares at runtime. An `export type { T }` /
  // `export interface I` spec has no runtime binding, so assigning it
  // onto the namespace object would reference a name that does not
  // exist.
  let declared : Map[String, Bool] = {}
  let mutable : Map[String, Bool] = {}
  for stmt in body.block.stmts {
    collect_namespace_decl_names(stmt, declared, mutable)
  }
  for spec in body.exports {
    if !declared.contains(spec.local_name) {
      continue
    }
    if mutable.contains(spec.local_name) {
      // `export let x` can be reassigned from inside the namespace, and
      // a plain `N.x = x` snapshot would then go stale. A getter keeps
      // reads live. (Writes through `N.x` don't propagate back to the
      // local — TypeScript rewrites those references instead, which
      // needs a full scope rewrite.)
      inner.push(namespace_live_export(name, spec.export_name, spec.local_name))
    } else {
      inner.push(
        @ast.TsStmt::PropAssign(
          @ast.TsExpr::Var(name),
          spec.export_name,
          @ast.TsExpr::Var(spec.local_name),
        ),
      )
    }
  }
  let func : @ast.TsFunc = {
    name: "",
    type_params: [],
    const_type_params: [],
    type_param_bounds: [],
    params: [
      {
        name,
        binding: None,
        is_rest: false,
        is_optional: false,
        type_: @ast.TsType::Any,
        default: None,
      },
    ],
    return_type: @ast.TsType::Void,
    body: { stmts: inner, stmt_positions: [] },
    is_generator: false,
    is_async: false,
  }
  @ast.TsStmt::Block({
    stmts: [
      namespace_object_decl(name),
      @ast.TsStmt::Expr(
        @ast.TsExpr::CallExpr(@ast.TsExpr::FuncExpr(func), [
          @ast.TsExpr::Var(name),
        ]),
      ),
    ],
    stmt_positions: [],
  })
}

///|
/// `Object.defineProperty(N, "x", { get: function () { return x; }, enumerable: true })`
fn namespace_live_export(
  namespace_name : String,
  export_name : String,
  local_name : String,
) -> @ast.TsStmt {
  let getter : @ast.TsFunc = {
    name: "",
    type_params: [],
    const_type_params: [],
    type_param_bounds: [],
    params: [],
    return_type: @ast.TsType::Any,
    body: {
      stmts: [@ast.TsStmt::Return(Some(@ast.TsExpr::Var(local_name)))],
      stmt_positions: [],
    },
    is_generator: false,
    is_async: false,
  }
  @ast.TsStmt::Expr(
    @ast.TsExpr::MethodCall(@ast.TsExpr::Var("Object"), "defineProperty", [
      @ast.TsExpr::Var(namespace_name),
      @ast.TsExpr::StringLit(export_name),
      @ast.TsExpr::ObjectLit([
        ("get", @ast.TsExpr::FuncExpr(getter)),
        ("enumerable", @ast.TsExpr::BoolLit(true)),
      ]),
    ]),
  )
}

///|
/// Names a namespace body declares at runtime, plus which of them are
/// reassignable (`let` / `var`).
fn collect_namespace_decl_names(
  stmt : @ast.TsStmt,
  declared : Map[String, Bool],
  mutable : Map[String, Bool],
) -> Unit {
  match stmt {
    Const(@ast.TsBinding::Ident(n), _, _) => declared[n] = true
    Let(@ast.TsBinding::Ident(n), _, @ast.TsExpr::FuncExpr(_)) =>
      // A `function f() {}` declaration is lowered to `Let(f, FuncExpr)`;
      // it is not a reassignable variable.
      declared[n] = true
    Let(@ast.TsBinding::Ident(n), _, _) | Var(@ast.TsBinding::Ident(n), _, _) => {
      declared[n] = true
      mutable[n] = true
    }
    NativeClassStmt(decl, _) => declared[decl.name] = true
    // The enum lowering and multi-declarator `var a = 1, b = 2` both
    // nest their statements one block deep.
    Block(inner) =>
      for s in inner.stmts {
        collect_namespace_decl_names(s, declared, mutable)
      }
    _ => ()
  }
}
