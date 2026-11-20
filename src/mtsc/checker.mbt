///|
/// A strict TypeScript diagnostic that can be consumed by command-line and
/// JavaScript-module callers alike.
pub(all) struct MtscTypeIssue {
  path : String
  message : String
}

///|
/// One caller-resolved TypeScript module for the JavaScript checker API.
/// Resolution intentionally belongs to the embedding build tool; the checker
/// only parses and validates the source texts it is given.
pub(all) struct MtscModuleSource {
  path : String
  source : String
  allowJsx : Bool
}

///|
/// A caller-resolved import edge. Module resolution belongs to the embedding
/// build tool, so aliases and virtual files never leak into the checker.
pub(all) struct MtscModuleEdge {
  importerPath : String
  moduleSpecifier : String
  targetPath : String
}

///|
/// A filesystem-free module graph consumed by `checkModuleGraph`.
pub(all) struct MtscModuleGraph {
  modules : Array[MtscModuleSource]
  edges : Array[MtscModuleEdge]
}

///|
priv struct ParsedMtscModule {
  source : MtscModuleSource
  module_ : @ast.TsModule
  module_block : @ast.TsModuleBlock
}

///|
fn is_unresolved_import_binding(
  issue : @checker.ExprIssue,
  imported_binding_names : Array[String],
) -> Bool {
  for name in imported_binding_names {
    if issue.message == "cannot find name `\{name}`" {
      return true
    }
  }
  false
}

///|
/// Parse source and run the strict checker. Imported bindings are checked in
/// their own modules, so their known single-file unresolved-name false
/// positives are omitted from this module's result.
fn collect_type_issues_from_module(
  module_ : @ast.TsModule,
  globals : Array[(String, @ast.TsType)],
  type_modules : Array[@ast.TsModule],
  namespace_type_aliases~ : Array[(String, String, String)] = [],
  type_module_keys~ : Array[String] = [],
  type_module_import_aliases~ : Array[Array[(String, String, String)]] = [],
) -> Result[Array[MtscTypeIssue], String] {
  let issues : Array[MtscTypeIssue] = []
  for
    issue in @checker.check_module_function_bodies_with_context(
      module_,
      globals,
      type_modules,
      namespace_type_aliases~,
      type_module_keys~,
      type_module_import_aliases~,
    ) {
    if !is_unresolved_import_binding(issue, module_.imported_binding_names) {
      issues.push({ path: issue.path, message: issue.message, })
    }
  }
  Ok(issues)
}

///|
/// `declaration_file~` says the source is a `.d.ts`, which makes every
/// declaration in it ambient whether or not it writes `declare`. A
/// labelled argument with a default, because this is the JavaScript ABI
/// and every existing caller must keep compiling and answering exactly
/// as before — and because the fact lives in the PATH, which a caller
/// holding only `source` genuinely cannot supply. The parse flag is read
/// only to go SILENT, so `false` is today's behaviour.
///
/// `compiler_options~` is a tsconfig's `compilerOptions`, as
/// `compiler_option_header` takes them; empty means none were given.
pub fn collect_type_issues(
  source : String,
  allow_jsx : Bool,
  declaration_file~ : Bool = false,
  compiler_options~ : Array[(String, String)] = [],
) -> Result[Array[MtscTypeIssue], String] {
  let parser = @parser.Parser::from_source_with_jsx(
    source,
    allow_jsx,
    option_header=compiler_option_header(compiler_options),
  )
  // A checking parse: keep `as const` for the checker (no transform reads
  // this module).
  parser.keep_const_assertions()
  if declaration_file {
    parser.mark_declaration_file()
  }
  let module_ = parser.parse_module() catch { e => return Err("\{e}") }
  collect_type_issues_from_module(module_, [], [])
}

///|
/// JavaScript-facing strict checker API. Returns an empty string for valid
/// source; otherwise each diagnostic occupies one line as
/// `<path>: <message>`. This keeps the JS ABI plain while the MoonBit CLI can
/// still use `collect_type_issues` for structured diagnostics.
pub fn check_source(source : String, allow_jsx : Bool) -> String {
  match collect_type_issues(source, allow_jsx) {
    Err(e) => "parse error: \{e}"
    Ok(issues) =>
      issues.map(fn(issue) { "\{issue.path}: \{issue.message}" }).join("\n")
  }
}

///|
/// JavaScript-facing strict checker API for a resolved module graph.
/// Resolution remains the caller's responsibility so this package stays
/// independent of filesystems and bundlers.
///
/// Returns an empty string when every supplied module is valid. Diagnostics
/// are prefixed with the caller-provided module path and preserve input order,
/// making the string ABI stable for build-tool integrations.
pub fn check_module_sources(modules : Array[MtscModuleSource]) -> String {
  let diagnostics : Array[String] = []
  for module_ in modules {
    match collect_type_issues(module_.source, module_.allowJsx) {
      Err(e) => diagnostics.push("\{module_.path}: parse error: \{e}")
      Ok(issues) =>
        for issue in issues {
          diagnostics.push("\{module_.path}: \{issue.message}")
        }
    }
  }
  diagnostics.join("\n")
}

///|
fn parse_graph_module(
  source : MtscModuleSource,
  option_header~ : String = "",
  // The source is an ambient module BODY (`graph_with_ambient_modules`).
  ambient_body~ : Bool = false,
) -> Result[ParsedMtscModule, String] {
  // A declaration file makes every declaration in it ambient whether or
  // not it writes `declare`; the PATH is the only place that fact lives,
  // and the bodiless-declaration rules read it only to go silent.
  // `.d.mts` / `.d.cts` are declaration files too: zod's `types` condition
  // names `index.d.cts`, and the graph loader reads it.
  let is_dts = source.path.has_suffix(".d.ts") ||
    source.path.has_suffix(".d.mts") ||
    source.path.has_suffix(".d.cts")
  let p1 = @parser.Parser::from_source_with_jsx(
    source.source,
    source.allowJsx,
    option_header~,
  )
  p1.keep_const_assertions()
  if is_dts {
    p1.mark_declaration_file()
  }
  let module_ = try {
    if ambient_body {
      p1.parse_ambient_module_body()
    } else {
      p1.parse_module()
    }
  } catch {
    e => return Err("\{e}")
  }
  let p2 = @parser.Parser::from_source_with_jsx(
    source.source,
    source.allowJsx,
    option_header~,
  )
  p2.keep_const_assertions()
  if is_dts {
    p2.mark_declaration_file()
  }
  let module_block = p2.parse_module_block() catch { e => return Err("\{e}") }
  Ok({ source, module_, module_block, })
}

///|
/// `function_value_type` under a binder for the function's own type
/// parameters, so an importer's call solves them (`@import-generic:`).
fn generic_function_value_type(func : @ast.TsFunc) -> @ast.TsType {
  let f = function_value_type(func)
  if func.type_params.is_empty() {
    f
  } else {
    @ast.TsType::GenericFunc(func.type_params, func.type_param_bounds, f)
  }
}

///|
fn function_value_type(func : @ast.TsFunc) -> @ast.TsType {
  let params : Array[@ast.TsType] = []
  let names : Array[String] = []
  for i, param in func.params {
    // A leading `this` parameter types the receiver and takes no argument
    // position (`declare_function_value_type` drops it the same way).
    if i == 0 && param.name == "this" && !param.is_rest {
      continue
    }
    names.push(param.name)
    if param.is_rest {
      params.push(@ast.TsType::Rest(param.type_))
    } else if param.is_optional || param.default is Some(_) {
      // A parameter written `x?` or with a default may be omitted, and a
      // `Func` says so the way the checker reads it: `T | undefined`.
      // Without it, an imported `joinValues(array, separator = " | ")`
      // demanded two arguments at every call.
      params.push(
        match param.type_ {
          Union(parts) if parts.contains(Undefined) => param.type_
          t => @ast.TsType::Union([t, Undefined])
        },
      )
    } else {
      params.push(param.type_)
    }
  }
  @ast.TsType::Func(
    params,
    @ast.index_predicate_subject(func.return_type, names),
  )
}

///|
/// The value type of one `declare function` signature, in the shape
/// `function_value_type` gives a function declaration: a leading `this`
/// parameter dropped (it types the receiver and takes no argument), a rest
/// parameter as `Rest(_)`, and the type parameters as a `GenericFunc`
/// binder so an importer's call solves them (`@import-generic:`).
///
/// The parameters are the INLINED ones — a bounded `T extends B` reads as
/// `B` — so a bounded parameter is judged against its bound, as it was
/// before; only an unbounded one is left for the call to solve. Optional
/// parameters already arrive as `T | undefined`, which is how a `Func`
/// spells "may be omitted".
fn declare_function_value_type(import_ : @ast.TsImport) -> @ast.TsType {
  let start = if import_.params.length() > 0 && import_.params[0].0 == "this" {
    1
  } else {
    0
  }
  let params : Array[@ast.TsType] = []
  for i in start..<import_.params.length() {
    let t = import_.params[i].1
    if i < import_.param_is_rest.length() && import_.param_is_rest[i] {
      params.push(@ast.TsType::Rest(t))
    } else {
      params.push(t)
    }
  }
  let names = import_.params[start:].iter().map(fn(p) { p.0 }).collect()
  let f = @ast.TsType::Func(
    params,
    @ast.index_predicate_subject(import_.return_type, names),
  )
  if import_.type_params.is_empty() {
    f
  } else {
    @ast.TsType::GenericFunc(import_.type_params, [], f)
  }
}

///|
fn local_value_type(module_ : @ast.TsModule, name : String) -> @ast.TsType? {
  // A namespace is lowered to `var N = N || {}`, so `values` holds it as
  // `any` and has to be passed over. A class of the same name is a
  // declaration merge whose value is that class. A FUNCTION of the same
  // name is one too, and its value is both: callable, with the
  // namespace's members on it — preact's `h` (five overloads plus
  // `namespace h { … }`), drizzle's `sql`, express's `e`. The lowered
  // `var` used to answer first there, so all three were `any`.
  //
  // Only an INSTANTIATED namespace contributes a value. A type-only one
  // (`export const Foo = …` beside `export namespace Foo { type T = … }`,
  // a common way to give a value a namespace of types) has no runtime
  // binding, and reading it as an empty object shadowed the `const`.
  if !module_.classes.iter().any(fn(c) { c.name == name }) {
    for ns in module_.namespaces {
      if ns.name != name {
        continue
      }
      match local_function_value_type(module_, name) {
        Some(callable) =>
          return Some(
            callable_with_members(callable, namespace_value_type(ns.module_)),
          )
        None =>
          if namespace_is_instantiated(ns.module_) {
            return Some(namespace_value_type(ns.module_))
          }
      }
      break
    }
  }
  for value in declared_values(module_) {
    if value.name == name {
      match value.type_ {
        Any =>
          match arrow_const_predicate_type(module_, name) {
            Some(t) => return Some(t)
            None => ()
          }
        _ => ()
      }
      return Some(spread_objects_as_any(value.type_))
    }
  }
  match arrow_const_predicate_type(module_, name) {
    Some(t) => return Some(t)
    None => ()
  }
  match local_function_value_type(module_, name) {
    Some(t) => return Some(t)
    None => ()
  }
  for enum_ in module_.enums {
    if enum_.name == name {
      return Some(@ast.TsType::Named(name))
    }
  }
  // A class used as a VALUE is its constructor, not an instance, and this
  // checker has no constructor-type spelling an importer can use — a
  // class declared in the SAME file is `any` as a value for that reason.
  // `Named(name)` here is the INSTANCE type, so an imported class read as
  // a value was wrong in both directions: redi's `injector.add([Svc])`
  // compared `Svc[]` (instances) against `[Ctor<T>]` and reported, and a
  // static member was looked up among the instance's. The importer now
  // sees what a local use sees.
  for class_ in module_.classes {
    if class_.name == name {
      return Some(@ast.TsType::Any)
    }
  }
  None
}

///|
/// The value of a function `name` declares, as a function declaration
/// (`funcs`) or a `declare function` (`imports`): one signature, or the
/// `Union` an overload set is.
fn local_function_value_type(
  module_ : @ast.TsModule,
  name : String,
) -> @ast.TsType? {
  // An OVERLOADED function is several declarations of one name, and the
  // first is only one of its signatures: effect's `pipe` / `flow` have
  // twenty, and handing an importer the first made every call with more
  // arguments "expected 1 argument(s)". A union of the declarations' types
  // is the overload-set shape the checker ingests a local one as.
  //
  // Each signature carries its own type parameters as a `GenericFunc`
  // binder, as a `declare function` does (`declare_function_value_type`):
  // without one an importer read `S` in preact's
  // `function useState<S>(init: S | (() => S)): [S, Dispatch<…>]` — a
  // bodiless `function` in a `.d.ts`, not a `declare function` — as a name
  // it could not resolve, and `const [n, setN] = useState(0)` came back
  // with `setN: undefined`, "not callable" on every state update.
  //
  // An overload set's IMPLEMENTATION is not part of its callable surface
  // when overload signatures exist, in tsc as in `Resolver::ingest_module`
  // (`has_sig_only`). Kept here it was the one non-generic member, which
  // the overload matcher tries first, and it accepts any call: effect's
  // `pipe(a, f, g, …)` came back `unknown` from `pipe(a: unknown, …):
  // unknown` instead of solving the overload written for that many
  // arguments.
  //
  // Which declaration IS the implementation is a parse-time fact: the
  // parser's `<fn-impl:NAME>` marker says one exists, and tsc requires it
  // to follow its signatures directly, so it is the LAST declaration of
  // the name. An empty statement list cannot tell `f(x: any): void {}`
  // from a signature, and that implementation then stayed callable, so
  // `f(123)` was accepted against `f(x: string): void`. Where no marker
  // exists (a declaration file, or a set with no implementation) the
  // statement count is the remaining evidence.
  let decls = module_.funcs.filter(fn(f) { f.name == name })
  let has_impl = module_.grammar_misuses.contains("<fn-impl:\{name}>")
  let has_signature_only = decls
    .iter()
    .any(fn(f) { f.body.stmts.length() == 0 })
  let sigs : Array[@ast.TsType] = []
  for i, func in decls {
    let callable = if has_impl && decls.length() > 1 {
      i < decls.length() - 1
    } else {
      !has_signature_only || func.body.stmts.length() == 0
    }
    if callable {
      // An unannotated return is read from the body, as a function
      // declared in the importer's own file is (see
      // `unannotated_function_return_from_body`).
      let func = match
        @checker.unannotated_function_return_from_body(module_, func) {
        Some(t) => { ..func, return_type: t, }
        None => func
      }
      sigs.push(generic_function_value_type(func))
    }
  }
  match sigs.length() {
    0 => ()
    // A BOUNDED generic function's parameters arrive with the bound
    // inlined (`T extends Trait` stored as `Trait`), which made an importer
    // judge `make("E", init)` against `(inst: Trait) => void` and reject an
    // `init` taking the subtype tsc infers `T` from. The un-inlined copy
    // the parser keeps for call-site inference is the real signature, and
    // a binder over it lets the importer solve `T` the way a local caller
    // does.
    1 =>
      match
        (
          module_.raw_generic_signatures.get(name),
          module_.funcs.iter().find_first(fn(f) { f.name == name }),
        ) {
        (Some(Func(raw_params, raw_ret)), Some(func)) if !func.type_params.is_empty() &&
          raw_params.length() == func.params.length() => {
          // The raw copy keeps the TYPES and not the optionality, which
          // `function_value_type` reads off the declaration: without it
          // `joinValues(array, separator = " | ")` demanded two arguments.
          // A REST parameter is wrapped the way `function_value_type`
          // wraps one, which is how a `Func` says "any number from here":
          // left bare, `polygon<P>(...points: P[])` read as one parameter
          // and every call with more was "expected 1 argument(s)" once the
          // count of an imported generic was judged.
          let params = raw_params.mapi(fn(i, t) {
            let p = func.params[i]
            if p.is_rest {
              match t {
                Rest(_) => t
                _ => @ast.TsType::Rest(t)
              }
            } else if p.is_optional || p.default is Some(_) {
              match t {
                Union(parts) if parts.contains(Undefined) => t
                _ => @ast.TsType::Union([t, Undefined])
              }
            } else {
              t
            }
          })
          // The declared bounds ride along: a primitive-constrained
          // parameter keeps a fresh literal at the call (see the
          // `@import-generic:` arm of `infer_expr`).
          return Some(
            @ast.TsType::GenericFunc(
              func.type_params,
              func.type_param_bounds,
              Func(params, raw_ret),
            ),
          )
        }
        _ => return Some(sigs[0])
      }
    _ => return Some(@ast.TsType::Union(sigs))
  }
  // A `declare function` — every function a `.d.ts` declares — is held as
  // a `TsImport`, and this branch used to read the FIRST one as a bare
  // `Func`: an overload set lost every signature but one (drizzle's
  // `integer()` / `integer(config?)` / `integer(name, config?)` made
  // `integer("id")` "expected 0 argument(s)"), a rest parameter read as a
  // single array argument (`and(...conditions)` became "expected 1"), and
  // a type parameter was an unbound name (preact's `useState<S>`). None of
  // it showed while a package's declarations were never loaded; the
  // types-mode check graph loads them. The shape now matches what the
  // `funcs` branch above builds for a function declaration.
  let declared : Array[@ast.TsType] = []
  for import_ in module_.imports {
    if import_.name == name {
      declared.push(declare_function_value_type(import_))
    }
  }
  match declared.length() {
    0 => ()
    1 => return Some(declared[0])
    _ => return Some(@ast.TsType::Union(declared))
  }
  None
}

///|
/// A function merged with a namespace: its signatures as `<call>` entries,
/// which is how an object type literal holds call signatures, beside the
/// namespace's members.
fn callable_with_members(
  callable : @ast.TsType,
  members : @ast.TsType,
) -> @ast.TsType {
  let fields : Array[(@ast.TsType, @ast.TsType)] = []
  match callable {
    Union(parts) =>
      for part in parts {
        fields.push((Literal("<call>"), part))
      }
    _ => fields.push((Literal("<call>"), callable))
  }
  match members {
    Object(entries) =>
      for entry in entries {
        fields.push(entry)
      }
    _ => ()
  }
  Object(fields)
}

///|
/// The `values` entries a body DECLARES, without the `var N = N || {}`
/// each `namespace N` block is lowered to. Counted as a value, a namespace
/// holding only `namespace Types { interface I {} }` read as instantiated,
/// and its empty object shadowed a `declare const` of the same name.
///
/// The parser records the lowering as one `any` entry per namespace
/// block, and a written `declare const N: any` is the same entry, so the
/// two are told apart by COUNT rather than by shape: one `any` entry named
/// `N` is dropped per `namespace N` block. A real `const N: T` keeps its
/// type and is never dropped, and a real `const N: any` beside a
/// type-only `namespace N` survives as the one entry left over.
fn declared_values(body : @ast.TsModule) -> Array[@ast.TsValueDecl] {
  let lowered : Map[String, Int32] = Map([])
  for n in body.namespaces {
    lowered[n.name] = lowered.get(n.name).unwrap_or(0) + 1
  }
  let out : Array[@ast.TsValueDecl] = []
  for v in body.values {
    let left = lowered.get(v.name).unwrap_or(0)
    if left > 0 && v.type_ is Any {
      lowered[v.name] = left - 1
      continue
    }
    out.push(v)
  }
  out
}

///|
/// Whether a namespace body declares anything that exists at run time,
/// which is what gives the namespace a value.
fn namespace_is_instantiated(body : @ast.TsModule) -> Bool {
  !declared_values(body).is_empty() ||
  !body.funcs.is_empty() ||
  !body.imports.is_empty() ||
  !body.classes.is_empty() ||
  !body.enums.is_empty() ||
  body.namespaces.iter().any(fn(n) { namespace_is_instantiated(n.module_) })
}

///|
/// The VALUE an imported namespace stands for: an object of its members.
/// `import { util } from "./util"` gave `util` no type at all, so every
/// `util.x` was `any` — zod's `util.assertNever(effect)` could not end a
/// path, and `const s: string = util.n` was silent.
///
/// A member whose type names a type declared INSIDE the namespace stays
/// `any`: the importer would resolve that bare name in its own scope,
/// where it means something else or nothing, and a wrong type is the
/// direction that invents findings. Whether a member is `export`ed is not
/// recorded in the AST, which only ever makes an unexported `N.x` read as
/// legal.
fn namespace_value_type(body : @ast.TsModule) -> @ast.TsType {
  let local_types : Array[String] = []
  for i in body.interfaces {
    local_types.push(i.name)
  }
  for a in body.type_aliases {
    local_types.push(a.name)
  }
  for c in body.classes {
    local_types.push(c.name)
  }
  for e in body.enums {
    local_types.push(e.name)
  }
  for n in body.namespaces {
    local_types.push(n.name)
  }
  fn mentions_local(t : @ast.TsType) -> Bool {
    if local_types.is_empty() {
      return false
    }
    let flat = "\{t}".replace_all(old=" ", new="").replace_all(old="\n", new="")
    local_types
    .iter()
    .any(fn(n) {
      flat.contains("Named(\"" + n + "\")") ||
      flat.contains("Applied(\"" + n + "\",")
    })
  }

  // Every runtime member a body can declare. A `declare function` lives
  // in `imports` (every function an ambient body declares, so React's
  // `declare namespace React { function useState… }` had none), and a
  // class, an enum or an instantiated nested namespace is a member too:
  // left out, `N.Inner.x` read as a property `N` does not have, where
  // `any` loses nothing.
  let names : Array[String] = []
  let seen : Map[String, Unit] = Map([])
  fn add(n : String) {
    if !seen.contains(n) {
      seen[n] = ()
      names.push(n)
    }
  }

  for v in body.values {
    add(v.name)
  }
  for f in body.funcs {
    add(f.name)
  }
  for i in body.imports {
    add(i.name)
  }
  for c in body.classes {
    add(c.name)
  }
  for e in body.enums {
    add(e.name)
  }
  for n in body.namespaces {
    if namespace_is_instantiated(n.module_) {
      add(n.name)
    }
  }
  let fields : Array[(@ast.TsType, @ast.TsType)] = []
  for n in names {
    let t = match local_value_type(body, n) {
      Some(t) if !mentions_local(t) => t
      _ => @ast.TsType::Any
    }
    fields.push((@ast.TsType::Literal(n), t))
  }
  @ast.TsType::Object(fields)
}

///|
/// `const NAME = (x: T): x is U => …` — how effect writes a guard — is in
/// `values` as `Any` (no annotation), so an importer saw no predicate at
/// all. Only a predicate return is taken, and its PARAMETERS are `any`:
/// an arrow's own `<A>` is not in the AST, so the written parameter types
/// could carry unbound names into every argument check of every call.
fn arrow_const_predicate_type(
  module_ : @ast.TsModule,
  name : String,
) -> @ast.TsType? {
  for stmt in module_.top_level_stmts {
    match stmt {
      Const(Ident(n), Any, ArrowFunc(params, TypePredicate(p, t), _, _)) if n ==
        name =>
        return Some(Func(guard_param_slots(params), TypePredicate(p, t)))
      // `export const isUnion = makeGuard("Union")` — see
      // `@checker.factory_guard_predicate`.
      Const(Ident(n), Any, init) if n == name =>
        match @checker.factory_guard_predicate(module_, init) {
          Some((params, p, t)) =>
            return Some(Func(guard_param_slots(params), TypePredicate(p, t)))
          None => ()
        }
      _ => ()
    }
  }
  None
}

///|
/// The parameter slots of a guard read as a value: each one `any`, and an
/// optional or defaulted one `any | undefined`, the spelling the arity rule
/// reads as omittable (a bare `any` reads as required). excalidraw's
/// `isBindingElement = <T>(element?: T | null, includeLocked = true): element
/// is … =>` was "expected 2 argument(s), got 1" at every one-argument call.
fn guard_param_slots(params : Array[@ast.TsParam]) -> Array[@ast.TsType] {
  params.map(fn(param) {
    if param.is_rest {
      @ast.TsType::Rest(Array(Any))
    } else if param.is_optional || param.default is Some(_) {
      @ast.TsType::Union([Any, Undefined])
    } else {
      @ast.TsType::Any
    }
  })
}

///|
/// True when `local_` names a function `module_` declares more than once.
///
/// It takes the DECLARING module, which is what `exported_value_site`
/// returns. It used to take the module an import NAMES and look only at
/// that module's own declarations, so an overload set re-exported through
/// a barrel (`export * from "./integer.js"`, how drizzle's `sqlite-core`
/// publishes `integer`) read as a single function, lost its `@overloads:`
/// marker, and was judged by the every-member arity rule a union-typed
/// VALUE takes — "expected at least 2 argument(s)" on `integer("id")`,
/// which the direct `columns/integer` import accepted.
fn declares_overload_set(module_ : ParsedMtscModule, local_ : String) -> Bool {
  let mut n = 0
  for f in module_.module_.funcs {
    if f.name == local_ {
      n = n + 1
    }
  }
  // A `.d.ts` declares its overloads with `declare function`, which the
  // parser keeps in `imports`.
  for imp in module_.module_.imports {
    if imp.name == local_ {
      n = n + 1
    }
  }
  n > 1
}

///|
/// True when `ty` can narrow: a predicate-returning callable, generic or
/// not, or an object type whose call signatures include one.
fn is_predicate_value_type(ty : @ast.TsType) -> Bool {
  match ty {
    Func(_, TypePredicate(_, _)) => true
    GenericFunc(_, _, inner) => is_predicate_value_type(inner)
    Object(entries) =>
      entries.iter().any(fn(e) { is_predicate_value_type(e.1) })
    _ => false
  }
}

///|
/// The import that binds `local_name` in `module_`, as (specifier, the name
/// it imports): `Some("default")` for a default import, `None` for a
/// namespace import. A type-only import binds no value and is skipped.
fn graph_import_binding(
  module_ : ParsedMtscModule,
  local_name : String,
) -> (String, String?)? {
  for import_ in module_.module_block.imports {
    if import_.type_only {
      continue
    }
    if import_.default_binding == Some(local_name) {
      return Some((import_.module_spec, Some("default")))
    }
    if import_.namespace_binding == Some(local_name) {
      return Some((import_.module_spec, None))
    }
    for index, binding in import_.named_bindings {
      let type_only = index < import_.named_type_only.length() &&
        import_.named_type_only[index]
      if binding.1 == local_name && !type_only {
        return Some((import_.module_spec, Some(binding.0)))
      }
    }
  }
  None
}

///|
/// The value `module_` exports as `export_name`, following value
/// re-exports: the module that DECLARES it, the name it has there, and its
/// type. The type is written in that module's scope — its bare `I` means
/// the `I` it declares or imports — so the checker reads it there (see the
/// `@value-origin:` marker in `graph_import_globals`), and a fact about the
/// declaration itself (is it an overload set?) has to be asked of that
/// module too, under that name, since a re-export can rename it.
fn exported_value_site(
  module_ : ParsedMtscModule,
  export_name : String,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  seen : Array[(String, String)],
) -> (ParsedMtscModule, String, @ast.TsType)? {
  for item in seen {
    if item.0 == module_.source.path && item.1 == export_name {
      return None
    }
  }
  let next_seen : Array[(String, String)] = []
  for item in seen {
    next_seen.push(item)
  }
  next_seen.push((module_.source.path, export_name))
  for export_ in module_.module_block.exports {
    if export_.export_name == export_name {
      match local_value_type(module_.module_, export_.local_name) {
        Some(t) => return Some((module_, export_.local_name, t))
        None => ()
      }
      // `import { n } from "./a"; export { n }` exports an import binding,
      // which has no declaration here: the value is the one the import
      // names, in ITS module. A namespace import has no value type to
      // follow (`ns.k` is not modelled).
      match graph_import_binding(module_, export_.local_name) {
        Some((spec, Some(imported))) =>
          match find_graph_target(edges, module_.source.path, spec) {
            Some(path) =>
              match find_graph_module(modules, path) {
                Some(target) =>
                  return exported_value_site(
                    target, imported, modules, edges, next_seen,
                  )
                None => return None
              }
            None => return None
          }
        _ => return None
      }
    }
  }
  // `export { value } from "./module"` is the ordinary public-barrel style.
  // Follow only value reexports here; `export type` never introduces a
  // runtime binding for an importing module.
  for reexport_ in module_.module_block.reexports {
    if reexport_.type_only {
      continue
    }
    let target_path = match
      find_graph_target(edges, module_.source.path, reexport_.module_spec) {
      Some(path) => path
      None => continue
    }
    let target = match find_graph_module(modules, target_path) {
      Some(target) => target
      None => continue
    }
    match reexport_.kind {
      @ast.TsReExportKind::Named(items) =>
        for item in items {
          let (imported_name, reexported_name) = item
          if reexported_name == export_name {
            match
              exported_value_site(
                target, imported_name, modules, edges, next_seen,
              ) {
              Some(site) => return Some(site)
              None => ()
            }
          }
        }
      @ast.TsReExportKind::All =>
        if export_name != "default" {
          match
            exported_value_site(target, export_name, modules, edges, next_seen) {
            Some(site) => return Some(site)
            None => ()
          }
        }
      // A namespace is an object-like value with members that the lightweight
      // checker cannot faithfully describe as one static function/value type.
      @ast.TsReExportKind::Namespace(_) => ()
    }
  }
  // `import { version } from "react"` of an `export = React` module names
  // a MEMBER of the assigned value (`esModuleInterop`). A member that is an
  // overload set — a `Union` whose parts are all signatures — would arrive
  // with no `@overloads:` marker, which the checker reads as a union-typed
  // value every member must accept, so it binds as `any`. A union-typed
  // VALUE (`const mode: "dev" | "prod"`) is an ordinary member, and it was
  // read as absent.
  if export_name != "default" &&
    module_.module_block.has_export_equals &&
    mtsc_is_declaration_file(module_.source.path) {
    match exported_value_site(module_, "default", modules, edges, next_seen) {
      Some((declarer, _, Object(entries))) => {
        let found = entries.filter(fn(e) {
          e.0 is Literal(k) && k == export_name
        })
        if found.length() == 1 {
          let value_type = match found[0].1 {
            Union(parts) if parts
              .iter()
              .all(fn(t) {
                t is (Func(_, _) | GenericFunc(_, _, _) | CallableMeta(_, _))
              }) => @ast.TsType::Any
            t => t
          }
          return Some((declarer, export_name, value_type))
        }
      }
      _ => ()
    }
  }
  None
}

///|
/// The module `spec` names from `importer`, when the graph holds it.
fn graph_target_module(
  importer : ParsedMtscModule,
  spec : String,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
) -> ParsedMtscModule? {
  match find_graph_target(edges, importer.source.path, spec) {
    Some(path) => find_graph_module(modules, path)
    None => None
  }
}

///|
/// The value names `module_` exports, local exports first, then its
/// re-exports in order, following `export *`. `export *` does not carry
/// `default`, as in ECMAScript, so only the outermost module contributes
/// one.
fn graph_value_export_names(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  seen : Map[String, Unit],
  out : Array[String],
  present : Map[String, Unit],
  include_default : Bool,
) -> Unit {
  if seen.contains(module_.source.path) {
    return
  }
  seen[module_.source.path] = ()
  fn add(name : String) {
    if (include_default || name != "default") && !present.contains(name) {
      present[name] = ()
      out.push(name)
    }
  }

  for export_ in module_.module_block.exports {
    add(export_.export_name)
  }
  for reexport_ in module_.module_block.reexports {
    if reexport_.type_only {
      continue
    }
    match reexport_.kind {
      @ast.TsReExportKind::Named(items) =>
        for item in items {
          add(item.1)
        }
      @ast.TsReExportKind::Namespace(name) => add(name)
      @ast.TsReExportKind::All =>
        match
          graph_target_module(module_, reexport_.module_spec, modules, edges) {
          Some(target) =>
            graph_value_export_names(
              target, modules, edges, seen, out, present, false,
            )
          None => ()
        }
    }
  }
}

///|
/// The module whose NAMESPACE OBJECT `module_` exports as `export_name`:
/// `export * as name from "./m"` (effect's `index.ts` exports every module
/// that way), or an `import * as ns` binding exported by name
/// (`import * as z from "./external"; export { z }`, zod's spelling),
/// followed through named re-exports, `export *` and import bindings. A
/// local declaration of the name answers first, and is not one.
fn graph_namespace_export_target(
  module_ : ParsedMtscModule,
  export_name : String,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  depth : Int32,
) -> ParsedMtscModule? {
  if depth > 8 {
    return None
  }
  for export_ in module_.module_block.exports {
    if export_.export_name != export_name {
      continue
    }
    if local_value_type(module_.module_, export_.local_name) is Some(_) {
      return None
    }
    match graph_import_binding(module_, export_.local_name) {
      Some((spec, None)) =>
        return graph_target_module(module_, spec, modules, edges)
      Some((spec, Some(imported))) =>
        match graph_target_module(module_, spec, modules, edges) {
          Some(target) =>
            return graph_namespace_export_target(
              target,
              imported,
              modules,
              edges,
              depth + 1,
            )
          None => return None
        }
      None => return None
    }
  }
  for reexport_ in module_.module_block.reexports {
    if reexport_.type_only {
      continue
    }
    let target = match
      graph_target_module(module_, reexport_.module_spec, modules, edges) {
      Some(t) => t
      None => continue
    }
    match reexport_.kind {
      @ast.TsReExportKind::Namespace(name) =>
        if name == export_name {
          return Some(target)
        }
      @ast.TsReExportKind::Named(items) =>
        for item in items {
          if item.1 == export_name {
            match
              graph_namespace_export_target(
                target,
                item.0,
                modules,
                edges,
                depth + 1,
              ) {
              Some(m) => return Some(m)
              None => ()
            }
          }
        }
      // `export *` answers only where no explicit re-export does, the
      // precedence `graph_exported_type` follows (second pass below).
      @ast.TsReExportKind::All => ()
    }
  }
  if export_name == "default" {
    return None
  }
  for reexport_ in module_.module_block.reexports {
    if reexport_.type_only || !(reexport_.kind is @ast.TsReExportKind::All) {
      continue
    }
    match graph_target_module(module_, reexport_.module_spec, modules, edges) {
      Some(target) =>
        match
          graph_namespace_export_target(
            target,
            export_name,
            modules,
            edges,
            depth + 1,
          ) {
          Some(m) => return Some(m)
          None => ()
        }
      None => ()
    }
  }
  None
}

///|
/// A module's namespace object as a value: one member per value export,
/// typed where it is DECLARED, and the declaring module of each member, so
/// the checker reads a member's type through that module's renames (the
/// per-member form of `@value-origin:`).
///
/// An overload set is one member per signature, which is how an object
/// type literal holds overloaded methods. A member whose type this cannot
/// compute — a class (a class value is `any` here), an enum, a nested
/// namespace, an export from outside the graph — is not listed, and the
/// `[k: string]: any` signature makes it read as unknown rather than
/// absent. The cost is a missed TS2339 on a typo'd member, which is the
/// affordable direction.
///
/// Cached per module for one graph check: effect's modules each import
/// several large namespaces (`import * as core`), and building one is a
/// pass over every export.
fn graph_namespace_object(
  target : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  cache : Map[String, (@ast.TsType, Array[(String, String)])],
) -> (@ast.TsType, Array[(String, String)]) {
  match cache.get(target.source.path) {
    Some(hit) => return hit
    None => ()
  }
  // `import * as React from "react"` of an `export = React` module is the
  // ASSIGNED value — what `esModuleInterop` makes of a CommonJS module's
  // namespace import — so its members are that value's.
  if target.module_block.has_export_equals &&
    mtsc_is_declaration_file(target.source.path) {
    match exported_value_site(target, "default", modules, edges, []) {
      Some((declarer, _, Object(entries))) => {
        let origins : Array[(String, String)] = []
        for entry in entries {
          match entry.0 {
            Literal(k) => origins.push((k, declarer.source.path))
            _ => ()
          }
        }
        let fields = entries.filter(fn(e) { !(e.0 is Literal("<call>")) })
        fields.push((String_, Any))
        let value = (@ast.TsType::Object(fields), origins)
        cache[target.source.path] = value
        return value
      }
      _ => ()
    }
  }
  let names : Array[String] = []
  graph_value_export_names(
    target,
    modules,
    edges,
    Map([]),
    names,
    Map([]),
    true,
  )
  let fields : Array[(@ast.TsType, @ast.TsType)] = []
  let origins : Array[(String, String)] = []
  let typed : Map[String, Unit] = Map([])
  for name in names {
    match exported_value_site(target, name, modules, edges, []) {
      Some((declarer, declared_name, type_)) => {
        // Only a DECLARATION file's export is a written type. A `.ts`
        // source's unannotated `export const` is the parser's coarse
        // inference — an erased `as const` widens to `string`, an arrow's
        // own `<A>` is not in the AST — and typing those members of
        // effect's `import * as core` put 311 false positives on its own
        // sources, every one a coarse answer the namespace object had been
        // hiding as `any`. A package's `.d.ts`, which is what an
        // application's namespace import reaches, says what it means.
        if type_ is Any || !mtsc_is_declaration_file(declarer.source.path) {
          continue
        }
        for sig in namespace_member_signatures(declarer, declared_name, type_) {
          fields.push((Literal(name), sig))
        }
        origins.push((name, declarer.source.path))
        typed[name] = ()
      }
      None => ()
    }
  }
  // When every name the namespace can hold is known, a member this could
  // not type is still a member: it is listed as `any`, and the
  // `[k: string]: any` signature goes, so a typo'd member is TS2339 the way
  // tsc reports it (`z.objectt`, `Effect.succed`, `Y.encodeStateAsUpdat`).
  // While any name could come from somewhere this does not see, the
  // signature stays and an unlisted member reads as unknown.
  if graph_namespace_names_closed(target, modules, edges, Map([])) {
    for name in names {
      if !typed.contains(name) {
        fields.push((Literal(name), Any))
      }
    }
  } else {
    fields.push((String_, Any))
  }
  let value = (@ast.TsType::Object(fields), origins)
  cache[target.source.path] = value
  value
}

///|
/// Whether `graph_value_export_names` lists every value name `module_`'s
/// namespace object holds. Only a declaration file's export list is read
/// that way: a `.ts` source can export through shapes the list does not
/// enumerate. It is open when the module assigns its whole value
/// (`export =`), and when an `export *` reaches a module the graph does
/// not hold, since that module's names are unknown. A named re-export of
/// an unloaded module only loses a TYPE, so it does not open the list.
///
/// A module augmentation can add a value export (`declare module "pk" {
/// export const added: string }` makes `P.added` legal), so EVERY module
/// along the `export *` closure must be one no augmentation can name:
/// `declare module "./base" { export const added: string }` adds `added`
/// to a barrel that does `export * from "./base"`, and checking the
/// barrel alone reported that legal member as missing.
fn graph_namespace_names_closed(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  seen : Map[String, Unit],
) -> Bool {
  if seen.contains(module_.source.path) {
    return true
  }
  seen[module_.source.path] = ()
  if !mtsc_is_declaration_file(module_.source.path) ||
    module_.module_block.has_export_equals ||
    graph_module_may_be_augmented(module_, modules, edges) {
    return false
  }
  for reexport_ in module_.module_block.reexports {
    if reexport_.type_only {
      continue
    }
    match reexport_.kind {
      @ast.TsReExportKind::All =>
        match
          graph_target_module(module_, reexport_.module_spec, modules, edges) {
          Some(target) =>
            if !graph_namespace_names_closed(target, modules, edges, seen) {
              return false
            }
          None => return false
        }
      _ => ()
    }
  }
  true
}

///|
/// Whether some `declare module "spec" { … }` in the program could add
/// names to `target`. An augmentation can add a VALUE export (`declare
/// module "pk" { export const added: string }` makes `P.added` legal), so
/// such a module's namespace object stays open.
///
/// The question is whether `spec` can name `target`, and every way it can
/// is taken as a yes: an edge for that spelling from the declaring module
/// that leads to `target`; a relative spelling whose path is `target`'s; a
/// spelling some importer uses to reach `target`; and a bare spelling of
/// `target`'s package (`effect/Effect` augments a file reached as
/// `./Effect.js`). What it must not do is count every ambient module:
/// `@types/node` declares `declare module "assert"` and fifty siblings,
/// and project mode loads it whenever it is installed.
fn graph_module_may_be_augmented(
  target : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
) -> Bool {
  let target_specs : Map[String, Unit] = Map([])
  for e in edges {
    if e.targetPath == target.source.path {
      target_specs[e.moduleSpecifier] = ()
    }
  }
  let target_stem = module_path_stem(target.source.path)
  for m in modules {
    for aug in m.module_.module_augmentations {
      let spec = aug.0
      match find_graph_target(edges, m.source.path, spec) {
        Some(path) => if path == target.source.path { return true }
        None =>
          if spec.has_prefix(".") {
            let dir = match m.source.path.rev_find("/") {
              Some(i) => m.source.path[:i].to_owned()
              None => "."
            }
            let joined = module_path_stem(
              normalize_module_path(dir + "/" + spec),
            )
            if stems_may_match(joined, target_stem) {
              return true
            }
          } else if target_specs.contains(spec) ||
            spec_names_package_of(spec, target.source.path) {
            return true
          }
      }
    }
  }
  false
}

///|
/// `path` without a module extension and without a trailing `/index`, so
/// `./x.js`, `./x`, `x.d.ts` and `x/index.d.ts` compare equal.
fn module_path_stem(path : String) -> String {
  let mut p = path
  for
    ext in [
      ".d.ts", ".d.cts", ".d.mts", ".tsx", ".ts", ".cts", ".mts", ".jsx", ".js",
      ".cjs", ".mjs",
    ] {
    if p.has_suffix(ext) {
      p = p[:p.length() - ext.length()].to_owned()
      break
    }
  }
  if p.has_suffix("/index") {
    p = p[:p.length() - "/index".length()].to_owned()
  }
  p
}

///|
/// `.` and `..` segments resolved, so `a/b/../c` is `a/c`.
fn normalize_module_path(path : String) -> String {
  let out : Array[String] = []
  let absolute = path.has_prefix("/")
  for seg in path.split("/") {
    let seg = seg.to_owned()
    if seg == "" || seg == "." {
      continue
    }
    if seg == ".." && out.length() > 0 && out[out.length() - 1] != ".." {
      let _ = out.pop()
    } else {
      out.push(seg)
    }
  }
  (if absolute { "/" } else { "" }) + out.join("/")
}

///|
/// Two stems name one file when they are equal, or when one is a suffix of
/// the other at a `/` boundary: a module path can be held absolute in one
/// place and relative to the project in another.
fn stems_may_match(a : String, b : String) -> Bool {
  a == b || a.has_suffix("/" + b) || b.has_suffix("/" + a)
}

///|
/// Whether bare `spec` names the package `path` lies in: `effect/Effect`
/// and `effect` both name `…/node_modules/effect/…`, and `react` names
/// `…/node_modules/@types/react/…` too.
fn spec_names_package_of(spec : String, path : String) -> Bool {
  let segs : Array[String] = spec
    .split("/")
    .map(fn(s) { s.to_owned() })
    .collect()
  if segs.length() == 0 || segs[0] == "" {
    return false
  }
  let pkg = if segs[0].has_prefix("@") && segs.length() > 1 {
    segs[0] + "/" + segs[1]
  } else {
    segs[0]
  }
  let types_pkg = if pkg.has_prefix("@") {
    "@types/" + pkg[1:].to_owned().replace(old="/", new="__")
  } else {
    "@types/" + pkg
  }
  path.contains("node_modules/" + pkg + "/") ||
  path.contains("node_modules/" + types_pkg + "/")
}

///|
/// The fields one namespace member contributes. An object type literal
/// holds an overloaded method as one field per signature, and the method
/// call path reads overloads only in that shape, so an overload set (a
/// `Union` of signatures) and a callable object with nothing BUT call
/// signatures — how effect's `dual` APIs are declared, `{ (that): (self)
/// => R; (self, that): R }` — are each spread into one field per
/// signature. Kept whole, `Equal.equals(a, b)` was judged against the
/// first signature alone: "expected 1 argument(s), got 2".
///
/// A checking parse holds a generic call signature as a `GenericFunc`, and
/// the method call path selects among overload fields only when each is a
/// plain signature, so a spread signature is the `Func` inside: the shape
/// these fields have always had.
fn namespace_member_signatures(
  declarer : ParsedMtscModule,
  declared_name : String,
  type_ : @ast.TsType,
) -> Array[@ast.TsType] {
  match type_ {
    Union(parts) if declares_overload_set(declarer, declared_name) => parts
    Object(entries) if entries.length() > 1 &&
      entries.iter().all(fn(e) { e.0 is Literal("<call>") }) =>
      entries.map(fn(e) {
        match e.1 {
          GenericFunc(_, _, inner) => inner
          other => other
        }
      })
    _ => [type_]
  }
}

///|
/// Bind `local_name` to `target`'s namespace object (see
/// `graph_namespace_object`).
fn push_graph_namespace_binding(
  globals : Array[(String, @ast.TsType)],
  local_name : String,
  target : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  cache : Map[String, (@ast.TsType, Array[(String, String)])],
) -> Unit {
  let (type_, origins) = graph_namespace_object(target, modules, edges, cache)
  globals.push((local_name, type_))
  for origin in origins {
    globals.push(
      (
        "@value-origin-member:" + local_name + "\u{0}" + origin.0,
        Named(origin.1),
      ),
    )
  }
  // `Predicate.isObject(u)` narrows through the namespace — effect calls
  // nearly every guard that way. Its PREDICATE exports are published
  // under an `@ns:` key the narrowing reads first (see
  // `apply_method_type_predicate_narrowing`).
  for export_ in target.module_block.exports {
    match local_value_type(target.module_, export_.local_name) {
      Some(t) if is_predicate_value_type(t) => {
        // The type is written in the TARGET's scope: its bare
        // `Success` means the target's own, which in the importer is
        // reached as `ns.Success`.
        let renames : Map[String, String] = Map([])
        for i in target.module_.interfaces {
          renames[i.name] = local_name + "." + i.name
        }
        for a in target.module_.type_aliases {
          renames[a.name] = local_name + "." + a.name
        }
        for c in target.module_.classes {
          renames[c.name] = local_name + "." + c.name
        }
        globals.push(
          (
            "@ns:" + local_name + "." + export_.export_name,
            @checker.rename_type_refs(t, renames),
          ),
        )
      }
      _ => ()
    }
  }
}

///|
/// Whether `module_`'s `export_name` may come from a module OUTSIDE the
/// checked graph: a value re-export that could provide the name, whose
/// target has no edge (a bare package the loader did not follow, a
/// relative file that is not there, an import the host skipped) or was
/// never loaded. tsc binds such an alias to an unknown symbol and reports
/// nothing on the importer, so `exported_value_site` coming back empty is
/// not, on its own, a missing export.
fn export_may_come_from_outside(
  module_ : ParsedMtscModule,
  export_name : String,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  seen : Array[(String, String)],
) -> Bool {
  for item in seen {
    if item.0 == module_.source.path && item.1 == export_name {
      return false
    }
  }
  let next_seen = seen.copy()
  next_seen.push((module_.source.path, export_name))
  // A local `export { n }` of an import binding comes from wherever the
  // import does — `import { n } from "ext-pkg"; export { n }` is the same
  // fact as `export { n } from "ext-pkg"`, and a namespace import is a
  // value this checker does not model at all.
  for export_ in module_.module_block.exports {
    if export_.export_name != export_name {
      continue
    }
    if local_value_type(module_.module_, export_.local_name) is Some(_) {
      return false
    }
    match graph_import_binding(module_, export_.local_name) {
      Some((spec, imported)) => {
        let target = match find_graph_target(edges, module_.source.path, spec) {
          Some(path) => find_graph_module(modules, path)
          None => None
        }
        return match (target, imported) {
          (None, _) | (_, None) => true
          (Some(target), Some(name)) =>
            export_may_come_from_outside(
              target, name, modules, edges, next_seen,
            )
        }
      }
      None => return false
    }
  }
  for reexport_ in module_.module_block.reexports {
    if reexport_.type_only {
      continue
    }
    // The name this re-export would ask its target for, or `None` when it
    // cannot provide `export_name` at all.
    let asked = match reexport_.kind {
      @ast.TsReExportKind::Named(items) => {
        let mut found : String? = None
        for item in items {
          if item.1 == export_name {
            found = Some(item.0)
            break
          }
        }
        found
      }
      @ast.TsReExportKind::All =>
        if export_name == "default" {
          None
        } else {
          Some(export_name)
        }
      @ast.TsReExportKind::Namespace(_) => None
    }
    guard asked is Some(asked_name) else { continue }
    let target = match
      find_graph_target(edges, module_.source.path, reexport_.module_spec) {
      Some(path) => find_graph_module(modules, path)
      None => None
    }
    match target {
      None => return true
      Some(target) =>
        if export_may_come_from_outside(
            target, asked_name, modules, edges, next_seen,
          ) {
          return true
        }
    }
  }
  false
}

///|
/// The last index built over a module list / an edge list, reused while
/// the same array (by identity, at the same length) is asked about.
///
/// Both lookups used to be a linear scan per call, and they are called per
/// import, per re-export hop and per checked module: on univer's 58-package
/// graph that is tens of thousands of modules and edges scanned for every
/// `@univerjs/core` import of every file. One graph check hands the same
/// two arrays to every helper, so a single slot is enough; a caller with
/// different arrays (or one that appended to them) gets a fresh index, so
/// the answer is always the linear scan's — first match wins.
let graph_module_index : Array[
  (Array[ParsedMtscModule], Int32, Map[String, ParsedMtscModule]),
] = []

///|
let graph_edge_index : Array[
  (Array[MtscModuleEdge], Int32, Map[String, String]),
] = []

///|
fn find_graph_module(
  modules : Array[ParsedMtscModule],
  path : String,
) -> ParsedMtscModule? {
  if graph_module_index.length() == 1 {
    let (arr, len, index) = graph_module_index[0]
    if physical_equal(arr, modules) && len == modules.length() {
      return index.get(path)
    }
  }
  let index : Map[String, ParsedMtscModule] = Map([])
  for module_ in modules {
    if !index.contains(module_.source.path) {
      index[module_.source.path] = module_
    }
  }
  graph_module_index.clear()
  graph_module_index.push((modules, modules.length(), index))
  index.get(path)
}

///|
fn find_graph_target(
  edges : Array[MtscModuleEdge],
  importer_path : String,
  module_specifier : String,
) -> String? {
  let key = importer_path + "\u{0}" + module_specifier
  if graph_edge_index.length() == 1 {
    let (arr, len, index) = graph_edge_index[0]
    if physical_equal(arr, edges) && len == edges.length() {
      return index.get(key)
    }
  }
  let index : Map[String, String] = Map([])
  for edge in edges {
    let k = edge.importerPath + "\u{0}" + edge.moduleSpecifier
    if !index.contains(k) {
      index[k] = edge.targetPath
    }
  }
  graph_edge_index.clear()
  graph_edge_index.push((edges, edges.length(), index))
  index.get(key)
}

///|
/// `graph_exposed_type_names(m, …, "", 0)` per module path, for the
/// duration of one graph check (`collect_parsed_graph_issues` clears it).
/// What a module exposes does not depend on who imports it, and every
/// checked module asks again about the same barrels.
let graph_exposed_cache : Map[String, Array[(String, String, String)]] = Map([])

///|
fn graph_exposed_types(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
) -> Array[(String, String, String)] {
  match graph_exposed_cache.get(module_.source.path) {
    Some(cached) => return cached
    None => ()
  }
  let out : Array[(String, String, String)] = []
  graph_exposed_type_names(module_, modules, edges, {}, out, "", 0)
  graph_exposed_cache[module_.source.path] = out
  out
}

///|
/// `graph_named_import_aliases(m, …)` per module path, for one graph check.
let graph_import_alias_cache : Map[String, Array[(String, String, String)]] = Map([],
)

///|
fn is_local_module_specifier(module_specifier : String) -> Bool {
  // `.` and `..` are relative too — a package's own modules reach their
  // barrel with `from "."`. Missing them here makes the graph edge for
  // that import invisible to the checker, so every type the barrel
  // re-exports reads as unresolved.
  module_specifier == "." ||
  module_specifier == ".." ||
  module_specifier.has_prefix("./") ||
  module_specifier.has_prefix("../") ||
  module_specifier.has_prefix("/")
}

///|
/// The type names a module exposes, as `(exposed, bare)` pairs: its own
/// type declarations, plus whatever its re-exports expose — `export *`
/// unchanged, `export { A as B }` under the new name, and
/// `export * as ns` under `ns.`. `bare` is the key the resolver ingested
/// the declaration at (`graph_type_modules` ingests every reachable module
/// at bare names), so the pair is all `alias_namespace_import_types`
/// needs. Every declared type counts, exported or not: an unexported one
/// is already reachable at its bare name, so the qualified key adds no
/// declaration the resolver does not already hold.
fn graph_exposed_type_names(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  seen : Map[String, Unit],
  out : Array[(String, String, String)],
  prefix : String,
  depth : Int32,
) -> Unit {
  if depth > 8 || seen.contains(prefix + "|" + module_.source.path) {
    return
  }
  seen[prefix + "|" + module_.source.path] = ()
  let m = module_.module_
  for i in m.interfaces {
    out.push((prefix + i.name, i.name, module_.source.path))
  }
  for c in m.classes {
    out.push((prefix + c.name, c.name, module_.source.path))
  }
  for a in m.type_aliases {
    out.push((prefix + a.name, a.name, module_.source.path))
  }
  for e in m.enums {
    out.push((prefix + e.name, e.name, module_.source.path))
  }
  // An `export =` module exposes its assigned value's namespace types at
  // the top: `import * as express from "express"` reads `express.Request`
  // as that namespace's `Request`.
  match export_equals_namespaces(module_) {
    Some((assigned, bodies)) =>
      for body in bodies {
        for i in body.interfaces {
          out.push(
            (prefix + i.name, assigned + "." + i.name, module_.source.path),
          )
        }
        for a in body.type_aliases {
          out.push(
            (prefix + a.name, assigned + "." + a.name, module_.source.path),
          )
        }
        for c in body.classes {
          out.push(
            (prefix + c.name, assigned + "." + c.name, module_.source.path),
          )
        }
        for e in body.enums {
          out.push(
            (prefix + e.name, assigned + "." + e.name, module_.source.path),
          )
        }
      }
    None => ()
  }
  for re in module_.module_block.reexports {
    let target = match
      find_graph_target(edges, module_.source.path, re.module_spec) {
      Some(path) =>
        match find_graph_module(modules, path) {
          Some(t) => t
          None => continue
        }
      None => continue
    }
    match re.kind {
      @ast.TsReExportKind::All =>
        graph_exposed_type_names(
          target,
          modules,
          edges,
          seen,
          out,
          prefix,
          depth + 1,
        )
      @ast.TsReExportKind::Namespace(ns) =>
        graph_exposed_type_names(
          target,
          modules,
          edges,
          seen,
          out,
          prefix + ns + ".",
          depth + 1,
        )
      @ast.TsReExportKind::Named(items) => {
        let inner : Array[(String, String, String)] = []
        graph_exposed_type_names(
          target,
          modules,
          edges,
          {},
          inner,
          "",
          depth + 1,
        )
        for item in items {
          let (imported, exported) = item
          for pair in inner {
            if pair.0 == imported {
              out.push((prefix + exported, pair.1, pair.2))
            }
          }
        }
      }
    }
  }
}

///|
/// `(qualified, bare)` pairs for every NAMESPACE import of `module_`
/// (`import * as core from "./core"` exposes `core.X` for each type the
/// target exposes). See `alias_namespace_import_types` in the checker.
fn graph_namespace_type_aliases(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
) -> Array[(String, String, String)] {
  let out : Array[(String, String, String)] = []
  for imp in module_.module_block.imports {
    let ns = match imp.namespace_binding {
      Some(ns) => ns
      None => continue
    }
    let target = match
      find_graph_target(edges, module_.source.path, imp.module_spec) {
      Some(path) =>
        match find_graph_module(modules, path) {
          Some(t) => t
          None => continue
        }
      None => continue
    }
    for e in graph_exposed_types(target, modules, edges) {
      out.push((ns + "." + e.0, e.1, e.2))
    }
  }
  // A named or default import of a NAMESPACE export (`import { Effect }
  // from "effect"` of `export * as Effect`) is the same binding by
  // another route, and `Effect.Effect<A>` in an annotation means the type
  // that module exposes.
  for imp in module_.module_block.imports {
    if imp.type_only {
      continue
    }
    let target = match
      graph_target_module(module_, imp.module_spec, modules, edges) {
      Some(t) => t
      None => continue
    }
    let bindings : Array[(String, String)] = []
    match imp.default_binding {
      Some(local_name) => bindings.push(("default", local_name))
      None => ()
    }
    for index, binding in imp.named_bindings {
      let type_only = index < imp.named_type_only.length() &&
        imp.named_type_only[index]
      if !type_only {
        bindings.push(binding)
      }
    }
    for binding in bindings {
      let (imported, local_name) = binding
      match graph_namespace_export_target(target, imported, modules, edges, 0) {
        Some(ns_target) =>
          for e in graph_exposed_types(ns_target, modules, edges) {
            out.push((local_name + "." + e.0, e.1, e.2))
          }
        None => ()
      }
    }
  }
  for pair in graph_named_import_aliases(module_, modules, edges) {
    out.push(pair)
  }
  out
}

///|
/// `(local, bare, origin)` for every NAMED type import of `module_`.
///
/// A named import binds the local name to one module's declaration, and
/// the bare table cannot say which when two reachable modules declare the
/// name: it holds their merge. univer's `@univerjs/core` and
/// `@univerjs/protocol` both export `ICommand`, `IRange`, `ICellData` and
/// `BooleanNumber`, so `import { ICommand } from '@univerjs/core'` was asked
/// for protocol's `data` member. The triple lets the checker point the
/// local spelling at `bare@origin`, exactly as it does for `ns.X`; for a
/// name only one module declares it adds nothing the bare entry does not
/// already hold.
///
/// The binding is found through the target's EXPORT TABLE
/// (`graph_exported_type`), not through the list of every declaration
/// `graph_exposed_types` builds for namespace imports: a module may declare
/// a private `interface T` beside `export { T } from "./a"`, and the import
/// means `a.ts`'s.
fn graph_named_import_aliases(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
) -> Array[(String, String, String)] {
  match graph_import_alias_cache.get(module_.source.path) {
    Some(cached) => return cached
    None => ()
  }
  let out : Array[(String, String, String)] = []
  for imp in module_.module_block.imports {
    if imp.named_bindings.length() == 0 {
      continue
    }
    let target = match
      find_graph_target(edges, module_.source.path, imp.module_spec) {
      Some(path) =>
        match find_graph_module(modules, path) {
          Some(t) => t
          None => continue
        }
      None => continue
    }
    for binding in imp.named_bindings {
      let (imported, local_name) = binding
      match graph_exported_type(target, modules, edges, imported, 0) {
        Some((bare, origin)) => out.push((local_name, bare, origin))
        None => ()
      }
    }
  }
  graph_import_alias_cache[module_.source.path] = out
  out
}

///|
/// `graph_declaration_namespace_aliases(m, …)` per module path, for one
/// graph check.
let graph_declaration_namespace_alias_cache : Map[
  String,
  Array[(String, String, String)],
] = Map([])

///|
/// `(ns.X, bare, origin)` for EVERY namespace import of a declaration file.
///
/// The shared resolver maps `ns.X` through the CHECKED module's own
/// `import * as ns`, so a qualified name written inside another module
/// resolves only where the checked module happens to bind the same `ns` to
/// the same target, and otherwise abstains. zod's declarations are written
/// that way throughout — `string(params?: string | core.$ZodStringParams):
/// ZodString` — so an application's `z.string` was unknowable, and so was
/// every member of a zod interface that names a `core.` type. For a
/// declaration file the qualified name is a written type and resolving it
/// in its own module's terms is exact; a `.ts` source keeps the narrower
/// conflicting-only rule (see `graph_conflicting_namespace_aliases`).
fn graph_declaration_namespace_aliases(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
) -> Array[(String, String, String)] {
  match graph_declaration_namespace_alias_cache.get(module_.source.path) {
    Some(hit) => return hit
    None => ()
  }
  let out : Array[(String, String, String)] = []
  for imp in module_.module_block.imports {
    let ns = match imp.namespace_binding {
      Some(ns) => ns
      None => continue
    }
    match graph_target_module(module_, imp.module_spec, modules, edges) {
      Some(target) =>
        for e in graph_exposed_types(target, modules, edges) {
          out.push((ns + "." + e.0, e.1, e.2))
        }
      None => ()
    }
  }
  // A NAMED import of a namespace export (`import { Models } from
  // "./barrel"` of `export * as Models`) binds the same namespace by
  // another route, the case `graph_namespace_type_aliases` handles for
  // the checked module.
  for imp in module_.module_block.imports {
    if imp.type_only {
      continue
    }
    let target = match
      graph_target_module(module_, imp.module_spec, modules, edges) {
      Some(t) => t
      None => continue
    }
    for index, binding in imp.named_bindings {
      let type_only = index < imp.named_type_only.length() &&
        imp.named_type_only[index]
      if type_only {
        continue
      }
      let (imported, local_name) = binding
      match graph_namespace_export_target(target, imported, modules, edges, 0) {
        Some(ns_target) =>
          for e in graph_exposed_types(ns_target, modules, edges) {
            out.push((local_name + "." + e.0, e.1, e.2))
          }
        None => ()
      }
    }
  }
  graph_declaration_namespace_alias_cache[module_.source.path] = out
  out
}

///|
/// `(ns.X, bare, origin)` for each namespace import of `module_` whose
/// binding name the checked module also binds (`own_namespaces`, name to
/// target path) to a DIFFERENT module. See the call site.
fn graph_conflicting_namespace_aliases(
  module_ : ParsedMtscModule,
  own_namespaces : Map[String, String],
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
) -> Array[(String, String, String)] {
  let out : Array[(String, String, String)] = []
  if own_namespaces.length() == 0 {
    return out
  }
  for imp in module_.module_block.imports {
    let ns = match imp.namespace_binding {
      Some(ns) => ns
      None => continue
    }
    let theirs = match own_namespaces.get(ns) {
      Some(t) => t
      None => continue
    }
    let target_path = match
      find_graph_target(edges, module_.source.path, imp.module_spec) {
      Some(path) => path
      None => continue
    }
    if target_path == theirs {
      continue
    }
    match find_graph_module(modules, target_path) {
      Some(target) =>
        for e in graph_exposed_types(target, modules, edges) {
          out.push((ns + "." + e.0, e.1, e.2))
        }
      None => ()
    }
  }
  out
}

///|
/// The declaration `module_` exports as the TYPE `name`, as
/// `(bare, origin)`: the name it was declared under and the module that
/// declares it.
///
/// TypeScript's precedence, in order: a local export (`export interface
/// T`, `export { T }`, `export { U as T }`) — following an `export { T }`
/// of an IMPORTED `T` back to its module; a named re-export
/// (`export { T } from`); then `export *`, where a name two `export *`
/// sources provide differently is excluded from the module's exports
/// altogether. `None` for anything else — not exported, ambiguous, too
/// deep, or reached through a module the graph does not hold — and the
/// caller abstains, which leaves the bare entry: the old answer.
fn graph_exported_type(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  name : String,
  depth : Int32,
) -> (String, String)? {
  if depth > 8 {
    return None
  }
  let path = module_.source.path
  let follow = fn(spec : String, imported : String) -> (String, String)? {
    match find_graph_target(edges, path, spec) {
      Some(target_path) =>
        match find_graph_module(modules, target_path) {
          Some(t) => graph_exported_type(t, modules, edges, imported, depth + 1)
          None => None
        }
      None => None
    }
  }
  for ex in module_.module_block.exports {
    if ex.export_name != name {
      continue
    }
    if module_declares_top_level_type(module_.module_, ex.local_name) {
      return Some((ex.local_name, path))
    }
    // `import { T } from "./a"; export { T }`.
    for imp in module_.module_block.imports {
      for binding in imp.named_bindings {
        if binding.1 == ex.local_name {
          return follow(imp.module_spec, binding.0)
        }
      }
    }
    return None
  }
  for re in module_.module_block.reexports {
    match re.kind {
      @ast.TsReExportKind::Named(items) =>
        for item in items {
          if item.1 == name {
            return follow(re.module_spec, item.0)
          }
        }
      _ => ()
    }
  }
  // `export = e` exports the types of the namespace merged with `e`.
  match export_equals_namespaces(module_) {
    Some((assigned, bodies)) =>
      for body in bodies {
        if module_declares_top_level_type(body, name) {
          return Some((assigned + "." + name, path))
        }
      }
    None => ()
  }
  let mut found : (String, String)? = None
  for re in module_.module_block.reexports {
    match re.kind {
      @ast.TsReExportKind::All =>
        match follow(re.module_spec, name) {
          Some(hit) =>
            match found {
              None => found = Some(hit)
              Some(prev) => if prev != hit { return None }
            }
          None => ()
        }
      _ => ()
    }
  }
  found
}

///|
/// The namespace bodies merged with the value an `export =` module assigns
/// (`declare function e(); declare namespace e { interface Request … };
/// export = e`, which is express), with that value's name. Their types are
/// the module's type exports: `import type { Request } from "express"`
/// names `e.Request`, and the resolver ingested it under that qualified
/// key.
fn export_equals_namespaces(
  module_ : ParsedMtscModule,
) -> (String, Array[@ast.TsModule])? {
  if !module_.module_block.has_export_equals {
    return None
  }
  let assigned = match
    module_.module_block.exports
    .iter()
    .find_first(fn(e) { e.export_name == "default" }) {
    Some(e) => e.local_name
    None => return None
  }
  let bodies : Array[@ast.TsModule] = []
  for ns in module_.module_.namespaces {
    if ns.name == assigned {
      bodies.push(ns.module_)
    }
  }
  if bodies.is_empty() {
    None
  } else {
    Some((assigned, bodies))
  }
}

///|
/// True when `module_` declares `name` at its top level as a type: an
/// interface, a type alias, an enum or a class.
fn module_declares_top_level_type(
  module_ : @ast.TsModule,
  name : String,
) -> Bool {
  module_.interfaces.iter().any(fn(d) { d.name == name }) ||
  module_.type_aliases.iter().any(fn(d) { d.name == name }) ||
  module_.enums.iter().any(fn(d) { d.name == name }) ||
  module_.classes.iter().any(fn(d) { d.name == name })
}

///|
/// The type names a module's own scope declares or imports, outside its
/// `declare global` block, each mapped to `Name@<module path>`. A
/// `declare global` value typed by one of them cannot be read in a module
/// that does not reach the declaring one, and that key is never registered
/// there, so the reference stays unresolved.
fn module_scope_type_renames(
  module_ : ParsedMtscModule,
) -> (Map[String, String], Map[String, Unit]) {
  let names : Map[String, Unit] = Map([])
  let m = module_.module_
  for iface in m.interfaces {
    names[iface.name] = ()
  }
  for ta in m.type_aliases {
    names[ta.name] = ()
  }
  for c in m.classes {
    names[c.name] = ()
  }
  for e in m.enums {
    names[e.name] = ()
  }
  // The roots a qualified reference in this scope can start from: its own
  // namespaces and its namespace imports.
  let roots : Map[String, Unit] = Map([])
  for ns in m.namespaces {
    if ns.name != "<global>" {
      names[ns.name] = ()
      roots[ns.name] = ()
    }
  }
  for n in m.imported_binding_names {
    names[n] = ()
  }
  for imp in module_.module_block.imports {
    match imp.namespace_binding {
      Some(ns) => roots[ns] = ()
      None => ()
    }
  }
  let out : Map[String, String] = Map([])
  for n, _ in names {
    out[n] = n + "@" + module_.source.path
  }
  (out, roots)
}

///|
/// Collect type declarations from the caller-resolved transitive dependency
/// graph. Runtime names are deliberately not injected from these modules;
/// `graph_import_globals` remains the only path for value bindings.
fn graph_type_modules(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  keys~ : Array[String] = [],
) -> Array[@ast.TsModule] {
  let type_modules : Array[@ast.TsModule] = []
  // Each reachable module is ingested ONCE. Every import edge used to
  // push its target, so a module imported from k places was ingested k
  // times and every interface it declares was merged with itself on each
  // repeat — `extends`, index signatures and method type parameters
  // concatenated k times. On zod's `util.ts` program that was 820,000
  // self-merges and half of the whole check.
  //
  // The edge order is still walked as before, and each module is kept at
  // its LAST position in it. Later ingestion overwrites a class or alias
  // that two modules both declare (and decides which declaration's field
  // wins in a cross-module interface merge), so the last position is the
  // one that keeps every such winner what it was.
  // The walk runs on the program's integer ids: the index is built once per
  // program, and the walk itself used to hash a path at every step. For
  // every checked module that was rebuilding two path-keyed tables (13% of
  // univer core's check) and then hashing ~1,000 paths per walk (7%).
  let g = graph_reach_index(modules, edges)
  let root = match g.ids.get(module_.source.path) {
    Some(id) => id
    None => return type_modules
  }
  let visited = FixedArray::make(g.paths.length(), false)
  let order : Array[Int32] = []
  let pending : Array[Int32] = [root]
  let mut cursor = 0
  while cursor < pending.length() {
    let importer = pending[cursor]
    cursor = cursor + 1
    if visited[importer] {
      continue
    }
    visited[importer] = true
    for target in g.targets[importer] {
      order.push(target)
      pending.push(target)
    }
  }
  let last_index = FixedArray::make(g.paths.length(), -1)
  for i, t in order {
    last_index[t] = i
  }
  for i, t in order {
    if last_index[t] == i {
      match g.modules[t] {
        Some(m) => {
          type_modules.push(m.module_)
          keys.push(m.source.path)
        }
        None => ()
      }
    }
  }
  type_modules
}

///|
/// The import graph on integer ids. Every path an edge or a module names
/// gets an id; `targets` keeps each importer's edges in edge order, and
/// only targets with a parsed module, which is what the path-based walk
/// followed (`find_graph_module`'s first-match rule picks the module).
priv struct GraphReachIndex {
  ids : Map[String, Int32]
  paths : Array[String]
  modules : Array[ParsedMtscModule?]
  targets : Array[Array[Int32]]
}

///|
/// The last index built, reused while the same two arrays (by identity, at
/// the same lengths) are asked about, as `graph_module_index` is.
let graph_reach_index_cache : Array[
  (
    Array[ParsedMtscModule],
    Int32,
    Array[MtscModuleEdge],
    Int32,
    GraphReachIndex,
  ),
] = []

///|
fn graph_reach_index(
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
) -> GraphReachIndex {
  if graph_reach_index_cache.length() == 1 {
    let (ms, ml, es, el, g) = graph_reach_index_cache[0]
    if physical_equal(ms, modules) &&
      ml == modules.length() &&
      physical_equal(es, edges) &&
      el == edges.length() {
      return g
    }
  }
  let g = { ids: Map([]), paths: [], modules: [], targets: [], }
  let id_of = fn(path : String) -> Int32 {
    match g.ids.get(path) {
      Some(id) => id
      None => {
        let id = g.paths.length()
        g.ids[path] = id
        g.paths.push(path)
        g.modules.push(None)
        g.targets.push([])
        id
      }
    }
  }
  for m in modules {
    let id = id_of(m.source.path)
    if g.modules[id] is None {
      g.modules[id] = Some(m)
    }
  }
  for edge in edges {
    let from = id_of(edge.importerPath)
    let to = id_of(edge.targetPath)
    if g.modules[to] is Some(_) {
      g.targets[from].push(to)
    }
  }
  graph_reach_index_cache.clear()
  graph_reach_index_cache.push(
    (modules, modules.length(), edges, edges.length(), g),
  )
  g
}

///|
/// `skipped_imports` holds the imports a host chose not to follow, keyed
/// `importer + "\u{0}" + specifier`: they have no edge by design, so a
/// relative one is not reported as a missing local module.
fn graph_import_globals(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  skipped_imports : Map[String, Unit],
  namespace_cache : Map[String, (@ast.TsType, Array[(String, String)])],
) -> (Array[(String, @ast.TsType)], Array[String]) {
  let globals : Array[(String, @ast.TsType)] = []
  let diagnostics : Array[String] = []
  for import_ in module_.module_block.imports {
    let target_path = match
      find_graph_target(edges, module_.source.path, import_.module_spec) {
      Some(path) => path
      None => {
        if is_local_module_specifier(import_.module_spec) &&
          !skipped_imports.contains(
            module_.source.path + "\u{0}" + import_.module_spec,
          ) {
          diagnostics.push(
            "cannot resolve local module `\{import_.module_spec}`",
          )
        }
        continue
      }
    }
    let target = match find_graph_module(modules, target_path) {
      Some(target) => target
      None => {
        diagnostics.push(
          "resolved module `\{import_.module_spec}` is absent at `\{target_path}`",
        )
        continue
      }
    }
    match import_.default_binding {
      Some(local_name) =>
        match exported_value_site(target, "default", modules, edges, []) {
          // The same two markers the named-import branch below records.
          // A default import is the spelling that is USUALLY bound under
          // another name (`import ident from "./lib"`), so without the
          // `@import-generic:` marker the call never solved its type
          // parameters and `const s: string = ident({ a: 1 })` was silent
          // where the named spelling reports.
          Some((declarer, declared_name, type_)) => {
            globals.push((local_name, type_))
            globals.push(
              ("@value-origin:" + local_name, Named(declarer.source.path)),
            )
            if type_ is GenericFunc(_, _, _) {
              globals.push(("@import-generic:" + local_name, Any))
            }
            if type_ is Any {
              globals.push(("@imported:" + local_name, Any))
            }
            // `export default function f(a); export default function
            // f(a, b)` is an overload set, the same as a named one.
            if declares_overload_set(declarer, declared_name) {
              globals.push(("@overloads:" + local_name, Any))
            }
          }
          None =>
            if graph_namespace_export_target(
                target, "default", modules, edges, 0,
              )
              is Some(ns_target) {
              // `import z from "zod"` of `export default z`, where `z` is
              // the namespace object of another module.
              push_graph_namespace_binding(
                globals, local_name, ns_target, modules, edges, namespace_cache,
              )
            } else if export_may_come_from_outside(
                target,
                "default",
                modules,
                edges,
                [],
              ) {
              globals.push((local_name, Any))
              globals.push(("@imported:" + local_name, Any))
            } else if graph_exported_type(target, modules, edges, "default", 0)
              is Some(_) {
              // A default-exported type: nothing to bind as a value.
              ()
            } else if mtsc_is_declaration_file(target.source.path) {
              // A declaration file or an ambient module with no default
              // export gets a SYNTHETIC one — the module namespace object —
              // which TypeScript 7 always allows (it removed
              // `allowSyntheticDefaultImports: false`). Probed: a default
              // import of `declare module "m" {}`, of one exporting only
              // `const k`, and of a `.d.ts` package all compile, while the
              // same import of a `.ts` file with no default export is
              // TS1192. The namespace object is not modelled, so the
              // binding is untyped.
              globals.push((local_name, Any))
              globals.push(("@imported:" + local_name, Any))
            } else {
              diagnostics.push(
                "module `\{import_.module_spec}` has no default value export",
              )
            }
        }
      None => ()
    }
    // A NAMESPACE import (`import * as Predicate`) binds no value type, so
    // `Predicate.isObject(u)` narrowed nothing — effect calls nearly every
    // guard that way. Its PREDICATE exports alone are published under an
    // `@ns:` key only the narrowing reads, so no other `ns.member` access
    // changes meaning.
    match import_.namespace_binding {
      Some(ns) =>
        push_graph_namespace_binding(
          globals, ns, target, modules, edges, namespace_cache,
        )
      None => ()
    }
    for index, binding in import_.named_bindings {
      let type_only = import_.type_only ||
        (
          index < import_.named_type_only.length() &&
          import_.named_type_only[index]
        )
      if type_only {
        continue
      }
      let (imported_name, local_name) = binding
      match exported_value_site(target, imported_name, modules, edges, []) {
        Some((declarer, declared_name, type_)) => {
          let origin = declarer.source.path
          globals.push((local_name, type_))
          // The module the type is WRITTEN in. When it shares a type name
          // with another reachable module, the checker reads the type
          // through that module's own renames, so `consume(x: I)` means the
          // `I` its module imports rather than the one the importer does.
          globals.push(("@value-origin:" + local_name, Named(origin)))
          // An imported GENERIC function arrives as a binder over its raw
          // signature; this marks the binding as imported so the checker's
          // by-name call path solves it (see the `GenericFunc` arm of the
          // `Call` case in `infer_expr`).
          if type_ is GenericFunc(_, _, _) {
            globals.push(("@import-generic:" + local_name, Any))
          }
          // An imported value's `Any` is usually an exporter whose type
          // this checker could not compute (`export const identity = <A>(a:
          // A): A => a` — an arrow's own `<A>` is not in the AST), not a
          // written `any`. Rules that trust `Any` as a declaration read this.
          if type_ is Any {
            globals.push(("@imported:" + local_name, Any))
          }
          // An imported OVERLOAD set arrives as the same `Union` of
          // signatures a union-typed value is, and the two take opposite
          // arity rules (one overload must accept, against every member).
          // Locally that is told apart by the function declaration's entry
          // in `signatures`; across a module boundary this marker says it.
          if declares_overload_set(declarer, declared_name) {
            globals.push(("@overloads:" + local_name, Any))
          }
        }
        None =>
          if graph_namespace_export_target(
              target, imported_name, modules, edges, 0,
            )
            is Some(ns_target) {
            // `import { Effect } from "effect"` of `export * as Effect`.
            push_graph_namespace_binding(
              globals, local_name, ns_target, modules, edges, namespace_cache,
            )
          } else if export_may_come_from_outside(
              target,
              imported_name,
              modules,
              edges,
              [],
            ) {
            globals.push((local_name, Any))
            globals.push(("@imported:" + local_name, Any))
          } else if graph_exported_type(
              target, modules, edges, imported_name, 0,
            )
            is Some(_) {
            // `import { I } from "./x"` of an interface or type alias is
            // legal without `type` (only `verbatimModuleSyntax` asks for
            // it): there is no value to bind, and a use of `I` as a value
            // is a different error this site does not decide.
            ()
          } else {
            diagnostics.push(
              "module `\{import_.module_spec}` has no value export `\{imported_name}`",
            )
          }
      }
    }
  }
  (globals, diagnostics)
}

///|
/// JavaScript-facing graph checker. The caller supplies modules and resolved
/// import edges; this package then performs deterministic parsing, local
/// checking, and value-level import contract propagation without reading the
/// filesystem or knowing about a particular bundler.
pub(all) struct MtscGraphIssue {
  modulePath : String
  path : String
  message : String
}

///|
/// True for a `.d.ts` whose declarations are ambient — global to the
/// whole program. A declaration file that imports or exports anything is
/// a module in its own right, so its declarations stay local to it.
///
/// A file is a module when ITS OWN top level imports or exports anything.
/// That is read from two facts an ambient `declare module "x" { … }` body
/// cannot touch: the block's import list, and the `<module-syntax>` /
/// `<export-…>` markers every `export` form leaves in the file's own
/// parser (a body is parsed by a child parser, which keeps its own). The
/// block's EXPORT list is not one of them: it collects the bodies'
/// `export`s too, so a `globals.d.ts` holding any `declare module` read as
/// a module, and none of its `declare const` globals were visible.
fn is_ambient_script_module(module_ : ParsedMtscModule) -> Bool {
  if !module_.source.path.has_suffix(".d.ts") {
    return false
  }
  // A `declare module "m" { … }` body is a MODULE whatever it holds: its
  // declarations belong to `"m"`. Its virtual file carries no import or
  // export marker, so without this it read as a script and published every
  // declaration in it program-wide — `declare module "m" { const hidden:
  // number }` made `hidden` a global, and two bodies each declaring
  // `interface I` merged into one.
  if module_.source.path.has_prefix(ambient_module_root) {
    return false
  }
  if !module_.module_block.imports.is_empty() {
    return false
  }
  for gm in module_.module_.grammar_misuses {
    if gm == "<module-syntax>" ||
      gm.has_prefix("<export-value>") ||
      gm.has_prefix("<export-default>") ||
      gm.has_prefix("<export-eq>") {
      return false
    }
  }
  true
}

///|
/// Value-level bindings a module declares, in the (name, type) shape the
/// checker takes for globals.
fn module_value_bindings(
  module_ : @ast.TsModule,
) -> Array[(String, @ast.TsType)] {
  let out : Array[(String, @ast.TsType)] = []
  for value in module_.values {
    out.push((value.name, spread_objects_as_any(value.type_)))
  }
  for func in module_.funcs {
    out.push((func.name, function_value_type(func)))
  }
  for class_ in module_.classes {
    out.push((class_.name, @ast.TsType::Named(class_.name)))
  }
  for enum_ in module_.enums {
    out.push((enum_.name, @ast.TsType::Named(enum_.name)))
  }
  out
}

///|
/// `ty` with every object type that came from a SPREAD read as `any`. A
/// value's recorded type is the parser's initializer shape, which writes
/// each `...x` as a member literally named `@@spread:N`: excalidraw's
/// `MIME_TYPES = { ...STRING_MIME_TYPES, "excalidraw.svg": …,
/// ...IMAGE_MIME_TYPES } as const` was read by every importer as having
/// neither `svg` nor `text`. The spread sources are other values the
/// parser cannot see into, so the shape is unknowable here — the same
/// answer the checker's own inference gives an unenumerable spread.
fn spread_objects_as_any(ty : @ast.TsType) -> @ast.TsType {
  match ty {
    Object(fields) =>
      if fields
        .iter()
        .any(fn(f) { f.0 is Literal(k) && k.has_prefix("@@spread:") }) {
        Any
      } else {
        Object(fields.map(fn(f) { (f.0, spread_objects_as_any(f.1)) }))
      }
    Tuple(items) => Tuple(items.map(spread_objects_as_any))
    Array(inner) => Array(spread_objects_as_any(inner))
    _ => ty
  }
}

///|
/// Where the module an ambient `declare module "spec"` declares lives in
/// the program. Not a path any file can have, so it cannot collide with
/// one, and it ends in `.d.ts` so the body is parsed as declarations.
fn ambient_module_path(spec : String) -> String {
  ambient_module_root + spec + ".d.ts"
}

///|
/// The directory every `ambient_module_path` lives under.
let ambient_module_root : String = "/@ambient-module/"

///|
/// `parsed` with an export entry for every value it declares. Every
/// declaration in an ambient module body is exported, with or without
/// `export` — probed: `declare module "m" { const n: number }` imports as
/// `import { n } from "m"` with no error, and so does an unexported `const`
/// beside an exported one. Interfaces and type aliases get an entry too: a
/// NAMED type import (`import type { I } from "m"`) is resolved through the
/// export table, and without the entry it fell back to the program-wide
/// merge of every `I`, so two ambient modules each declaring `I` read as
/// one interface with both shapes.
fn with_implicit_exports(parsed : ParsedMtscModule) -> ParsedMtscModule {
  let exported : Map[String, Unit] = Map([])
  for e in parsed.module_block.exports {
    exported[e.export_name] = ()
  }
  let exports = parsed.module_block.exports.copy()
  let names : Array[String] = []
  for entry in module_value_bindings(parsed.module_) {
    names.push(entry.0)
  }
  for i in parsed.module_.interfaces {
    names.push(i.name)
  }
  for a in parsed.module_.type_aliases {
    names.push(a.name)
  }
  for name in names {
    if !exported.contains(name) {
      exported[name] = ()
      exports.push({ local_name: name, export_name: name, })
    }
  }
  { ..parsed, module_block: { ..parsed.module_block, exports, }, }
}

///|
/// The program with every AMBIENT module declaration as a module of its
/// own, and the imports that name one routed to it.
///
/// `declare module "virtual:cfg" { … }` in a script-shaped declaration file
/// declares a module, and an import of `"virtual:cfg"` reads it. Each body
/// is re-parsed from its source (`TsModule.ambient_module_sources`) as a
/// module at `ambient_module_path`, so its exports, its types and its own
/// imports go through exactly the code a real file does. Bodies declaring
/// one name in several files are concatenated, which is how TypeScript
/// merges them.
///
/// Which import reads one follows `resolveExternalModule`, and each rule was
/// probed:
/// - an EXACT ambient name wins over a file the resolver found, so a
///   `declare module "dup"` beside a real `dup` package is what `"dup"`
///   means;
/// - a PATTERN (`"*.css"`, at most one `*`) applies only when resolution
///   found nothing the program reads, and the one with the longest prefix
///   wins. `./a.css` resolves to a file the checker cannot read, which is
///   exactly where the pattern answers;
/// - a relative specifier never names an ambient module exactly (a relative
///   ambient name is an error, TS2436).
///
/// A `declare module` inside a file with its own imports or exports is an
/// AUGMENTATION of an existing module, not a declaration, and is left
/// alone here.
///
/// The third result is the virtual modules' paths. They hold declarations
/// only and nothing reports on them. The fourth is the imports a SHORTHAND
/// declaration answered (`declare module "spec";`, and patterns such as
/// `declare module "*.svg";`), as `importer \u{0} specifier`: TypeScript
/// types every import from one as `any`, so each is left without an edge
/// and counted with the host-skipped imports, which nothing reports.
fn graph_with_ambient_modules(
  parsed_modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
) -> (
  Array[ParsedMtscModule],
  Array[MtscModuleEdge],
  Map[String, Unit],
  Map[String, Unit],
) {
  let bodies : Map[String, String] = Map([])
  let order : Array[String] = []
  // The files each body came from: an import inside a body was resolved
  // relative to the file holding it, so its edge is keyed by that file.
  let origins : Map[String, Array[String]] = Map([])
  // `declare module "spec";` with no body: every import from it is untyped
  // (`any`), so an import it answers gets no edge and is not reported.
  let shorthands : Map[String, Unit] = Map([])
  for m in parsed_modules {
    if !is_ambient_script_module(m) {
      continue
    }
    for entry in m.module_.ambient_module_sources {
      let (spec, body) = entry
      if body == @ast.shorthand_ambient_module_body {
        if !shorthands.contains(spec) {
          shorthands[spec] = ()
        }
        continue
      }
      match bodies.get(spec) {
        Some(prev) => bodies[spec] = prev + "\n" + body
        None => {
          bodies[spec] = body
          order.push(spec)
        }
      }
      match origins.get(spec) {
        Some(files) => files.push(m.source.path)
        None => origins[spec] = [m.source.path]
      }
    }
  }
  let virtual_paths : Map[String, Unit] = Map([])
  let untyped : Map[String, Unit] = Map([])
  if order.length() == 0 && shorthands.length() == 0 {
    return (parsed_modules, edges, virtual_paths, untyped)
  }
  let modules = parsed_modules.copy()
  let exact : Map[String, String] = Map([])
  let patterns : Array[(String, String, String)] = []
  let targets : Map[String, String] = Map([])
  for e in edges {
    let k = e.importerPath + "\u{0}" + e.moduleSpecifier
    if !targets.contains(k) {
      targets[k] = e.targetPath
    }
  }
  // A body's own imports and re-exports (`export { n } from "dep"`),
  // carried over from the file that holds it to the virtual module.
  let body_edges : Array[MtscModuleEdge] = []
  // Shorthand declarations route like any other, to "untyped". A braced
  // body for the same name wins, since it says what the module holds.
  let untyped_target = "\u{0}untyped"
  for spec, _ in shorthands {
    if bodies.contains(spec) {
      continue
    }
    match spec.find("*") {
      Some(i) =>
        patterns.push(
          (spec[:i].to_owned(), spec[i + 1:].to_owned(), untyped_target),
        )
      None => exact[spec] = untyped_target
    }
  }
  for spec in order {
    let path = ambient_module_path(spec)
    let source : MtscModuleSource = {
      path,
      source: bodies.get(spec).unwrap_or(""),
      allowJsx: false,
    }
    match parse_graph_module(source, ambient_body=true) {
      Ok(parsed) => {
        for inner in mtsc_module_specifiers(parsed) {
          for origin in origins.get(spec).unwrap_or([]) {
            match targets.get(origin + "\u{0}" + inner) {
              Some(target) => {
                body_edges.push({
                  importerPath: path,
                  moduleSpecifier: inner,
                  targetPath: target,
                })
                break
              }
              None => ()
            }
          }
        }
        modules.push(with_implicit_exports(parsed))
        virtual_paths[path] = ()
        match spec.find("*") {
          Some(i) =>
            patterns.push((spec[:i].to_owned(), spec[i + 1:].to_owned(), path))
          None => exact[spec] = path
        }
      }
      // A body that does not parse declares nothing here; the file that
      // holds it reports its own syntax.
      Err(_) => ()
    }
  }
  let parsed_paths : Map[String, Unit] = Map([])
  for m in modules {
    parsed_paths[m.source.path] = ()
  }
  for e in body_edges {
    let k = e.importerPath + "\u{0}" + e.moduleSpecifier
    if !targets.contains(k) {
      targets[k] = e.targetPath
    }
  }
  let routed : Array[MtscModuleEdge] = []
  for m in modules {
    for spec in mtsc_module_specifiers(m) {
      let importer = m.source.path
      if !is_local_module_specifier(spec) {
        match exact.get(spec) {
          Some(path) => {
            if path == untyped_target {
              untyped[importer + "\u{0}" + spec] = ()
            } else {
              routed.push({
                importerPath: importer,
                moduleSpecifier: spec,
                targetPath: path,
              })
            }
            continue
          }
          None => ()
        }
      }
      let resolved = match targets.get(importer + "\u{0}" + spec) {
        Some(target) => parsed_paths.contains(target)
        None => false
      }
      if resolved {
        continue
      }
      let mut best : (Int32, String)? = None
      for pattern in patterns {
        let (prefix, suffix, path) = pattern
        if spec.length() >= prefix.length() + suffix.length() &&
          spec.has_prefix(prefix) &&
          spec.has_suffix(suffix) {
          match best {
            Some((len, _)) if len >= prefix.length() => ()
            _ => best = Some((prefix.length(), path))
          }
        }
      }
      match best {
        Some((_, path)) =>
          if path == untyped_target {
            untyped[importer + "\u{0}" + spec] = ()
          } else {
            routed.push({
              importerPath: importer,
              moduleSpecifier: spec,
              targetPath: path,
            })
          }
        None => ()
      }
    }
  }
  // First edge per (importer, specifier) wins in `find_graph_target`, so the
  // routed edges go in front of the resolver's.
  for e in edges {
    // A shorthand answered this import: the file the resolver found, if
    // any, is not what the import means.
    if !untyped.contains(e.importerPath + "\u{0}" + e.moduleSpecifier) {
      routed.push(e)
    }
  }
  // A body's own import of a module a shorthand declares is untyped too:
  // the copied edge would read the file the resolver found instead.
  for e in body_edges {
    if !untyped.contains(e.importerPath + "\u{0}" + e.moduleSpecifier) {
      routed.push(e)
    }
  }
  (modules, routed, virtual_paths, untyped)
}

///|
/// Type-check a resolved module graph and return the diagnostics.
///
/// This is what a multi-file CLI wants: checking each file in isolation
/// leaves every imported type unresolvable, and a checker that cannot
/// see `type Loc = { … }` from the module that declares it either stays
/// silent on real errors or reports a mismatch between two identical
/// shapes. Resolution stays the caller's job — hand over the module
/// sources plus the import edges between them.
///
/// `check_module_graph` flattens the same information into one string
/// for the JavaScript ABI; the CLI needs it structured so it can format
/// and count diagnostics itself.
///
/// `compiler_options~` applies one tsconfig's `compilerOptions` to every
/// module, as `tsc -p` does; see `compiler_option_header`.
pub fn collect_module_graph_issues(
  graph : MtscModuleGraph,
  compiler_options~ : Array[(String, String)] = [],
  // Modules that take part in the program as CONTEXT only: their
  // declarations are visible to every module that imports them, and their
  // own diagnostics are not computed. A dependency's `.d.ts` is the case
  // this exists for — `tsc` with `skipLibCheck` does the same — and
  // skipping the per-module check rather than filtering its output is
  // what keeps a package's hundreds of declaration files from costing a
  // check each.
  context_only~ : Map[String, Unit] = Map([]),
) -> Array[MtscGraphIssue] {
  let parsed_modules : Array[ParsedMtscModule] = []
  let issues : Array[MtscGraphIssue] = []
  let option_header = compiler_option_header(compiler_options)
  let unreadable : Map[String, Unit] = Map([])
  for source in graph.modules {
    match parse_graph_module(source, option_header~) {
      Ok(module_) => parsed_modules.push(module_)
      // A context-only module is a dependency's declaration file, which
      // the program reads and does not check. One this parser cannot read
      // is far likelier a gap here than a syntax error in a published
      // package, so it is left untyped instead of reported, as the CLI's
      // loader already does for the same file.
      Err(_) if context_only.contains(source.path) =>
        unreadable[source.path] = ()
      Err(e) =>
        issues.push({
          modulePath: source.path,
          path: "parse",
          message: "parse error: \{e}",
        })
    }
  }
  // An import of an unreadable dependency is untyped, not missing: its edge
  // goes, and the import is marked skipped so a relative one is not
  // reported as an unresolved local module either. Kept, the edge pointed
  // at a module the graph does not hold, which is "is absent at".
  let edges = graph.edges.filter(fn(e) { !unreadable.contains(e.targetPath) })
  let skipped_imports : Map[String, Unit] = Map([])
  for e in graph.edges {
    if unreadable.contains(e.targetPath) {
      skipped_imports[e.importerPath + "\u{0}" + e.moduleSpecifier] = ()
    }
  }
  collect_parsed_graph_issues(
    parsed_modules,
    edges,
    issues,
    context_only~,
    skipped_imports~,
  )
  issues
}

///|
/// Check an already-parsed graph, appending to `issues`.
///
/// Split out of `collect_module_graph_issues` so the host-driven loader
/// in `service.mbt` can hand over modules it has ALREADY parsed. It has
/// to parse them to discover their imports at all, and re-parsing every
/// file to re-derive a graph the loader just built would be a third pass
/// over every source — `parse_graph_module` already costs two, one for
/// the module and one for its block.
///
/// Extraction only: the body below is what `collect_module_graph_issues`
/// ran, and that function still produces the same diagnostics in the
/// same order. `checker_wbtest.mbt` pins that, and so does the
/// `checkModuleGraph` string ABI built on top of it.
fn collect_parsed_graph_issues(
  parsed_modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
  issues : Array[MtscGraphIssue],
  context_only~ : Map[String, Unit] = Map([]),
  skipped_imports~ : Map[String, Unit] = Map([]),
) -> Unit {
  // Ambient declaration files are part of every module's scope: that is
  // what makes `declare const MyGlobal: …` in an `env.d.ts` visible from
  // a source file that never imports it. Only script-shaped `.d.ts`
  // files count — one carrying its own imports / exports is a module,
  // and its declarations are private to it.
  // Every type-only ingestion below is cached per module path for the
  // duration of THIS check; a previous program's entries must not leak in.
  @checker.clear_type_module_cache()
  graph_exposed_cache.clear()
  graph_import_alias_cache.clear()
  graph_declaration_namespace_alias_cache.clear()
  graph_module_index.clear()
  graph_edge_index.clear()
  graph_reach_index_cache.clear()
  let (parsed_modules, edges, ambient_module_paths, untyped_imports) = graph_with_ambient_modules(
    parsed_modules, edges,
  )
  let skipped_imports = if untyped_imports.length() == 0 {
    skipped_imports
  } else {
    let all : Map[String, Unit] = Map([])
    for k, _ in skipped_imports {
      all[k] = ()
    }
    for k, _ in untyped_imports {
      all[k] = ()
    }
    all
  }
  let context_only = if ambient_module_paths.length() == 0 {
    context_only
  } else {
    let all : Map[String, Unit] = Map([])
    for k, _ in context_only {
      all[k] = ()
    }
    for k, _ in ambient_module_paths {
      all[k] = ()
    }
    all
  }
  let ambient_globals : Array[(String, @ast.TsType)] = []
  // Aligned with `ambient_globals`: the module a `declare global` entry was
  // written in, or "" for an ambient script's, whose scope is global.
  let ambient_global_origin : Array[String] = []
  // Per declaring module, the type names its own scope declares or imports,
  // each mapped to a key no other module registers (see below).
  let global_scope_renames : Map[
    String,
    (Map[String, String], Map[String, Unit]),
  ] = Map([])
  let ambient_modules : Array[@ast.TsModule] = []
  let namespace_cache : Map[String, (@ast.TsType, Array[(String, String)])] = Map([],
  )
  for module_ in parsed_modules {
    if !is_ambient_script_module(module_) {
      continue
    }
    ambient_modules.push(module_.module_)
    for entry in module_value_bindings(module_.module_) {
      ambient_globals.push(entry)
      // Its type is written in the ambient file's scope, which has no key:
      // the checker reads it through what that file's declarations moved
      // to (`<unkeyed>`, see `check_module_function_bodies_layered`).
      ambient_globals.push(("@value-origin:" + entry.0, Named("<unkeyed>")))
      ambient_global_origin.push("")
      ambient_global_origin.push("")
    }
  }
  // A MODULE's `declare global { … }` augments the global scope for the
  // whole program, the way an ambient script's declarations do, whether or
  // not anything imports the module. Only a module the checked file
  // reached used to contribute it, so `types: ["vitest/globals"]`, whose
  // `globals.d.ts` is `declare global { const it: … }` plus `export {}`,
  // left `describe` / `it` / `expect` undeclared in every test file. The
  // block's values are typed in the declaring module's scope, which is
  // what `@value-origin:` names.
  for module_ in parsed_modules {
    if is_ambient_script_module(module_) {
      continue
    }
    for ns in module_.module_.namespaces {
      if ns.name != "<global>" {
        continue
      }
      ambient_modules.push(ns.module_)
      if !global_scope_renames.contains(module_.source.path) {
        global_scope_renames[module_.source.path] = module_scope_type_renames(
          module_,
        )
      }
      for entry in module_value_bindings(ns.module_) {
        if @checker.lib_declares_global_value(entry.0) {
          continue
        }
        ambient_globals.push(entry)
        ambient_globals.push(
          ("@value-origin:" + entry.0, Named(module_.source.path)),
        )
        ambient_global_origin.push(module_.source.path)
        ambient_global_origin.push(module_.source.path)
      }
    }
  }
  for module_ in parsed_modules {
    // Still parsed and still ingested by every module that reaches it —
    // only its OWN check is skipped. The ambient scan above runs over
    // every module for the same reason: a context-only `.d.ts` that
    // declares globals still declares them.
    if context_only.contains(module_.source.path) {
      continue
    }
    // `// @ts-nocheck` opts the file out of every check, its imports'
    // "has no export" / "cannot find module" included — tsc accepts
    // `import x from "./nonexistent"` under it. Like a context-only file it
    // still declares what it declares for the modules that reach it.
    if @checker.module_is_ts_nocheck(module_.module_) {
      continue
    }
    let (globals, import_diagnostics) = graph_import_globals(
      module_, parsed_modules, edges, skipped_imports, namespace_cache,
    )
    let type_module_keys : Array[String] = []
    let type_modules = graph_type_modules(
      module_,
      parsed_modules,
      edges,
      keys=type_module_keys,
    )
    // A `declare global` value's type is written in its declaring module's
    // scope. Where that module is reachable, its types are ingested and the
    // `@value-origin:` marker reads them there. Where it is not, a bare
    // `Payload` would resolve against whatever THIS module calls `Payload`
    // and report `payload.a` on a legal line, so the names that scope
    // declares or imports move to keys nothing registers, which abstains,
    // as an import-typed global already does.
    let reachable_origins : Map[String, Unit] = Map([])
    reachable_origins[module_.source.path] = ()
    for k in type_module_keys {
      reachable_origins[k] = ()
    }
    // An import or a declaration binds its name in the module's own scope,
    // which a global never overrides: `import { shadowed } from "./other"`
    // or `export const shadowed = "s"` beside a `declare global { const
    // shadowed: number }` elsewhere is the module's own `shadowed`. The
    // ambient entries come last in `globals`, so pushing them for such a
    // name would let the global win inside every function body.
    let own_names : Map[String, Unit] = Map([])
    for name in module_.module_.imported_binding_names {
      own_names[name] = ()
    }
    for entry in module_value_bindings(module_.module_) {
      own_names[entry.0] = ()
    }
    for i, entry in ambient_globals {
      let name = if entry.0.has_prefix("@value-origin:") {
        entry.0["@value-origin:".length():].to_owned()
      } else {
        entry.0
      }
      if own_names.contains(name) {
        continue
      }
      let origin = ambient_global_origin[i]
      match global_scope_renames.get(origin) {
        Some((renames, roots)) if origin != "" &&
          !reachable_origins.contains(origin) &&
          !entry.0.has_prefix("@value-origin:") => {
          // A dotted name rooted at one of that module's own namespaces or
          // namespace imports (`Models.Payload`, `ns.X`) is in its scope
          // too, and a bare-name rename cannot match it.
          let all = renames.copy()
          for n in @checker.collect_referenced_names(entry.1) {
            match n.find(".") {
              Some(i) if roots.contains(n[:i].to_owned()) =>
                all[n] = n + "@" + origin
              _ => ()
            }
          }
          globals.push((entry.0, @checker.rename_type_refs(entry.1, all)))
        }
        _ => globals.push(entry)
      }
    }
    for diagnostic in import_diagnostics {
      issues.push({
        modulePath: module_.source.path,
        path: "import",
        message: diagnostic,
      })
    }
    for ambient in ambient_modules {
      type_modules.push(ambient)
    }
    let namespace_type_aliases = graph_namespace_type_aliases(
      module_, parsed_modules, edges,
    )
    // Each reachable module's own named imports, aligned with
    // `type_module_keys`, so ITS references to a colliding name are
    // rewritten to the module it imports from rather than read off the
    // shared bare entry (see `graph_named_import_aliases`).
    //
    // Its NAMESPACE imports join them only where they disagree with the
    // checked module's: the shared resolver maps `ns.X` through the CHECKED
    // module's `import * as ns`, so a reachable module whose `ns` names a
    // different module would read the wrong `X`. Where the two agree that
    // mapping is already right, and where the checked module has no `ns`
    // the reference stays unresolved, which abstains.
    let own_namespaces : Map[String, String] = Map([])
    for imp in module_.module_block.imports {
      match imp.namespace_binding {
        Some(ns) =>
          match find_graph_target(edges, module_.source.path, imp.module_spec) {
            Some(target) => own_namespaces[ns] = target
            None => ()
          }
        None => ()
      }
    }
    let type_module_import_aliases : Array[Array[(String, String, String)]] = []
    for key in type_module_keys {
      type_module_import_aliases.push(
        match find_graph_module(parsed_modules, key) {
          Some(m) => {
            let named = graph_named_import_aliases(m, parsed_modules, edges)
            let conflicting = if mtsc_is_declaration_file(m.source.path) {
              graph_declaration_namespace_aliases(m, parsed_modules, edges)
            } else {
              graph_conflicting_namespace_aliases(
                m, own_namespaces, parsed_modules, edges,
              )
            }
            if conflicting.length() == 0 {
              named
            } else {
              let all = named.copy()
              for extra in conflicting {
                all.push(extra)
              }
              all
            }
          }
          None => []
        },
      )
    }
    match
      collect_type_issues_from_module(
        module_.module_,
        globals,
        type_modules,
        namespace_type_aliases~,
        type_module_keys~,
        type_module_import_aliases~,
      ) {
      Err(e) =>
        issues.push({
          modulePath: module_.source.path,
          path: "parse",
          message: "parse error: \{e}",
        })
      Ok(found) =>
        for issue in found {
          issues.push({
            modulePath: module_.source.path,
            path: issue.path,
            message: issue.message,
          })
        }
    }
  }
}

///|
pub fn check_module_graph(graph : MtscModuleGraph) -> String {
  // The string ABI is a FORMAT over `collect_module_graph_issues`, not a
  // second checker. It used to carry its own copy of the per-module loop,
  // and that copy had fallen behind the one the CLI runs: no per-module
  // type keys (so a name two modules declare was their merge — univer's
  // `ICommand`), no ambient `.d.ts` scope, and no reset of the type-module
  // cache between programs. One loop, two renderings.
  let diagnostics : Array[String] = []
  for issue in collect_module_graph_issues(graph) {
    diagnostics.push("\{issue.modulePath}: \{issue.message}")
  }
  diagnostics.join("\n")
}
