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
  let module_ = p1.parse_module() catch { e => return Err("\{e}") }
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
  for i, param in func.params {
    // A leading `this` parameter types the receiver and takes no argument
    // position (`declare_function_value_type` drops it the same way).
    if i == 0 && param.name == "this" && !param.is_rest {
      continue
    }
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
  @ast.TsType::Func(params, func.return_type)
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
  let f = @ast.TsType::Func(params, import_.return_type)
  if import_.type_params.is_empty() {
    f
  } else {
    @ast.TsType::GenericFunc(import_.type_params, [], f)
  }
}

///|
fn local_value_type(module_ : @ast.TsModule, name : String) -> @ast.TsType? {
  // A namespace is lowered to `var N = N || {}`, so `values` holds it as
  // `any` and has to be passed over. A function or class of the same name
  // is a declaration merge whose value is that function or class.
  if !module_.funcs.iter().any(fn(f) { f.name == name }) &&
    !module_.classes.iter().any(fn(c) { c.name == name }) {
    for ns in module_.namespaces {
      if ns.name == name && !ns.is_declare {
        return Some(namespace_value_type(ns.module_))
      }
    }
  }
  for value in module_.values {
    if value.name == name {
      match value.type_ {
        Any =>
          match arrow_const_predicate_type(module_, name) {
            Some(t) => return Some(t)
            None => ()
          }
        _ => ()
      }
      return Some(value.type_)
    }
  }
  match arrow_const_predicate_type(module_, name) {
    Some(t) => return Some(t)
    None => ()
  }
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
          let params = raw_params.mapi(fn(i, t) {
            let p = func.params[i]
            if !p.is_rest && (p.is_optional || p.default is Some(_)) {
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

  let names : Array[String] = []
  for v in body.values {
    if !names.contains(v.name) {
      names.push(v.name)
    }
  }
  for f in body.funcs {
    if !names.contains(f.name) {
      names.push(f.name)
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
        name => {
        let ps : Array[@ast.TsType] = []
        for _ in params {
          ps.push(Any)
        }
        return Some(Func(ps, TypePredicate(p, t)))
      }
      // `export const isUnion = makeGuard("Union")` — see
      // `@checker.factory_guard_predicate`.
      Const(Ident(n), Any, init) if n == name =>
        match @checker.factory_guard_predicate(module_, init) {
          Some((params, p, t)) => {
            let ps : Array[@ast.TsType] = []
            for _ in params {
              ps.push(Any)
            }
            return Some(Func(ps, TypePredicate(p, t)))
          }
          None => ()
        }
      _ => ()
    }
  }
  None
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
  for export_ in module_.module_block.exports {
    if export_.export_name == export_name {
      return local_value_type(module_.module_, export_.local_name).map(fn(t) {
        (module_, export_.local_name, t)
      })
    }
  }
  // `export { value } from "./module"` is the ordinary public-barrel style.
  // Follow only value reexports here; `export type` never introduces a
  // runtime binding for an importing module.
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
  None
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
  let order : Array[ParsedMtscModule] = []
  let visited_paths : Map[String, Unit] = Map([])
  let modules_by_path : Map[String, ParsedMtscModule] = Map([])
  for m in modules {
    if !modules_by_path.contains(m.source.path) {
      modules_by_path[m.source.path] = m
    }
  }
  let edges_by_importer : Map[String, Array[String]] = Map([])
  for edge in edges {
    match edges_by_importer.get(edge.importerPath) {
      Some(targets) => targets.push(edge.targetPath)
      None => edges_by_importer[edge.importerPath] = [edge.targetPath]
    }
  }
  let pending_paths : Array[String] = [module_.source.path]
  let mut cursor = 0
  while cursor < pending_paths.length() {
    let importer_path = pending_paths[cursor]
    cursor = cursor + 1
    if visited_paths.contains(importer_path) {
      continue
    }
    visited_paths[importer_path] = ()
    for target_path in edges_by_importer.get(importer_path).unwrap_or([]) {
      let target = match modules_by_path.get(target_path) {
        Some(target) => target
        None => continue
      }
      order.push(target)
      pending_paths.push(target.source.path)
    }
  }
  let last_index : Map[String, Int32] = Map([])
  for i, t in order {
    last_index[t.source.path] = i
  }
  for i, t in order {
    if last_index.get(t.source.path) == Some(i) {
      type_modules.push(t.module_)
      keys.push(t.source.path)
    }
  }
  type_modules
}

///|
fn graph_import_globals(
  module_ : ParsedMtscModule,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
) -> (Array[(String, @ast.TsType)], Array[String]) {
  let globals : Array[(String, @ast.TsType)] = []
  let diagnostics : Array[String] = []
  for import_ in module_.module_block.imports {
    let target_path = match
      find_graph_target(edges, module_.source.path, import_.module_spec) {
      Some(path) => path
      None => {
        if is_local_module_specifier(import_.module_spec) {
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
            diagnostics.push(
              "module `\{import_.module_spec}` has no default value export",
            )
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
        for export_ in target.module_block.exports {
          match local_value_type(target.module_, export_.local_name) {
            Some(t) if is_predicate_value_type(t) => {
              // The type is written in the TARGET's scope: its bare
              // `Success` means the target's own, which in the importer is
              // reached as `ns.Success`.
              let renames : Map[String, String] = Map([])
              for i in target.module_.interfaces {
                renames[i.name] = ns + "." + i.name
              }
              for a in target.module_.type_aliases {
                renames[a.name] = ns + "." + a.name
              }
              for c in target.module_.classes {
                renames[c.name] = ns + "." + c.name
              }
              globals.push(
                (
                  "@ns:" + ns + "." + export_.export_name,
                  @checker.rename_type_refs(t, renames),
                ),
              )
            }
            _ => ()
          }
        }
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
          diagnostics.push(
            "module `\{import_.module_spec}` has no value export `\{imported_name}`",
          )
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
fn is_ambient_script_module(module_ : ParsedMtscModule) -> Bool {
  if !module_.source.path.has_suffix(".d.ts") {
    return false
  }
  module_.module_block.imports.is_empty() &&
  module_.module_block.exports.is_empty() &&
  module_.module_block.reexports.is_empty()
}

///|
/// Value-level bindings a module declares, in the (name, type) shape the
/// checker takes for globals.
fn module_value_bindings(
  module_ : @ast.TsModule,
) -> Array[(String, @ast.TsType)] {
  let out : Array[(String, @ast.TsType)] = []
  for value in module_.values {
    out.push((value.name, value.type_))
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
  for source in graph.modules {
    match parse_graph_module(source, option_header~) {
      Ok(module_) => parsed_modules.push(module_)
      Err(e) =>
        issues.push({
          modulePath: source.path,
          path: "parse",
          message: "parse error: \{e}",
        })
    }
  }
  collect_parsed_graph_issues(
    parsed_modules,
    graph.edges,
    issues,
    context_only~,
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
  graph_module_index.clear()
  graph_edge_index.clear()
  let ambient_globals : Array[(String, @ast.TsType)] = []
  let ambient_modules : Array[@ast.TsModule] = []
  for module_ in parsed_modules {
    if !is_ambient_script_module(module_) {
      continue
    }
    ambient_modules.push(module_.module_)
    for entry in module_value_bindings(module_.module_) {
      ambient_globals.push(entry)
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
    let (globals, import_diagnostics) = graph_import_globals(
      module_, parsed_modules, edges,
    )
    for entry in ambient_globals {
      globals.push(entry)
    }
    for diagnostic in import_diagnostics {
      issues.push({
        modulePath: module_.source.path,
        path: "import",
        message: diagnostic,
      })
    }
    let type_module_keys : Array[String] = []
    let type_modules = graph_type_modules(
      module_,
      parsed_modules,
      edges,
      keys=type_module_keys,
    )
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
            let conflicting = graph_conflicting_namespace_aliases(
              m, own_namespaces, parsed_modules, edges,
            )
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
