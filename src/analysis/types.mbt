// Static analysis types for binding analysis and type inference.

///|
/// Source location information for error reporting.
pub(all) struct SourceLoc {
  offset : Int
  line : Int
  column : Int
} derive(Eq, Debug)

///|
/// Create SourceLoc from token offset by scanning source string.
pub fn SourceLoc::from_offset(source : String, offset : Int) -> SourceLoc {
  let mut line = 1
  let mut col = 1
  let mut i = 0
  while i < offset && i < source.length() {
    if source[i] == '\n' {
      line += 1
      col = 1
    } else {
      col += 1
    }
    i += 1
  }
  { offset, line, column: col }
}

///|
/// Create SourceLoc with unknown position.
pub fn SourceLoc::unknown() -> SourceLoc {
  { offset: -1, line: 0, column: 0 }
}

///|
/// Declaration kind for variable bindings.
pub(all) enum DeclKind {
  Var
  Let
  Const
  Param
  Function
  CatchParam
} derive(Eq, Debug)

///|
/// Information about a variable binding in scope.
pub(all) struct BindingInfo {
  name : String
  kind : DeclKind
  type_ : @ast.TsType
  is_initialized : Bool
  loc : SourceLoc
} derive(Debug)

///|
/// Kind of scope for different contexts.
pub(all) enum ScopeKind {
  Global
  Module
  Function
  Block
  Catch
  With
  ForLoop
} derive(Eq, Debug)

///|
/// Scope for tracking variable bindings.
pub(all) struct Scope {
  parent : Scope?
  bindings : Map[String, BindingInfo]
  kind : ScopeKind
}

///|
/// Create a new scope with optional parent.
pub fn Scope::new(kind : ScopeKind, parent : Scope?) -> Scope {
  { parent, bindings: {}, kind }
}

///|
/// Create global scope.
pub fn Scope::global() -> Scope {
  Scope::new(Global, None)
}

///|
/// Define a binding in current scope.
pub fn Scope::add_binding(
  self : Scope,
  name : String,
  info : BindingInfo,
) -> Unit {
  self.bindings[name] = info
}

///|
/// Check if name is defined in current scope (not parent).
pub fn Scope::has_local(self : Scope, name : String) -> Bool {
  self.bindings.contains(name)
}

///|
/// Get binding from current scope only.
pub fn Scope::get_local(self : Scope, name : String) -> BindingInfo? {
  self.bindings.get(name)
}

///|
/// Lookup binding in current scope and all parent scopes.
pub fn Scope::lookup(self : Scope, name : String) -> BindingInfo? {
  match self.bindings.get(name) {
    Some(info) => Some(info)
    None =>
      match self.parent {
        Some(p) => p.lookup(name)
        None => None
      }
  }
}

///|
/// Find the nearest enclosing function scope.
pub fn Scope::find_function_scope(self : Scope) -> Scope? {
  if self.kind == Function {
    Some(self)
  } else {
    match self.parent {
      Some(p) => p.find_function_scope()
      None => None
    }
  }
}

///|
/// Check if a name is defined as uninitialized (TDZ).
pub fn Scope::is_uninitialized(self : Scope, name : String) -> Bool {
  match self.bindings.get(name) {
    Some(info) => !info.is_initialized
    None =>
      match self.parent {
        Some(p) => p.is_uninitialized(name)
        None => false
      }
  }
}

///|
/// Mark a binding as initialized.
pub fn Scope::initialize(self : Scope, name : String) -> Unit {
  match self.bindings.get(name) {
    Some(info) =>
      self.bindings[name] = {
        name: info.name,
        kind: info.kind,
        type_: info.type_,
        is_initialized: true,
        loc: info.loc,
      }
    None =>
      match self.parent {
        Some(p) => p.initialize(name)
        None => ()
      }
  }
}

///|
/// Check if binding is const.
pub fn Scope::is_const(self : Scope, name : String) -> Bool {
  match self.bindings.get(name) {
    Some(info) => info.kind == Const
    None =>
      match self.parent {
        Some(p) => p.is_const(name)
        None => false
      }
  }
}

///|
/// Analysis context for tracking state during analysis.
pub(all) struct AnalysisCtx {
  errors : Array[AnalysisError]
  warnings : Array[AnalysisError]
  mut current_scope : Scope
  source : String
  mut in_loop : Bool
  mut in_switch : Bool
  mut is_strict : Bool
  mut expected_return_type : @ast.TsType?
  mut current_function_name : String?
}

///|
/// Forward declaration for AnalysisError (defined in errors.mbt).
pub(all) struct AnalysisError {
  kind : AnalysisErrorKind
  message : String
  loc : SourceLoc
} derive(Debug)

///|
/// Error kind enumeration.
pub(all) enum AnalysisErrorKind {
  SyntaxError
  ReferenceError
  TypeError
  UnsupportedFeature
  Warning
} derive(Eq, Debug)

///|
/// Create a new analysis context.
pub fn AnalysisCtx::new(source : String) -> AnalysisCtx {
  {
    errors: [],
    warnings: [],
    current_scope: Scope::global(),
    source,
    in_loop: false,
    in_switch: false,
    is_strict: false,
    expected_return_type: None,
    current_function_name: None,
  }
}

///|
/// Push a new scope.
pub fn AnalysisCtx::push_scope(self : AnalysisCtx, kind : ScopeKind) -> Unit {
  self.current_scope = Scope::new(kind, Some(self.current_scope))
}

///|
/// Pop current scope and return to parent.
pub fn AnalysisCtx::pop_scope(self : AnalysisCtx) -> Unit {
  match self.current_scope.parent {
    Some(p) => self.current_scope = p
    None => () // Cannot pop global scope
  }
}

///|
/// Add an error to the context.
pub fn AnalysisCtx::add_error(
  self : AnalysisCtx,
  kind : AnalysisErrorKind,
  message : String,
  offset : Int,
) -> Unit {
  let loc = SourceLoc::from_offset(self.source, offset)
  self.errors.push({ kind, message, loc })
}

///|
/// Add error with explicit location.
pub fn AnalysisCtx::add_error_at(
  self : AnalysisCtx,
  kind : AnalysisErrorKind,
  message : String,
  loc : SourceLoc,
) -> Unit {
  self.errors.push({ kind, message, loc })
}

///|
/// Add a warning to the context.
pub fn AnalysisCtx::add_warning(
  self : AnalysisCtx,
  message : String,
  offset : Int,
) -> Unit {
  let loc = SourceLoc::from_offset(self.source, offset)
  self.warnings.push({ kind: Warning, message, loc })
}

///|
/// Check if there are any errors.
pub fn AnalysisCtx::has_errors(self : AnalysisCtx) -> Bool {
  self.errors.length() > 0
}

///|
/// Define a binding in current scope with error checking.
pub fn AnalysisCtx::define_binding(
  self : AnalysisCtx,
  name : String,
  kind : DeclKind,
  type_ : @ast.TsType,
  initialized : Bool,
  offset : Int,
) -> Unit {
  let loc = SourceLoc::from_offset(self.source, offset)
  let info = { name, kind, type_, is_initialized: initialized, loc }

  // Check for duplicate declaration in same scope
  match self.current_scope.get_local(name) {
    Some(existing) =>
      // var can be redeclared in same scope
      if kind != Var && existing.kind != Var {
        self.add_error_at(
          SyntaxError,
          "Identifier '\{name}' has already been declared",
          loc,
        )
      }
    None => ()
  }
  self.current_scope.add_binding(name, info)
}

///|
/// Lookup a binding and check for TDZ errors.
pub fn AnalysisCtx::lookup_binding(
  self : AnalysisCtx,
  name : String,
  offset : Int,
) -> BindingInfo? {
  match self.current_scope.lookup(name) {
    Some(info) => {
      // Check for TDZ violation
      if !info.is_initialized && (info.kind == Let || info.kind == Const) {
        self.add_error(
          ReferenceError,
          "Cannot access '\{name}' before initialization",
          offset,
        )
      }
      Some(info)
    }
    None => None
  }
}
