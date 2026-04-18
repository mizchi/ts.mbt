// Symbol usage tracking for Perceus-style drop point analysis.
// Reference: https://www.microsoft.com/en-us/research/wp-content/uploads/2020/11/perceus-tr-v1.pdf

///|
/// Kind of variable use.
pub(all) enum UseKind {
  Read // x (read value)
  Write // x = ... (assign)
  ReadWrite // x += 1 (read then write)
} derive(Eq, Debug)

///|
/// A single reference to a symbol.
pub(all) struct SymbolRef {
  loc : SourceLoc
  kind : UseKind
  in_closure : Bool // Is this use inside a nested function/arrow?
  scope_depth : Int // Depth of scope at use site
} derive(Debug)

///|
/// Usage information for a single symbol.
pub(all) struct UsageInfo {
  name : String
  decl_loc : SourceLoc
  decl_kind : DeclKind
  type_ : @ast.TsType
  // Usage statistics
  mut read_count : Int
  mut write_count : Int
  mut is_captured : Bool // Used in nested function (closure capture)
  mut is_escaped : Bool // Passed to function / returned / stored in object
  // All references in order of appearance
  references : Array[SymbolRef]
  // Computed drop points (offsets where value can be dropped)
  mut drop_points : Array[SourceLoc]
  // Last use location (for linear/affine analysis)
  mut last_use : SourceLoc?
} derive(Debug)

///|
/// Create new UsageInfo for a symbol.
pub fn UsageInfo::new(
  name : String,
  decl_loc : SourceLoc,
  decl_kind : DeclKind,
  type_ : @ast.TsType,
) -> UsageInfo {
  {
    name,
    decl_loc,
    decl_kind,
    type_,
    read_count: 0,
    write_count: 0,
    is_captured: false,
    is_escaped: false,
    references: [],
    drop_points: [],
    last_use: None,
  }
}

///|
/// Check if this symbol is used linearly (exactly once after declaration).
pub fn UsageInfo::is_linear(self : UsageInfo) -> Bool {
  self.read_count == 1 && self.write_count == 0 && !self.is_captured
}

///|
/// Check if this symbol is affine (at most once after declaration).
pub fn UsageInfo::is_affine(self : UsageInfo) -> Bool {
  self.read_count <= 1 && self.write_count == 0 && !self.is_captured
}

///|
/// Check if symbol is never used (dead code candidate).
pub fn UsageInfo::is_unused(self : UsageInfo) -> Bool {
  self.read_count == 0 && self.write_count == 0
}

///|
/// Check if symbol can be dropped immediately after last use.
pub fn UsageInfo::can_drop_at_last_use(self : UsageInfo) -> Bool {
  !self.is_captured && !self.is_escaped && self.last_use is Some(_)
}

///|
/// Symbol table tracking all symbols and their usage.
pub(all) struct SymbolTable {
  // Symbol name -> UsageInfo (scoped by unique ID)
  symbols : Map[String, UsageInfo]
  // Scope stack for tracking closure depth
  mut scope_depth : Int
  mut in_closure_depth : Int // > 0 means we're inside a nested function
  // Current source for location calculation
  source : String
}

///|
/// Create new symbol table.
pub fn SymbolTable::new(source : String) -> SymbolTable {
  { symbols: {}, scope_depth: 0, in_closure_depth: 0, source }
}

///|
/// Generate unique key for symbol (handles shadowing).
fn make_symbol_key(name : String, scope_depth : Int) -> String {
  "\{name}@\{scope_depth}"
}

///|
/// Declare a new symbol.
pub fn SymbolTable::add_symbol(
  self : SymbolTable,
  name : String,
  decl_kind : DeclKind,
  type_ : @ast.TsType,
  offset : Int,
) -> Unit {
  let loc = SourceLoc::from_offset(self.source, offset)
  let key = make_symbol_key(name, self.scope_depth)
  let info = UsageInfo::new(name, loc, decl_kind, type_)
  self.symbols[key] = info
}

///|
/// Record a use of a symbol.
pub fn SymbolTable::record_use(
  self : SymbolTable,
  name : String,
  kind : UseKind,
  offset : Int,
) -> Unit {
  let loc = SourceLoc::from_offset(self.source, offset)
  // Find the symbol (search from current scope upward)
  let mut found_key : String? = None
  for depth = self.scope_depth; depth >= 0; depth = depth - 1 {
    let key = make_symbol_key(name, depth)
    if self.symbols.contains(key) {
      found_key = Some(key)
      break
    }
  }
  match found_key {
    Some(key) =>
      match self.symbols.get(key) {
        Some(info) => {
          let in_closure = self.in_closure_depth > 0
          let ref_ : SymbolRef = {
            loc,
            kind,
            in_closure,
            scope_depth: self.scope_depth,
          }
          info.references.push(ref_)
          // Update counts
          match kind {
            Read => info.read_count += 1
            Write => info.write_count += 1
            ReadWrite => {
              info.read_count += 1
              info.write_count += 1
            }
          }
          // Track closure capture
          if in_closure {
            info.is_captured = true
          }
          // Update last use
          info.last_use = Some(loc)
        }
        None => ()
      }
    None => () // Undeclared symbol (might be global)
  }
}

///|
/// Mark symbol as escaped (returned, stored in object, passed to function).
pub fn SymbolTable::mark_escaped(self : SymbolTable, name : String) -> Unit {
  for depth = self.scope_depth; depth >= 0; depth = depth - 1 {
    let key = make_symbol_key(name, depth)
    match self.symbols.get(key) {
      Some(info) => {
        info.is_escaped = true
        return
      }
      None => ()
    }
  }
}

///|
/// Enter a new scope.
pub fn SymbolTable::enter_scope(self : SymbolTable) -> Unit {
  self.scope_depth += 1
}

///|
/// Leave current scope.
pub fn SymbolTable::leave_scope(self : SymbolTable) -> Unit {
  self.scope_depth -= 1
}

///|
/// Enter a closure (nested function/arrow).
pub fn SymbolTable::enter_closure(self : SymbolTable) -> Unit {
  self.in_closure_depth += 1
  self.enter_scope()
}

///|
/// Leave a closure.
pub fn SymbolTable::leave_closure(self : SymbolTable) -> Unit {
  self.leave_scope()
  self.in_closure_depth -= 1
}

///|
/// Compute drop points for all symbols (Perceus-style analysis).
pub fn SymbolTable::compute_drop_points(self : SymbolTable) -> Unit {
  for entry in self.symbols {
    let info = entry.1
    compute_symbol_drop_points(info)
  }
}

///|
/// Compute drop points for a single symbol.
fn compute_symbol_drop_points(info : UsageInfo) -> Unit {
  // Clear previous computation
  info.drop_points = []

  // If captured or escaped, cannot determine static drop point
  if info.is_captured || info.is_escaped {
    return
  }

  // If never used, can drop immediately after declaration
  if info.references.length() == 0 {
    info.drop_points.push(info.decl_loc)
    return
  }

  // Find last use in each control flow path
  // For now, simple case: last reference is the drop point
  match info.last_use {
    Some(loc) => info.drop_points.push(loc)
    None => ()
  }
}

///|
/// Get all unused symbols (for dead code detection).
pub fn SymbolTable::get_unused_symbols(self : SymbolTable) -> Array[UsageInfo] {
  let result : Array[UsageInfo] = []
  for entry in self.symbols {
    let info = entry.1
    if info.is_unused() && info.decl_kind != Param {
      // Don't report unused parameters (might be intentional)
      result.push(info)
    }
  }
  result
}

///|
/// Get all symbols that can be dropped at their last use.
pub fn SymbolTable::get_droppable_symbols(
  self : SymbolTable,
) -> Array[UsageInfo] {
  let result : Array[UsageInfo] = []
  for entry in self.symbols {
    let info = entry.1
    if info.can_drop_at_last_use() {
      result.push(info)
    }
  }
  result
}

///|
/// Get symbols that are used linearly (good for in-place update optimization).
pub fn SymbolTable::get_linear_symbols(self : SymbolTable) -> Array[UsageInfo] {
  let result : Array[UsageInfo] = []
  for entry in self.symbols {
    let info = entry.1
    if info.is_linear() {
      result.push(info)
    }
  }
  result
}

///|
/// Get usage info for a specific symbol.
pub fn SymbolTable::get_usage(self : SymbolTable, name : String) -> UsageInfo? {
  // Search from current scope up
  for depth = self.scope_depth; depth >= 0; depth = depth - 1 {
    let key = make_symbol_key(name, depth)
    match self.symbols.get(key) {
      Some(info) => return Some(info)
      None => ()
    }
  }
  None
}

///|
/// Summary of drop analysis for code generation.
pub(all) struct DropAnalysis {
  // Symbols that can be dropped immediately after their last use
  drop_after_use : Array[(String, SourceLoc)]
  // Symbols that are never used (can skip allocation)
  never_used : Array[String]
  // Symbols captured by closures (need heap allocation)
  captured : Array[String]
  // Symbols that escape (need ref counting or GC)
  escaped : Array[String]
}

///|
/// Generate drop analysis summary from symbol table.
pub fn SymbolTable::get_drop_analysis(self : SymbolTable) -> DropAnalysis {
  self.compute_drop_points()
  let drop_after_use : Array[(String, SourceLoc)] = []
  let never_used : Array[String] = []
  let captured : Array[String] = []
  let escaped : Array[String] = []
  for entry in self.symbols {
    let info = entry.1
    if info.is_unused() {
      never_used.push(info.name)
    } else if info.is_captured {
      captured.push(info.name)
    } else if info.is_escaped {
      escaped.push(info.name)
    } else {
      match info.last_use {
        Some(loc) => drop_after_use.push((info.name, loc))
        None => ()
      }
    }
  }
  { drop_after_use, never_used, captured, escaped }
}
