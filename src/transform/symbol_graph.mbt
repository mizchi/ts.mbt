// Def-use / flow graph over a bundled `TsBlock`.
//
// This is Phase 1 of the type-free observability analysis described
// in DESIGN.md: walk the post-bundle / pre-mangle block once and
// record
//
//   - every binding (its declaration site, kind, reassignments)
//   - every reference to a binding (read / property receiver / call
//     receiver / index key / etc.)
//   - the data-flow edges between them (assignment, return, function
//     argument passing).
//
// Phase 2 (numeric-variable propagation) and Phase 3 (reflection-
// sink escape analysis) consume the graph; Phase 1 itself produces
// no minify benefit. The goal here is correctness — every binding
// reachable in the source must appear in `symbols`, and every
// `Var(n)` reference must resolve to the binding that JS scoping
// rules would pick.
//
// Scope rules followed:
//
//   - `function f(...) { … }` and `() => …` introduce a Function
//     scope. `var` hoists to the nearest enclosing Function scope;
//     `let` / `const` stay in the block where they're declared.
//   - `{ … }` blocks, `try { … }` / `catch (e) { … }` / `finally`,
//     `if`/`else`, loop bodies, and `switch` cases each get a
//     Block scope.
//   - `for (let x = …; …)` puts `x` in a fresh per-iteration scope
//     (modelled as a Block scope that wraps the body).
//   - Catch clauses introduce a Catch scope whose only binding is
//     the catch parameter (when present).
//
// External imports (`import x from "lib"`, `import { y } from
// "lib"`) all land in `external_bindings` so later phases can flag
// them as "value crosses the bundle boundary".

///|
pub type SymbolId = Int

///|
pub type ScopeId = Int

///|
pub(all) struct SymbolGraph {
  // Scope tree. `scopes[0]` is always the module root.
  scopes : Array[Scope]
  // All bindings, indexed by `SymbolId`. `symbols[i].id == i`.
  symbols : Array[Symbol]
  // Lookup: (scope_id, source_name) -> SymbolId. The lookup
  // resolution rule (walk up the parent chain until a match) is the
  // caller's responsibility.
  by_name : Map[String, SymbolId]
  // Data-flow edges. Each edge says "the value of `from` reaches
  // `to`" — used by Phase 3 / 4's backward propagation.
  flow_edges : Array[FlowEdge]
  // Bindings whose initializer crosses the bundle boundary
  // (`import x from "lib"` and friends). Phase 3 starts every
  // observability seed at one of these.
  external_bindings : Map[SymbolId, Bool]
  // Per-function metadata, keyed by the function's own SymbolId
  // (= the binding name of a named `function f() {...}` or the
  // `Let(...)` declarator that wraps a `FuncExpr`). Anonymous
  // function expressions get no entry — Phase 4 falls back to
  // wildcard when their return value reaches an observation
  // point because the callee can't be statically identified.
  funcs : Map[SymbolId, FuncInfo]
  // Names referenced but resolving to no binding, with one scope they
  // were seen in. Globals live here too (`console`, `Math`), so this is
  // raw material rather than an error list — `verify.mbt` subtracts the
  // host's names and reports whatever is left.
  //
  // The walk used to drop these on the floor: `sg_record_use`'s `None`
  // arm read "global / runtime built-in / typo. Nothing to record". The
  // typo is exactly what a verifier wants, and a deleted-but-still-
  // referenced binding IS a typo by then. `CODES is not defined` on the
  // Excalidraw bundle was detectable here without running anything.
  unresolved : Map[String, ScopeId]
}

///|
pub(all) struct FuncInfo {
  // The function's parameter symbol ids in declaration order.
  // Phase 4 uses this to walk from `FuncArg(fid, i)` flow
  // landings back to the i-th parameter binding.
  params : Array[SymbolId]
  // Source-side flow nodes for every `return <expr>` and every
  // `throw <expr>` in the function body. Phase 4 propagates
  // observability landing on this function's return value back
  // to these sources.
  returns : Array[FlowNode]
} derive(Debug)

///|
pub(all) struct Scope {
  id : ScopeId
  parent : ScopeId?
  kind : ScopeKind
  // SymbolIds declared in this scope (not in children).
  declared : Array[SymbolId]
}

///|
pub(all) enum ScopeKind {
  Module
  Function
  Block
  Catch
} derive(Eq, Debug)

///|
pub(all) struct Symbol {
  id : SymbolId
  scope_id : ScopeId
  name : String
  kind : SymbolKind
  // Recorded uses (Var references). Property `.foo` access on
  // this binding goes through `PropReceiver(foo)`; `arr[i]` on
  // this binding goes through `IndexReceiver`; etc.
  uses : Array[Use]
  // Initializers — the rhs of `let x = …` / `const x = …` /
  // `var x = …` declarations (and the implicit `undefined` for
  // bare `let x;`). For destructuring (`let {a, b} = obj`) the
  // `init` is the whole object expression and the symbol's
  // `defs` carries it as-is — refinement is Phase 3's job.
  defs : Array[Def]
  // RHS of every reassignment (`x = expr`, `x += expr`, etc.)
  // captured for type-flow analysis. Phase 2's numeric-vars pass
  // walks these to decide whether the binding stays numeric after
  // a write.
  reassign_rhs : Array[@ast.TsExpr]
  // Values written INTO this binding through a property or index
  // (`obj.q = v`, `obj[k] = v`, `obj.a.b = v`). A flow edge carries
  // the target's observability back to the value's own bindings, but
  // an object LITERAL written here has no binding of its own — its
  // keys exist only in that expression. `collect_direct_props` reads
  // this so an observed target reserves them.
  written_values : Array[@ast.TsExpr]
  // Set when any later statement writes to this binding (`x = ...`,
  // `x += ...`, `++x`, destructuring assignment, etc.).
  mut reassigned : Bool
  // Set when the binding is referenced inside a nested function /
  // arrow body. Closure-captured bindings can outlive the
  // declaring frame, so Phase 3 treats them conservatively.
  mut captured_by_closure : Bool
  // Static TypeScript type of the binding when one was supplied
  // (let/const/var annotation, function parameter annotation).
  // Defaults to `Any` when no useful type was recorded — that
  // matches "no type info" and downstream narrowing falls back to
  // the wildcard. Type-aware reservation passes
  // (`reserved_props_from_observability` in `flow_analysis.mbt`)
  // consult this to skip the External-observation wildcard when
  // the type's key set is statically bounded.
  mut ts_type : @ast.TsType
} derive(Debug)

///|
pub(all) enum SymbolKind {
  Let
  Const
  Var
  Param
  FuncDecl
  ImportDefault
  ImportNamespace
  ImportNamed
  Catch
  ClassDecl
} derive(Eq, Debug)

///|
pub(all) struct Def {
  init : @ast.TsExpr?
} derive(Debug)

///|
pub(all) struct Use {
  scope_id : ScopeId
  context : UseContext
} derive(Debug)

///|
pub(all) enum UseContext {
  // Plain read: `let y = x;`, `x + 1`, etc.
  Read
  // `x.foo`: the binding is the property receiver, `foo` is the
  // accessed property name.
  PropReceiver(String)
  // `x[i]`: the binding is the index-access receiver (an array /
  // map-like value).
  IndexReceiver
  // `arr[x]`: the binding is the dynamic index key.
  IndexKey
  // `x(args)`: the binding is the callee.
  CallReceiver
  // `f(x)`: the binding is an argument; `Int` is the position.
  CallArg(Int)
  // `new x(...)`.
  NewReceiver
  // `return x;`.
  ReturnValue
  // `throw x;`.
  ThrowValue
  // `x = …` LHS (excluding the binding's declaration site).
  AssignLHS
  // `… = x` RHS (the value being copied).
  AssignRHS
  // `obj.foo = x` — the value being assigned to a property.
  PropAssignRHS
  // `obj[k] = x` — same for index assignment.
  IndexAssignRHS
} derive(Debug)

///|
pub(all) struct FlowEdge {
  from : FlowNode
  to : FlowNode
} derive(Debug)

///|
/// A point in the data-flow graph.
pub(all) enum FlowNode {
  // The value of a binding.
  SymVal(SymbolId)
  // The value returned by a function (identified by its binding).
  // `Int` is the n-th return statement in source order; 0 covers
  // the common "single return" case and Phase 3 unifies them.
  FuncReturn(SymbolId)
  // The n-th parameter slot of a function call. Phase 3 propagates
  // observability from the call site into the callee's parameter.
  FuncArg(SymbolId, Int)
  // Literal-derived value (no upstream source). Phase 2/3 stops
  // backward propagation here; `kind` lets the numeric-vars pass
  // distinguish `0` from `"broken"` without re-walking the AST.
  Literal(LiteralKind)
  // Crosses the bundle boundary — `external_bindings` member or
  // call into an unresolved callee. Phase 3 treats this as a fixed
  // "observable" source / sink.
  External
  // Couldn't statically determine the source (computed call,
  // dynamic property, etc.). Phase 3 must treat as External.
  Unknown
} derive(Debug)

///|
pub(all) enum LiteralKind {
  LitNumeric // NumberLit / IntLit / BigIntLit / Number-typed arithmetic
  LitString // StringLit / TemplateLiteral
  LitBool // BoolLit
  LitNull // NullLit / Undefined
  LitObject // ObjectLit / ArrayLit / function expression
  LitOther // anything else we don't classify
} derive(Eq, Debug)

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

///|
/// Walk `block` once and produce a `SymbolGraph` covering every
/// binding and reference.
///
/// `external_local_names` lists binding NAMES that the linker
/// already established as external imports (default / namespace /
/// named) — passed in by the bundler since the merged `TsBlock`
/// itself doesn't carry the `TsImportDecl` headers.
pub fn build_symbol_graph(
  block : @ast.TsBlock,
  external_local_names : Map[String, Bool],
) -> SymbolGraph {
  let (g, _) = build_symbol_graph_with_sinks(block, external_local_names)
  g
}

///|
/// Same as `build_symbol_graph` but also returns the list of
/// observation sinks (reflection calls, throws, external arg
/// passing, etc.) discovered during the walk, each tagged with
/// the scope they were found in so callers can do scope-aware
/// `Var(...)` lookup when classifying them.
/// `host_shaped` / `host_returning` carry the whole-block provenance
/// facts from `host_provenance_names`: which binding names hold a
/// value the host owns, and which bundle functions return one. The
/// walk consults them to classify every call site — a call whose
/// callee isn't provably internal hands its arguments across the
/// bundle boundary. Callers that only want the symbol graph (no sink
/// analysis) can leave both empty.
pub fn build_symbol_graph_with_sinks(
  block : @ast.TsBlock,
  external_local_names : Map[String, Bool],
  host_shaped? : Map[String, Bool] = {},
  host_returning? : Map[String, Bool] = {},
) -> (SymbolGraph, Array[(Sink, ScopeId)]) {
  let g : SymbolGraph = {
    scopes: [],
    symbols: [],
    by_name: {},
    flow_edges: [],
    external_bindings: {},
    funcs: {},
    unresolved: {},
  }
  // Module scope (id 0).
  let module_scope = sg_new_scope(g, None, Module)
  // Phase 1: declare every binding visible in this scope so forward
  // references inside expressions can resolve.
  sg_declare_block_bindings(g, block, module_scope, external_local_names)
  // Phase 2: walk again, this time recording uses + flow edges
  // against the bindings that already exist.
  let walker : SgWalker = {
    g,
    current_scope: module_scope,
    in_closure_depth: 0,
    enclosing_func: None,
    enclosing_def: None,
    externals: external_local_names,
    host_roots: host_shaped,
    host_returning,
    scoped_sinks: [],
  }
  for s in block.stmts {
    sg_visit_stmt(walker, s)
  }
  (g, walker.scoped_sinks)
}

///|
priv struct SgWalker {
  g : SymbolGraph
  mut current_scope : ScopeId
  // Counts how many `function` / `=>` boundaries we've crossed
  // since the binding was declared. Any use inside a positive
  // depth is a closure capture.
  mut in_closure_depth : Int
  // SymbolId of the function we're currently inside (its body
  // gathers `return` / `throw` edges back to this symbol).
  mut enclosing_func : SymbolId?
  // SymbolId of the binding whose initializer we're currently
  // walking — used to add `RHS → binding` flow edges.
  mut enclosing_def : SymbolId?
  // External binding name set carried for sink classification.
  externals : Map[String, Bool]
  // Whole-block provenance facts (see `callee_provenance.mbt`):
  // binding names whose value the host owns, and bundle functions
  // that return one. Together with the live scope chain they decide
  // whether a call site is internal, an allowlisted built-in, or a
  // hand-off across the bundle boundary.
  host_roots : Map[String, Bool]
  host_returning : Map[String, Bool]
  // Collected sinks, paired with the scope they were observed in
  // so `reserve_props_from_sink` can resolve `Var(...)` arguments
  // through the right name lookup chain.
  scoped_sinks : Array[(Sink, ScopeId)]
}

///|
fn sg_new_scope(
  g : SymbolGraph,
  parent : ScopeId?,
  kind : ScopeKind,
) -> ScopeId {
  let id = g.scopes.length()
  g.scopes.push({ id, parent, kind, declared: [] })
  id
}

///|
fn sg_lookup(g : SymbolGraph, from_scope : ScopeId, name : String) -> SymbolId? {
  let mut cur : ScopeId? = Some(from_scope)
  while cur is Some(s) {
    match g.by_name.get(scope_name_key(s, name)) {
      Some(id) => return Some(id)
      None => cur = g.scopes[s].parent
    }
  }
  None
}

///|
/// Same as `sg_lookup` but pub for downstream passes (sink_catalog
/// uses this to resolve `Var(...)` sink arguments against the
/// scope they appeared in).
pub fn lookup_symbol_in_scope(
  g : SymbolGraph,
  from_scope : ScopeId,
  name : String,
) -> SymbolId? {
  sg_lookup(g, from_scope, name)
}

///|
fn scope_name_key(scope : ScopeId, name : String) -> String {
  scope.to_string() + ":" + name
}

///|
fn sg_declare(
  g : SymbolGraph,
  scope : ScopeId,
  name : String,
  kind : SymbolKind,
  external : Bool,
) -> SymbolId {
  // `var` hoists to the nearest enclosing Function / Module frame.
  let target_scope = if kind == Var { var_host_scope(g, scope) } else { scope }
  let key = scope_name_key(target_scope, name)
  match g.by_name.get(key) {
    // Already declared in this scope — keep the existing symbol
    // so multiple `var x` declarations share one entry.
    Some(id) => id
    None => {
      let id = g.symbols.length()
      g.symbols.push({
        id,
        scope_id: target_scope,
        name,
        kind,
        uses: [],
        defs: [],
        reassign_rhs: [],
        written_values: [],
        reassigned: false,
        captured_by_closure: false,
        ts_type: @ast.TsType::Any,
      })
      g.by_name[key] = id
      g.scopes[target_scope].declared.push(id)
      if external {
        g.external_bindings[id] = true
      }
      id
    }
  }
}

///|
fn var_host_scope(g : SymbolGraph, from : ScopeId) -> ScopeId {
  let mut cur = from
  let mut done = false
  while !done {
    let s = g.scopes[cur]
    match s.kind {
      Function | Module => done = true
      _ =>
        match s.parent {
          Some(p) => cur = p
          None => done = true
        }
    }
  }
  cur
}

// ---------------------------------------------------------------------------
// Pre-pass: declare all bindings of a block before walking expressions.
// JS hoists `var` / `function` declarations; pre-declaring `let` /
// `const` too just makes forward refs within the same block (which
// would throw at runtime) parse without losing the symbol.
// ---------------------------------------------------------------------------

///|
fn sg_declare_block_bindings(
  g : SymbolGraph,
  block : @ast.TsBlock,
  scope : ScopeId,
  external_local_names : Map[String, Bool],
) -> Unit {
  for s in block.stmts {
    sg_declare_stmt_bindings(g, s, scope, external_local_names)
  }
}

///|
fn sg_declare_stmt_bindings(
  g : SymbolGraph,
  stmt : @ast.TsStmt,
  scope : ScopeId,
  external_local_names : Map[String, Bool],
) -> Unit {
  match stmt {
    Var(b, t, init) => {
      let is_funcdecl = match init {
        @ast.TsExpr::FuncExpr(_) => true
        _ => false
      }
      let kind = if is_funcdecl { FuncDecl } else { Var }
      sg_declare_binding(g, b, scope, kind, external_local_names)
      sg_record_binding_type(g, b, scope, kind, t)
    }
    Let(b, t, init) => {
      let is_funcdecl = match init {
        @ast.TsExpr::FuncExpr(_) => true
        _ => false
      }
      let kind = if is_funcdecl { FuncDecl } else { Let }
      sg_declare_binding(g, b, scope, kind, external_local_names)
      sg_record_binding_type(g, b, scope, kind, t)
    }
    Const(b, t, init) => {
      let is_funcdecl = match init {
        @ast.TsExpr::FuncExpr(_) => true
        _ => false
      }
      let kind = if is_funcdecl { FuncDecl } else { Const }
      sg_declare_binding(g, b, scope, kind, external_local_names)
      sg_record_binding_type(g, b, scope, kind, t)
    }
    NativeClassStmt(decl, _) =>
      if decl.name != "" {
        let _ = sg_declare(g, scope, decl.name, ClassDecl, false)
      }
    // Same-kind multi-decl wrapper produced by `parse_var_like`.
    // The block leaks its bindings to the enclosing scope (emit
    // unwraps them) — declare each inner stmt against the SAME
    // scope rather than a child.
    Block(b) =>
      if is_multi_decl_wrapper(b) {
        for inner in b.stmts {
          sg_declare_stmt_bindings(g, inner, scope, external_local_names)
        }
      }
    _ => ()
  }
}

///|
fn is_multi_decl_wrapper(block : @ast.TsBlock) -> Bool {
  // `merge_decl_stmts` only wraps WHEN there are 2+ declarators —
  // a real `{ let a = 1; }` block has exactly one stmt and must be
  // treated as its own scope. The multi-decl wrapper always has
  // length() >= 2 by construction.
  if block.stmts.length() < 2 {
    return false
  }
  let kind = match block.stmts[0] {
    Var(_, _, _) => 0
    Let(_, _, _) => 1
    Const(_, _, _) => 2
    _ => return false
  }
  for s in block.stmts {
    match s {
      Var(_, _, _) => if kind != 0 { return false }
      Let(_, _, _) => if kind != 1 { return false }
      Const(_, _, _) => if kind != 2 { return false }
      _ => return false
    }
  }
  true
}

///|
// Stamp the static TypeScript type onto the symbol just declared
// for binding `b` in `scope`. No-op for opaque (`Any`) annotations
// and for destructuring patterns we can't decompose cleanly — the
// downstream narrowing pass treats the missing entry as "no type
// info" and falls back to the existing wildcard behaviour.
//
// The lookup mirrors `sg_declare`'s target-scope rule: `Var`
// hoists to the enclosing function frame, the others stay in
// `scope`. Without that mirroring the `Var` case looks up against
// the wrong key and silently misses the symbol.
fn sg_record_binding_type(
  g : SymbolGraph,
  b : @ast.TsBinding,
  scope : ScopeId,
  kind : SymbolKind,
  ty : @ast.TsType,
) -> Unit {
  match ty {
    @ast.TsType::Any => return
    _ => ()
  }
  match b {
    @ast.TsBinding::Ident(n) => {
      let target_scope = if kind == Var {
        var_host_scope(g, scope)
      } else {
        scope
      }
      let key = scope_name_key(target_scope, n)
      match g.by_name.get(key) {
        Some(id) => g.symbols[id].ts_type = ty
        None => ()
      }
    }
    _ => ()
  }
}

///|
fn sg_declare_binding(
  g : SymbolGraph,
  b : @ast.TsBinding,
  scope : ScopeId,
  kind : SymbolKind,
  external_local_names : Map[String, Bool],
) -> Unit {
  match b {
    Ident(n) => {
      let is_external = external_local_names.contains(n)
      let import_kind = if is_external { ImportNamed } else { kind }
      let _ = sg_declare(g, scope, n, import_kind, is_external)
    }
    Array(ab) => {
      for elem in ab.items {
        match elem {
          Some(be) =>
            sg_declare_binding(g, be.binding, scope, kind, external_local_names)
          None => ()
        }
      }
      match ab.rest {
        Some(r) => sg_declare_binding(g, r, scope, kind, external_local_names)
        None => ()
      }
    }
    Object(ob) => {
      for prop in ob.props {
        sg_declare_binding(g, prop.binding, scope, kind, external_local_names)
      }
      match ob.rest {
        Some(n) => {
          let _ = sg_declare(g, scope, n, kind, false)
        }
        None => ()
      }
    }
    Target(_) => ()
  }
}

// ---------------------------------------------------------------------------
// Main pass: record uses + flow edges
// ---------------------------------------------------------------------------

///|
fn sg_visit_stmt(w : SgWalker, stmt : @ast.TsStmt) -> Unit {
  match stmt {
    Var(b, _, init) | Let(b, _, init) | Const(b, _, init) =>
      sg_visit_decl(w, b, init)
    Assign(name, rhs) => {
      sg_record_use(w, name, AssignLHS)
      sg_visit_expr(w, rhs)
      // Mark the binding as reassigned, and add `rhs -> name` flow.
      match sg_lookup(w.g, w.current_scope, name) {
        Some(id) => {
          w.g.symbols[id].reassigned = true
          w.g.symbols[id].reassign_rhs.push(rhs)
          // `obj = { ...bag }` has the same hole one level up: the
          // literal used to be the end of the trail.
          for src in expr_flow_sources(w, rhs) {
            w.g.flow_edges.push({ from: src, to: SymVal(id) })
          }
        }
        None => ()
      }
    }
    CompoundAssign(name, _, rhs) => {
      sg_record_use(w, name, AssignLHS)
      sg_visit_expr(w, rhs)
      match sg_lookup(w.g, w.current_scope, name) {
        Some(id) => {
          w.g.symbols[id].reassigned = true
          // `x += expr` evaluates to the new value of `x` =
          // `x <op> expr`; arithmetic ops always produce a number,
          // string `+=` doesn't. Record the rhs verbatim and let
          // numeric-vars decide.
          w.g.symbols[id].reassign_rhs.push(rhs)
        }
        None => ()
      }
    }
    IndexAssign(target, idx, val) => {
      // `target[idx] = val`. The receiver is read (PropAssign
      // semantics), idx is read, val is read.
      sg_visit_expr(w, target)
      sg_visit_expr(w, idx)
      sg_visit_expr(w, val)
      sg_record_write_into(w, target, val)
    }
    PropAssign(target, prop, val) => {
      // Treat `obj.prop = val` as a `PropReceiver(prop)` use of
      // `obj` — Phase 4's prop-name reservation only walks
      // `Symbol.uses`, so without this the write side gets
      // dropped and `mergeDefs` etc. that were ASSIGNED (but not
      // READ in the same module) fall out of the reserved set.
      match target {
        @ast.TsExpr::Var(n) => sg_record_use(w, n, PropReceiver(prop))
        _ => sg_visit_expr(w, target)
      }
      sg_visit_expr(w, val)
      sg_record_write_into(w, target, val)
    }
    Expr(e) => sg_visit_expr(w, e)
    Throw(e) => {
      // `throw x` — caller sees the value; any property
      // (.message / .stack / .code) could be inspected.
      w.scoped_sinks.push(
        ({ expr: e, observation: Recursive }, w.current_scope),
      )
      sg_visit_expr(w, e)
    }
    Return(Some(e)) => {
      sg_visit_expr(w, e)
      match w.enclosing_func {
        Some(fid) => {
          let srcs = expr_immediate_sources(w, e)
          for src in srcs {
            w.g.flow_edges.push({ from: src, to: FuncReturn(fid) })
          }
          // The returned EXPRESSION, for the same reason
          // `sg_record_write_into` records a written one: an object
          // literal returned from here introduces keys that exist
          // nowhere else in the bundle, so nothing else can keep them
          // alive. `collect_direct_props` reads this list.
          w.g.symbols[fid].written_values.push(e)
          // Also record on `FuncInfo.returns` so Phase 4 can walk
          // the actual source nodes without re-iterating
          // `flow_edges` for every observable function.
          match w.g.funcs.get(fid) {
            Some(info) =>
              for src in srcs {
                info.returns.push(src)
              }
            None => ()
          }
        }
        None => ()
      }
    }
    Return(None) | Empty | Debugger | Break(_) | Continue(_) => ()
    If(c, t, e) => {
      sg_visit_expr(w, c)
      sg_visit_block_in_new_scope(w, t, Block)
      match e {
        Some(b) => sg_visit_block_in_new_scope(w, b, Block)
        None => ()
      }
    }
    While(c, body) | DoWhile(c, body) => {
      sg_visit_expr(w, c)
      sg_visit_block_in_new_scope(w, body, Block)
    }
    With(c, body) => {
      sg_visit_expr(w, c)
      sg_visit_block_in_new_scope(w, body, Block)
    }
    For(init, cond, update, body) => {
      let outer = w.current_scope
      w.current_scope = sg_new_scope(w.g, Some(outer), Block)
      match init {
        Some(s) => {
          sg_declare_stmt_bindings(w.g, s, w.current_scope, {})
          sg_visit_stmt(w, s)
        }
        None => ()
      }
      match cond {
        Some(e) => sg_visit_expr(w, e)
        None => ()
      }
      match update {
        Some(s) => sg_visit_stmt(w, s)
        None => ()
      }
      sg_visit_block_in_new_scope(w, body, Block)
      w.current_scope = outer
    }
    ForOf(_, b, _, iter, body) | ForAwaitOf(_, b, _, iter, body) => {
      sg_visit_expr(w, iter)
      let outer = w.current_scope
      w.current_scope = sg_new_scope(w.g, Some(outer), Block)
      sg_declare_binding(w.g, b, w.current_scope, Let, {})
      sg_visit_block_in_new_scope(w, body, Block)
      w.current_scope = outer
    }
    ForIn(_, b, _, iter, body) => {
      // `for-in iter` enumerates iter's property names — record
      // it as a DirectKeys sink in the enclosing scope (before
      // we open the per-iteration block).
      w.scoped_sinks.push(
        ({ expr: iter, observation: DirectKeys }, w.current_scope),
      )
      sg_visit_expr(w, iter)
      let outer = w.current_scope
      w.current_scope = sg_new_scope(w.g, Some(outer), Block)
      sg_declare_binding(w.g, b, w.current_scope, Let, {})
      sg_visit_block_in_new_scope(w, body, Block)
      w.current_scope = outer
    }
    Switch(e, cases) => {
      sg_visit_expr(w, e)
      for c in cases {
        match c.test_expr {
          Some(te) => sg_visit_expr(w, te)
          None => ()
        }
        sg_visit_block_in_new_scope(w, c.body, Block)
      }
    }
    Try(body, catch_bnd, catch_blk, finally_blk) => {
      sg_visit_block_in_new_scope(w, body, Block)
      match catch_blk {
        Some(cb) => {
          let outer = w.current_scope
          w.current_scope = sg_new_scope(w.g, Some(outer), Catch)
          match catch_bnd {
            Some(b) => sg_declare_binding(w.g, b, w.current_scope, Catch, {})
            None => ()
          }
          for s in cb.stmts {
            sg_visit_stmt(w, s)
          }
          w.current_scope = outer
        }
        None => ()
      }
      match finally_blk {
        Some(fb) => sg_visit_block_in_new_scope(w, fb, Block)
        None => ()
      }
    }
    Block(b) =>
      if is_multi_decl_wrapper(b) {
        // Already declared in the enclosing scope's pre-pass; just
        // walk the inner stmts here without opening a fresh frame.
        for inner in b.stmts {
          sg_visit_stmt(w, inner)
        }
      } else {
        sg_visit_block_in_new_scope(w, b, Block)
      }
    NativeClassStmt(decl, ctor) => {
      match decl.base_expr {
        Some(b) => sg_visit_expr(w, b)
        None => ()
      }
      match ctor {
        Some(f) => sg_visit_function_body(w, f)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => {
            // Class methods declare their params as Symbols inside a
            // fresh Function scope so the type-aware passes (e.g.
            // External-observation narrowing via the param
            // annotation) see them the same way they see arrow /
            // function-decl params.
            let outer = w.current_scope
            w.current_scope = sg_new_scope(w.g, Some(outer), Function)
            for p in m.params {
              let pid = sg_declare(w.g, w.current_scope, p.0, Param, false)
              match p.1 {
                @ast.TsType::Any => ()
                ty => w.g.symbols[pid].ts_type = ty
              }
            }
            sg_declare_block_bindings(w.g, b, w.current_scope, {})
            for s in b.stmts {
              sg_visit_stmt(w, s)
            }
            w.current_scope = outer
          }
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        sg_visit_expr(w, sf.1)
      }
    }
    Label(_, inner) => sg_visit_stmt(w, inner)
  }
}

///|
fn sg_visit_block_in_new_scope(
  w : SgWalker,
  block : @ast.TsBlock,
  kind : ScopeKind,
) -> Unit {
  let outer = w.current_scope
  w.current_scope = sg_new_scope(w.g, Some(outer), kind)
  sg_declare_block_bindings(w.g, block, w.current_scope, {})
  for s in block.stmts {
    sg_visit_stmt(w, s)
  }
  w.current_scope = outer
}

///|
fn sg_visit_decl(w : SgWalker, b : @ast.TsBinding, init : @ast.TsExpr) -> Unit {
  // Walk the initializer expression. Use `enclosing_def` to add
  // RHS->LHS flow edges.
  let lhs_id = binding_simple_ident(w, b)
  match lhs_id {
    Some(id) => {
      w.g.symbols[id].defs.push({ init: Some(init) })
      let prev = w.enclosing_def
      w.enclosing_def = Some(id)
      sg_visit_expr(w, init)
      w.enclosing_def = prev
      // Direct RHS sources flow to the LHS binding.
      for src in expr_immediate_sources(w, init) {
        w.g.flow_edges.push({ from: src, to: SymVal(id) })
      }
    }
    None =>
      // Destructuring binding — refinement is Phase 3's job.
      sg_visit_expr(w, init)
  }
}

///|
fn binding_simple_ident(w : SgWalker, b : @ast.TsBinding) -> SymbolId? {
  match b {
    Ident(n) => sg_lookup(w.g, w.current_scope, n)
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Expression walker
// ---------------------------------------------------------------------------

///|
fn sg_record_sinks_in_expr(w : SgWalker, expr : @ast.TsExpr) -> Unit {
  // Examine expression for reflection / external-call sinks at
  // THIS node only (no recursion — the surrounding `sg_visit_expr`
  // descends into children itself).
  match expr {
    IndexAccess(_, idx) =>
      // `obj[runtime_key]` widens the receiver's observable
      // surface to "every property name the bundle ever writes
      // here" — the runtime can pick any of them. Record the
      // receiver as a DirectKeys sink unless the key is provably
      // numeric (the IndexAccess wildcard fallback in
      // `mangle_safety` already short-circuits the numeric case;
      // here we only need to widen string-keyed cases). We don't
      // know yet if `idx` is numeric from the AST shape alone —
      // record unconditionally; Phase 4 only reserves the
      // bindings' actually-accessed names anyway, so a redundant
      // sink is harmless.
      match idx {
        NumberLit(_) | IntLit(_) => ()
        _ => {
          let recv = match expr {
            @ast.TsExpr::IndexAccess(r, _) => r
            _ => abort("unreachable")
          }
          w.scoped_sinks.push(
            ({ expr: recv, observation: DirectKeys }, w.current_scope),
          )
        }
      }
    MethodCall(recv, m, args) => {
      // The precisely-modelled reflection built-ins first.
      match recv {
        @ast.TsExpr::Var(name) =>
          if name == "Object" {
            match m {
              // `keys` hands out the key strings and nothing else, so
              // one level is the whole observation. `values` /
              // `entries` hand out the VALUES too, and the names inside
              // those ride along — an `Object.entries(x)` result that
              // reaches a consumer exposes `x`'s whole tree.
              "keys" =>
                for a in args {
                  w.scoped_sinks.push(
                    ({ expr: a, observation: DirectKeys }, w.current_scope),
                  )
                }
              "values" | "entries" | "fromEntries" =>
                for a in args {
                  w.scoped_sinks.push(
                    ({ expr: a, observation: Recursive }, w.current_scope),
                  )
                }
              // `Object.assign(target, …sources)` copies each source's own
              // first-level properties onto `target` — but the VALUES are
              // the same references, so a nested name travels with them
              // wherever `target` goes. `Recursive`, not `DirectKeys`.
              "assign" =>
                for i, a in args {
                  if i > 0 {
                    w.scoped_sinks.push(
                      ({ expr: a, observation: Recursive }, w.current_scope),
                    )
                  }
                }
              // `Object.defineProperty(obj, "name", desc)` /
              // `Object.defineProperties(obj, {…})` write a
              // property whose key is the second argument. When
              // the key is a string literal we already reserve
              // it; when it's a non-literal expression we mark
              // `obj` as DirectKeys-observable so its existing
              // surface stays renamed consistently.
              "defineProperty" =>
                if args.length() >= 2 {
                  match args[1] {
                    @ast.TsExpr::StringLit(_) | @ast.TsExpr::NumberLit(_) => ()
                    _ =>
                      w.scoped_sinks.push(
                        (
                          { expr: args[0], observation: DirectKeys },
                          w.current_scope,
                        ),
                      )
                  }
                }
              _ => ()
            }
          } else if name == "JSON" && m == "stringify" {
            for a in args {
              w.scoped_sinks.push(
                ({ expr: a, observation: Recursive }, w.current_scope),
              )
            }
          } else if name == "console" {
            for a in args {
              w.scoped_sinks.push(
                ({ expr: a, observation: Recursive }, w.current_scope),
              )
            }
          }
        _ => ()
      }
      // Then the general rule. `external.send({ id: 1 })`,
      // `crypto.subtle.digest(alg, data)`, `client.post(payload)` where
      // `client` came back from a foreign factory — each hands its
      // arguments to a body the analysis can't see, so every property
      // name on them escapes. The precise cases above are exempted by
      // the `pure_builtins` allowlist, so they don't get a redundant
      // wildcard on top of their exact reservation.
      sg_record_foreign_call_args(w, expr)
    }
    Call(_, _) | CallExpr(_, _) | New(_, _) | NewExpr(_, _) =>
      sg_record_foreign_call_args(w, expr)
    PropAssignExpr(target, _prop, rhs) =>
      if is_external_chain_for_sink(target, w.externals) {
        w.scoped_sinks.push(
          ({ expr: rhs, observation: ExternalPropWrite }, w.current_scope),
        )
      }
    _ => ()
  }
}

///|
/// The provenance question, asked from the walker's current position.
///
/// The one thing the pre-pass couldn't answer is here: `resolves`
/// consults the live scope chain, so a name no enclosing scope
/// declares is treated as host-provided. That is the fail-closed leg
/// of the rule — an ambient global out of a `.d.ts`, a script-tag
/// global, a typo'd reference all land on the safe side.
fn sg_callee_ctx(w : SgWalker) -> CalleeCtx {
  {
    roots: w.host_roots,
    host_returning: w.host_returning,
    resolves: fn(n) { sg_lookup(w.g, w.current_scope, n) is Some(_) },
  }
}

///|
/// Record every argument of `expr` as escaping, when `expr` is a call
/// whose callee the analysis can't prove internal.
fn sg_record_foreign_call_args(w : SgWalker, expr : @ast.TsExpr) -> Unit {
  if !call_site_is_foreign(expr, sg_callee_ctx(w)) {
    return
  }
  match call_site_args(expr) {
    Some(args) =>
      for a in args {
        w.scoped_sinks.push(
          ({ expr: a, observation: ExternalCallArg }, w.current_scope),
        )
      }
    None => ()
  }
}

///|
fn is_external_chain_for_sink(
  expr : @ast.TsExpr,
  externals : Map[String, Bool],
) -> Bool {
  match expr {
    @ast.TsExpr::Var(n) => externals.contains(n)
    PropAccess(recv, _) => is_external_chain_for_sink(recv, externals)
    MethodCall(recv, _, _) => is_external_chain_for_sink(recv, externals)
    IndexAccess(recv, _) => is_external_chain_for_sink(recv, externals)
    Call(n, _) => externals.contains(n)
    CallExpr(callee, _) => is_external_chain_for_sink(callee, externals)
    NonNull(inner)
    | OptionalChain(inner)
    | As(inner, _)
    | TypeArgs(_, inner)
    | Satisfies(inner, _) => is_external_chain_for_sink(inner, externals)
    _ => false
  }
}

///|
fn sg_visit_expr(w : SgWalker, expr : @ast.TsExpr) -> Unit {
  // Record observation sinks alongside the use walk so each sink
  // carries the scope it appeared in.
  sg_record_sinks_in_expr(w, expr)
  match expr {
    @ast.TsExpr::Var(n) => sg_record_use(w, n, Read)
    PropAccess(recv, prop) =>
      // `recv.prop` — if recv is `Var(name)`, treat as PropReceiver.
      // Otherwise recurse so deeper accesses still register.
      match recv {
        @ast.TsExpr::Var(n) => sg_record_use(w, n, PropReceiver(prop))
        _ => sg_visit_expr(w, recv)
      }
    MethodCall(recv, m, args) => {
      // `obj.method(args)` reads `obj.method` then calls it. The
      // receiver becomes a PropReceiver(method) use so Phase 4's
      // observability reserves `method` when the binding escapes.
      match recv {
        @ast.TsExpr::Var(n) => sg_record_use(w, n, PropReceiver(m))
        _ => sg_visit_expr(w, recv)
      }
      for a in args {
        sg_visit_expr(w, a)
      }
    }
    IndexAccess(recv, idx) => {
      match recv {
        @ast.TsExpr::Var(n) => sg_record_use(w, n, IndexReceiver)
        _ => sg_visit_expr(w, recv)
      }
      match idx {
        @ast.TsExpr::Var(n) => sg_record_use(w, n, IndexKey)
        _ => sg_visit_expr(w, idx)
      }
    }
    Call(callee, args) => {
      sg_record_use(w, callee, CallReceiver)
      for i, a in args {
        sg_visit_expr_as_arg(w, a, callee, i)
      }
    }
    CallExpr(callee, args) => {
      sg_visit_expr(w, callee)
      for i, a in args {
        let callee_id = match callee {
          @ast.TsExpr::Var(n) => sg_lookup(w.g, w.current_scope, n)
          _ => None
        }
        match callee_id {
          Some(id) => {
            // Already recorded the receiver use above; here we add
            // the arg-flow edge into the callee's parameter slot.
            for src in expr_immediate_sources(w, a) {
              w.g.flow_edges.push({ from: src, to: FuncArg(id, i) })
            }
            sg_visit_expr(w, a)
          }
          None => sg_visit_expr(w, a)
        }
      }
    }
    New(name, args) => {
      sg_record_use(w, name, NewReceiver)
      for a in args {
        sg_visit_expr(w, a)
      }
    }
    NewExpr(callee, args) => {
      sg_visit_expr(w, callee)
      for a in args {
        sg_visit_expr(w, a)
      }
    }
    AssignExpr(name, rhs) => {
      sg_record_use(w, name, AssignLHS)
      match sg_lookup(w.g, w.current_scope, name) {
        Some(id) => {
          w.g.symbols[id].reassigned = true
          w.g.symbols[id].reassign_rhs.push(rhs)
          for src in expr_immediate_sources(w, rhs) {
            w.g.flow_edges.push({ from: src, to: SymVal(id) })
          }
        }
        None => ()
      }
      sg_visit_expr(w, rhs)
    }
    AssignPattern(_b, rhs) => sg_visit_expr(w, rhs)
    CompoundAssignExpr(target, _, rhs) => {
      sg_visit_expr(w, target)
      sg_visit_expr(w, rhs)
    }
    PropAssignExpr(target, prop, rhs) => {
      match target {
        @ast.TsExpr::Var(n) => sg_record_use(w, n, PropReceiver(prop))
        _ => sg_visit_expr(w, target)
      }
      sg_visit_expr(w, rhs)
      sg_record_write_into(w, target, rhs)
    }
    IndexAssignExpr(target, idx, rhs) => {
      sg_visit_expr(w, target)
      sg_visit_expr(w, idx)
      sg_visit_expr(w, rhs)
      sg_record_write_into(w, target, rhs)
    }
    BinOp(_, l, r) => {
      sg_visit_expr(w, l)
      sg_visit_expr(w, r)
    }
    UnaryOp(_, inner)
    | Spread(inner)
    | Await(inner)
    | YieldStar(inner)
    | As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner)
    | TypeArgs(_, inner)
    | PureCall(inner) => sg_visit_expr(w, inner)
    Yield(Some(inner)) => sg_visit_expr(w, inner)
    Yield(None) => ()
    Cond(c, t, e) => {
      sg_visit_expr(w, c)
      sg_visit_expr(w, t)
      sg_visit_expr(w, e)
    }
    Seq(a, b) => {
      sg_visit_expr(w, a)
      sg_visit_expr(w, b)
    }
    ArrayLit(items) =>
      for it in items {
        sg_visit_expr(w, it)
      }
    ObjectLit(entries) =>
      for ent in entries {
        sg_visit_expr(w, ent.1)
      }
    ComputedProp(k, v) => {
      sg_visit_expr(w, k)
      sg_visit_expr(w, v)
    }
    ArrowFunc(params, _, body, _is_async) => {
      let outer_scope = w.current_scope
      let outer_func = w.enclosing_func
      w.in_closure_depth = w.in_closure_depth + 1
      w.current_scope = sg_new_scope(w.g, Some(outer_scope), Function)
      // Arrow has no own SymbolId for the function value itself;
      // returns / throws don't add func-return edges.
      w.enclosing_func = None
      for p in params {
        let pid = sg_declare(w.g, w.current_scope, p.name, Param, false)
        match p.type_ {
          @ast.TsType::Any => ()
          ty => w.g.symbols[pid].ts_type = ty
        }
      }
      match body {
        ArrowExpr(e) => sg_visit_expr(w, e)
        ArrowBlock(b) => {
          sg_declare_block_bindings(w.g, b, w.current_scope, {})
          for s in b.stmts {
            sg_visit_stmt(w, s)
          }
        }
      }
      w.current_scope = outer_scope
      w.enclosing_func = outer_func
      w.in_closure_depth = w.in_closure_depth - 1
    }
    FuncExpr(f) => sg_visit_function_body(w, f)
    DynamicImport(spec, opts) => {
      sg_visit_expr(w, spec)
      match opts {
        Some(o) => sg_visit_expr(w, o)
        None => ()
      }
    }
    TaggedTemplate(tag, _, _, exprs) => {
      sg_visit_expr(w, tag)
      for e in exprs {
        sg_visit_expr(w, e)
      }
    }
    TemplateLiteral(_, exprs) =>
      for e in exprs {
        sg_visit_expr(w, e)
      }
    NativeClassExpr(decl, ctor) => {
      match decl.base_expr {
        Some(b) => sg_visit_expr(w, b)
        None => ()
      }
      match ctor {
        Some(f) => sg_visit_function_body(w, f)
        None => ()
      }
      for m in decl.methods {
        match m.body {
          Some(b) => {
            // Class methods declare their params as Symbols inside a
            // fresh Function scope so the type-aware passes (e.g.
            // External-observation narrowing via the param
            // annotation) see them the same way they see arrow /
            // function-decl params.
            let outer = w.current_scope
            w.current_scope = sg_new_scope(w.g, Some(outer), Function)
            for p in m.params {
              let pid = sg_declare(w.g, w.current_scope, p.0, Param, false)
              match p.1 {
                @ast.TsType::Any => ()
                ty => w.g.symbols[pid].ts_type = ty
              }
            }
            sg_declare_block_bindings(w.g, b, w.current_scope, {})
            for s in b.stmts {
              sg_visit_stmt(w, s)
            }
            w.current_scope = outer
          }
          None => ()
        }
      }
      for sf in decl.static_field_inits {
        sg_visit_expr(w, sf.1)
      }
    }
    JsxElement(_, _, _) => ()
    _ => ()
  }
}

///|
fn sg_visit_expr_as_arg(
  w : SgWalker,
  arg : @ast.TsExpr,
  callee_name : String,
  arg_index : Int,
) -> Unit {
  match sg_lookup(w.g, w.current_scope, callee_name) {
    Some(id) =>
      for src in expr_immediate_sources(w, arg) {
        w.g.flow_edges.push({ from: src, to: FuncArg(id, arg_index) })
      }
    None => ()
  }
  sg_visit_expr(w, arg)
}

///|
fn sg_visit_function_body(w : SgWalker, f : @ast.TsFunc) -> Unit {
  // The named binding (if any) is declared in the enclosing scope
  // by sg_declare_stmt_bindings — here we open the function frame.
  let outer_scope = w.current_scope
  let outer_func = w.enclosing_func
  w.in_closure_depth = w.in_closure_depth + 1
  w.current_scope = sg_new_scope(w.g, Some(outer_scope), Function)
  // Pick up the function's own SymbolId from the enclosing scope
  // so `return`/`throw` inside the body can attach edges.
  let self_id = if f.name != "" {
    sg_lookup(w.g, outer_scope, f.name)
  } else {
    None
  }
  w.enclosing_func = self_id
  // Declare params and remember their ids so `FuncInfo` can map
  // `FuncArg(fid, i)` → param symbol on the backward walk.
  let param_ids : Array[SymbolId] = []
  for p in f.params {
    let pid = sg_declare(w.g, w.current_scope, p.name, Param, false)
    match p.type_ {
      @ast.TsType::Any => ()
      ty => w.g.symbols[pid].ts_type = ty
    }
    param_ids.push(pid)
  }
  // Pre-register the FuncInfo entry so `Return(Some(e))` inside
  // the body can append to `returns` directly. Anonymous
  // functions (no `self_id`) get no entry and Phase 4 treats
  // their return as Unknown.
  match self_id {
    Some(fid) => w.g.funcs[fid] = { params: param_ids, returns: [] }
    None => ()
  }
  sg_declare_block_bindings(w.g, f.body, w.current_scope, {})
  for s in f.body.stmts {
    sg_visit_stmt(w, s)
  }
  w.current_scope = outer_scope
  w.enclosing_func = outer_func
  w.in_closure_depth = w.in_closure_depth - 1
}

///|
fn sg_record_use(w : SgWalker, name : String, context : UseContext) -> Unit {
  match sg_lookup(w.g, w.current_scope, name) {
    Some(id) => {
      w.g.symbols[id].uses.push({ scope_id: w.current_scope, context })
      if w.in_closure_depth > 0 {
        let sym = w.g.symbols[id]
        // Compare: was the binding declared OUTSIDE the current
        // closure-depth scope chain? We approximate "declared
        // above any function frame we've crossed" by checking
        // whether the binding's scope is an ancestor of the
        // walker's current scope across at least one Function
        // boundary.
        if scope_crosses_function_boundary(w.g, sym.scope_id, w.current_scope) {
          w.g.symbols[id].captured_by_closure = true
        }
      }
    }
    // Unresolved: a host global, a runtime built-in, or a binding
    // some pass deleted while leaving this reference behind. The three
    // are indistinguishable here — the caller has the host's name list
    // — so record it and let `verify_block` decide.
    None =>
      if not(w.g.unresolved.contains(name)) {
        w.g.unresolved[name] = w.current_scope
      }
  }
}

///|
/// True when traversing from `current` up to `decl_scope` crosses a
/// `Function` scope boundary — i.e. the use is in a closure.
fn scope_crosses_function_boundary(
  g : SymbolGraph,
  decl_scope : ScopeId,
  current : ScopeId,
) -> Bool {
  let mut cur = current
  while cur != decl_scope {
    let s = g.scopes[cur]
    if s.kind is Function {
      return true
    }
    match s.parent {
      Some(p) => cur = p
      None => return false
    }
  }
  false
}

// ---------------------------------------------------------------------------
// Source extraction: what flow nodes contribute the VALUE of an expr?
// ---------------------------------------------------------------------------

///|
/// Sources for a FLOW EDGE, which has to see into a literal.
///
/// `collect_immediate_sources` answers `Literal(LitObject)` for an
/// object or array literal and stops. That is the right answer for the
/// questions it was written for — the numeric and container inferences
/// ask "what KIND of value is this", and an object literal is a fresh
/// object whatever is inside it. A flow edge asks something else: "if
/// this value is observed, what else becomes observed". For
/// `{ ...bag, g: c }` the answer includes `bag`.
///
/// Kept as a separate function rather than widening the shared one,
/// because widening it would change what those other inferences see.
fn collect_flow_sources(
  w : SgWalker,
  expr : @ast.TsExpr,
  out : Array[FlowNode],
) -> Unit {
  match expr {
    ObjectLit(entries) =>
      for ent in entries {
        collect_flow_sources(w, ent.1, out)
      }
    ArrayLit(items) =>
      for it in items {
        collect_flow_sources(w, it, out)
      }
    Spread(inner) => collect_flow_sources(w, inner, out)
    ComputedProp(_, v) => collect_flow_sources(w, v, out)
    Cond(_, t, e) => {
      collect_flow_sources(w, t, out)
      collect_flow_sources(w, e, out)
    }
    As(inner, _) | Satisfies(inner, _) | NonNull(inner) | TypeArgs(_, inner) =>
      collect_flow_sources(w, inner, out)
    _ => collect_immediate_sources(w, expr, out)
  }
}

///|
fn expr_flow_sources(w : SgWalker, expr : @ast.TsExpr) -> Array[FlowNode] {
  let out : Array[FlowNode] = []
  collect_flow_sources(w, expr, out)
  out
}

///|
/// `target.prop = val` / `target[i] = val` — the written value is now
/// reachable from `target`, so an observation of `target` observes it.
///
/// This edge was missing entirely. The write side recorded the target as
/// a `PropReceiver` use, which keeps the TARGET's own keys reserved, and
/// visited `val` for its own uses — but nothing connected the two. So
///
///   obj['q'] = { ...bag, g7: arr[2] };
///   console.log([obj]);
///
/// reserved `p` / `q` / `r` and renamed `alpha`, deleting `beta`,
/// `gamma` and `g7` as dead. `obj` is observed recursively; what was
/// written into it was not. Found by `just fuzz-mangle`.
fn sg_record_write_into(
  w : SgWalker,
  target : @ast.TsExpr,
  val : @ast.TsExpr,
) -> Unit {
  match sg_assign_target_root(w, target) {
    Some(id) => {
      for src in expr_flow_sources(w, val) {
        w.g.flow_edges.push({ from: src, to: SymVal(id) })
      }
      // The edge covers what the value REFERS to. An object literal
      // written here also introduces keys of its own — `g7` in
      // `obj.q = { ...bag, g7: v }` names nothing else in the bundle,
      // so nothing else can keep it alive.
      w.g.symbols[id].written_values.push(val)
    }
    None => ()
  }
}

///|
/// The binding a write ultimately lands in: `o.a.b = v` writes into
/// `o`, so `o`'s observability has to reach `v`.
fn sg_assign_target_root(w : SgWalker, target : @ast.TsExpr) -> SymbolId? {
  match target {
    @ast.TsExpr::Var(n) => sg_lookup(w.g, w.current_scope, n)
    @ast.TsExpr::PropAccess(recv, _) => sg_assign_target_root(w, recv)
    @ast.TsExpr::IndexAccess(recv, _) => sg_assign_target_root(w, recv)
    @ast.TsExpr::As(inner, _)
    | @ast.TsExpr::Satisfies(inner, _)
    | @ast.TsExpr::NonNull(inner)
    | @ast.TsExpr::TypeArgs(_, inner)
    | @ast.TsExpr::OptionalChain(inner) => sg_assign_target_root(w, inner)
    _ => None
  }
}

///|
/// Compute the set of `FlowNode`s that the expression's value could
/// come from. For `a` it's `[SymVal(a)]`; for `f()` it's the
/// callee's `FuncReturn`; for a literal it's `[Literal]`. Phase 3
/// uses this to draw the right inbound edges for assignments.
fn expr_immediate_sources(w : SgWalker, expr : @ast.TsExpr) -> Array[FlowNode] {
  let out : Array[FlowNode] = []
  collect_immediate_sources(w, expr, out)
  out
}

///|
fn collect_immediate_sources(
  w : SgWalker,
  expr : @ast.TsExpr,
  out : Array[FlowNode],
) -> Unit {
  match expr {
    @ast.TsExpr::Var(n) =>
      match sg_lookup(w.g, w.current_scope, n) {
        Some(id) =>
          if w.g.external_bindings.contains(id) {
            out.push(External)
          } else {
            out.push(SymVal(id))
          }
        None => out.push(Unknown)
      }
    Call(callee, _) =>
      match sg_lookup(w.g, w.current_scope, callee) {
        Some(id) =>
          if w.g.external_bindings.contains(id) {
            out.push(External)
          } else {
            out.push(FuncReturn(id))
          }
        None => out.push(Unknown)
      }
    CallExpr(callee, _) =>
      match callee {
        @ast.TsExpr::Var(n) =>
          match sg_lookup(w.g, w.current_scope, n) {
            Some(id) =>
              if w.g.external_bindings.contains(id) {
                out.push(External)
              } else {
                out.push(FuncReturn(id))
              }
            None => out.push(Unknown)
          }
        _ => out.push(Unknown)
      }
    MethodCall(_, _, _) => out.push(Unknown)
    New(_, _) | NewExpr(_, _) => out.push(Unknown)
    NumberLit(_) | IntLit(_) | BigIntLit(_) => out.push(Literal(LitNumeric))
    StringLit(_) | TemplateLiteral(_, _) => out.push(Literal(LitString))
    BoolLit(_) => out.push(Literal(LitBool))
    NullLit => out.push(Literal(LitNull))
    ArrayHole => out.push(Literal(LitOther))
    ObjectLit(_) | ArrayLit(_) => out.push(Literal(LitObject))
    ArrowFunc(_, _, _, _) | FuncExpr(_) => out.push(Literal(LitObject))
    Cond(_, t, e) => {
      collect_immediate_sources(w, t, out)
      collect_immediate_sources(w, e, out)
    }
    Seq(_, b) => collect_immediate_sources(w, b, out)
    BinOp(op, l, r) =>
      // `||` / `&&` / `??` propagate operand values; arithmetic
      // produces a fresh value whose type depends on the operator.
      match op {
        Or | And | Coalesce => {
          collect_immediate_sources(w, l, out)
          collect_immediate_sources(w, r, out)
        }
        // The arithmetic / bitwise binary operators always
        // produce a number (`+` is the trap — both operands may
        // be strings, so leave its result as Other).
        Sub
        | Mul
        | Div
        | Mod
        | Pow
        | BitAnd
        | BitOr
        | BitXor
        | Shl
        | Shr
        | UShr => out.push(Literal(LitNumeric))
        // Comparison / instanceof yields a boolean.
        BinEq
        | BinNe
        | AbstractEq
        | AbstractNe
        | BinLt
        | BinLe
        | BinGt
        | BinGe
        | Instanceof
        | In => out.push(Literal(LitBool))
        // `+` could be string concat or numeric — leave to the
        // numeric-vars pass which inspects the AST directly.
        Add => out.push(Literal(LitOther))
      }
    UnaryOp(op, _) =>
      match op {
        Neg | Plus | BitwiseNot | PreInc | PreDec | PostInc | PostDec =>
          out.push(Literal(LitNumeric))
        Not => out.push(Literal(LitBool))
        Typeof => out.push(Literal(LitString))
        Void => out.push(Literal(LitNull))
        Delete => out.push(Literal(LitBool))
      }
    As(inner, _)
    | Satisfies(inner, _)
    | NonNull(inner)
    | OptionalChain(inner)
    | PureCall(inner)
    | TypeArgs(_, inner)
    | Await(inner) => collect_immediate_sources(w, inner, out)
    Yield(_) | YieldStar(_) => out.push(Unknown)
    PropAccess(_, _) | IndexAccess(_, _) =>
      // Reading a property of some value — the resulting value's
      // "source" is the receiver chain. Phase 3 doesn't have
      // per-property flow yet; conservatively report Unknown so
      // downstream treats it as "could be anything".
      out.push(Unknown)
    _ => out.push(Unknown)
  }
}
