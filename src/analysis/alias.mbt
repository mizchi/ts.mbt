// Alias analysis - track which variables may point to the same object.

///|
/// Alias set representing variables that may alias each other.
pub(all) struct AliasSet {
  // Variables in this set
  mut variables : Array[String]
  // Is this set known to be a unique (non-aliased) value?
  mut is_unique : Bool
}

///|
pub fn AliasSet::new() -> AliasSet {
  { variables: [], is_unique: true }
}

///|
pub fn AliasSet::singleton(name : String) -> AliasSet {
  { variables: [name], is_unique: true }
}

///|
/// Alias analysis result for a function.
pub(all) struct AliasInfo {
  // Map from variable to its alias set ID
  var_to_set : Map[String, Int]
  // All alias sets
  sets : Array[AliasSet]
  // Variables that escape (passed to functions, returned, stored in objects)
  escaped : Array[String]
  // Variables that are definitely unique (no aliases)
  unique : Array[String]
}

///|
pub fn AliasInfo::new() -> AliasInfo {
  { var_to_set: {}, sets: [], escaped: [], unique: [] }
}

///|
fn AliasInfo::get_or_create_set(self : AliasInfo, name : String) -> Int {
  match self.var_to_set.get(name) {
    Some(id) => id
    None => {
      let id = self.sets.length()
      self.sets.push(AliasSet::singleton(name))
      self.var_to_set[name] = id
      id
    }
  }
}

///|
fn AliasInfo::merge_sets(self : AliasInfo, id1 : Int, id2 : Int) -> Unit {
  if id1 == id2 {
    return
  }
  // Merge smaller into larger
  let (from, to) = if self.sets[id1].variables.length() <
    self.sets[id2].variables.length() {
    (id1, id2)
  } else {
    (id2, id1)
  }
  // Move all variables from 'from' to 'to'
  for v in self.sets[from].variables {
    if !self.sets[to].variables.contains(v) {
      self.sets[to].variables.push(v)
    }
    self.var_to_set[v] = to
  }
  self.sets[to].is_unique = false
  self.sets[from].variables = []
}

///|
fn AliasInfo::mark_escaped(self : AliasInfo, name : String) -> Unit {
  if !self.escaped.contains(name) {
    self.escaped.push(name)
  }
  // Mark the entire alias set as non-unique
  match self.var_to_set.get(name) {
    Some(id) => self.sets[id].is_unique = false
    None => ()
  }
}

///|
/// Analyze a function for aliases.
pub fn analyze_aliases(func : @ast.TsFunc) -> AliasInfo {
  let info = AliasInfo::new()
  // Add parameters - they may alias external values
  for param in func.params {
    let id = info.get_or_create_set(param.name)
    // Object/array parameters are not unique
    match param.type_ {
      @ast.TsType::Array(_)
      | @ast.TsType::Object(_)
      | @ast.TsType::Any
      | @ast.TsType::Named(_) => info.sets[id].is_unique = false
      _ => ()
    }
  }
  // Analyze statements
  for stmt in func.body.stmts {
    analyze_stmt_aliases(stmt, info)
  }
  // Collect unique variables
  for entry in info.var_to_set {
    let name = entry.0
    let set_id = entry.1
    if info.sets[set_id].is_unique && !info.escaped.contains(name) {
      info.unique.push(name)
    }
  }
  info
}

///|
fn analyze_stmt_aliases(stmt : @ast.TsStmt, info : AliasInfo) -> Unit {
  match stmt {
    @ast.TsStmt::Var(binding, _, init)
    | @ast.TsStmt::Let(binding, _, init)
    | @ast.TsStmt::Const(binding, _, init) => {
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
        let _ = info.get_or_create_set(name)
        // Check if init creates an alias
        analyze_assignment_alias(name, init, info)
      }
    }
    @ast.TsStmt::Assign(name, value) => {
      let _ = info.get_or_create_set(name)
      analyze_assignment_alias(name, value, info)
    }
    @ast.TsStmt::Expr(e) => analyze_expr_escapes(e, info)
    @ast.TsStmt::Return(Some(e)) =>
      // Returned values escape
      mark_expr_escaped_alias(e, info)
    @ast.TsStmt::If(cond, then_block, else_block) => {
      analyze_expr_escapes(cond, info)
      for s in then_block.stmts {
        analyze_stmt_aliases(s, info)
      }
      match else_block {
        Some(eb) =>
          for s in eb.stmts {
            analyze_stmt_aliases(s, info)
          }
        None => ()
      }
    }
    @ast.TsStmt::While(cond, body) | @ast.TsStmt::DoWhile(cond, body) => {
      analyze_expr_escapes(cond, info)
      for s in body.stmts {
        analyze_stmt_aliases(s, info)
      }
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      match init {
        Some(i) => analyze_stmt_aliases(i, info)
        None => ()
      }
      match cond {
        Some(c) => analyze_expr_escapes(c, info)
        None => ()
      }
      match update {
        Some(u) => analyze_stmt_aliases(u, info)
        None => ()
      }
      for s in body.stmts {
        analyze_stmt_aliases(s, info)
      }
    }
    @ast.TsStmt::ForOf(_, binding, _, iter, body)
    | @ast.TsStmt::ForAwaitOf(_, binding, _, iter, body)
    | @ast.TsStmt::ForIn(_, binding, _, iter, body) => {
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
        let id = info.get_or_create_set(name)
        // Loop variable may alias array elements
        info.sets[id].is_unique = false
      }
      analyze_expr_escapes(iter, info)
      for s in body.stmts {
        analyze_stmt_aliases(s, info)
      }
    }
    @ast.TsStmt::Block(block) =>
      for s in block.stmts {
        analyze_stmt_aliases(s, info)
      }
    @ast.TsStmt::Try(try_block, binding, catch_block, finally_block) => {
      for s in try_block.stmts {
        analyze_stmt_aliases(s, info)
      }
      match binding {
        Some(b) => {
          let names : Array[String] = []
          collect_binding_names(b, names)
          for name in names {
            let id = info.get_or_create_set(name)
            info.sets[id].is_unique = false // Exception may be any object
          }
        }
        None => ()
      }
      match catch_block {
        Some(cb) =>
          for s in cb.stmts {
            analyze_stmt_aliases(s, info)
          }
        None => ()
      }
      match finally_block {
        Some(fb) =>
          for s in fb.stmts {
            analyze_stmt_aliases(s, info)
          }
        None => ()
      }
    }
    @ast.TsStmt::Throw(e) => mark_expr_escaped_alias(e, info)
    _ => ()
  }
}

///|
fn analyze_assignment_alias(
  target : String,
  value : @ast.TsExpr,
  info : AliasInfo,
) -> Unit {
  match value {
    // Direct variable copy creates alias
    @ast.TsExpr::Var(source) => {
      let target_id = info.get_or_create_set(target)
      let source_id = info.get_or_create_set(source)
      info.merge_sets(target_id, source_id)
    }
    // Literals are unique
    @ast.TsExpr::IntLit(_)
    | @ast.TsExpr::NumberLit(_)
    | @ast.TsExpr::StringLit(_)
    | @ast.TsExpr::BoolLit(_)
    | @ast.TsExpr::NullLit => ()
    // New object/array is unique (initially)
    @ast.TsExpr::ArrayLit(elements) =>
      // But elements may escape into the array
      for elem in elements {
        mark_expr_escaped_alias(elem, info)
      }
    @ast.TsExpr::ObjectLit(props) =>
      for prop in props {
        mark_expr_escaped_alias(prop.1, info)
      }
    // Function call result may be aliased
    @ast.TsExpr::Call(_, args) | @ast.TsExpr::CallExpr(_, args) => {
      let id = info.get_or_create_set(target)
      info.sets[id].is_unique = false
      // Arguments escape
      for arg in args {
        mark_expr_escaped_alias(arg, info)
      }
    }
    @ast.TsExpr::MethodCall(recv, _, args) => {
      let id = info.get_or_create_set(target)
      info.sets[id].is_unique = false
      analyze_expr_escapes(recv, info)
      for arg in args {
        mark_expr_escaped_alias(arg, info)
      }
    }
    // Property access may return aliased value
    @ast.TsExpr::PropAccess(obj, _) | @ast.TsExpr::IndexAccess(obj, _) => {
      let id = info.get_or_create_set(target)
      info.sets[id].is_unique = false
      analyze_expr_escapes(obj, info)
    }
    // Conditional - may be either branch
    @ast.TsExpr::Cond(_, then_e, else_e) => {
      analyze_assignment_alias(target, then_e, info)
      analyze_assignment_alias(target, else_e, info)
    }
    _ => {
      // Unknown - assume not unique
      let id = info.get_or_create_set(target)
      info.sets[id].is_unique = false
    }
  }
}

///|
fn analyze_expr_escapes(expr : @ast.TsExpr, info : AliasInfo) -> Unit {
  match expr {
    @ast.TsExpr::Call(_, args) | @ast.TsExpr::CallExpr(_, args) =>
      for arg in args {
        mark_expr_escaped_alias(arg, info)
      }
    @ast.TsExpr::MethodCall(recv, _, args) => {
      analyze_expr_escapes(recv, info)
      for arg in args {
        mark_expr_escaped_alias(arg, info)
      }
    }
    @ast.TsExpr::BinOp(_, left, right) => {
      analyze_expr_escapes(left, info)
      analyze_expr_escapes(right, info)
    }
    @ast.TsExpr::UnaryOp(_, operand) => analyze_expr_escapes(operand, info)
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      analyze_expr_escapes(cond, info)
      analyze_expr_escapes(then_e, info)
      analyze_expr_escapes(else_e, info)
    }
    @ast.TsExpr::PropAccess(obj, _) => analyze_expr_escapes(obj, info)
    @ast.TsExpr::IndexAccess(arr, idx) => {
      analyze_expr_escapes(arr, info)
      analyze_expr_escapes(idx, info)
    }
    _ => ()
  }
}

///|
fn mark_expr_escaped_alias(expr : @ast.TsExpr, info : AliasInfo) -> Unit {
  match expr {
    @ast.TsExpr::Var(name) => info.mark_escaped(name)
    @ast.TsExpr::ArrayLit(elements) =>
      for elem in elements {
        mark_expr_escaped_alias(elem, info)
      }
    @ast.TsExpr::ObjectLit(props) =>
      for prop in props {
        mark_expr_escaped_alias(prop.1, info)
      }
    @ast.TsExpr::PropAccess(obj, _) => mark_expr_escaped_alias(obj, info)
    @ast.TsExpr::IndexAccess(arr, _) => mark_expr_escaped_alias(arr, info)
    @ast.TsExpr::Cond(_, then_e, else_e) => {
      mark_expr_escaped_alias(then_e, info)
      mark_expr_escaped_alias(else_e, info)
    }
    @ast.TsExpr::Call(_, args) | @ast.TsExpr::CallExpr(_, args) =>
      for arg in args {
        mark_expr_escaped_alias(arg, info)
      }
    @ast.TsExpr::MethodCall(recv, _, args) => {
      mark_expr_escaped_alias(recv, info)
      for arg in args {
        mark_expr_escaped_alias(arg, info)
      }
    }
    _ => ()
  }
}

///|
/// Check if two variables may alias.
pub fn may_alias(info : AliasInfo, a : String, b : String) -> Bool {
  match (info.var_to_set.get(a), info.var_to_set.get(b)) {
    (Some(id_a), Some(id_b)) => id_a == id_b
    _ => false
  }
}

///|
/// Check if a variable is definitely unique (no aliases).
pub fn is_unique(info : AliasInfo, name : String) -> Bool {
  info.unique.contains(name)
}
