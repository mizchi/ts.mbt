// Generator analysis for AOT compilation.
// Analyzes generator functions to extract yield points and persisted variables.

///|
/// A yield point in the generator.
pub struct YieldPoint {
  /// Unique ID for this yield point
  id : Int
  /// The yield expression (None for implicit yield at end)
  expr : @ast.TsExpr?
  /// Whether this is yield* (delegate)
  is_delegate : Bool
}

///|
/// Variable that needs to be persisted across yields.
pub struct PersistedVar {
  name : String
  /// Whether this is a parameter
  is_param : Bool
}

///|
/// Result of generator analysis.
pub struct GeneratorAnalysis {
  /// All yield points in order of appearance
  yield_points : Array[YieldPoint]
  /// Variables that need to be persisted in the state struct
  persisted_vars : Array[PersistedVar]
  /// Number of states (yield_points.length + 1 for initial + 1 for done)
  state_count : Int
  /// Whether this generator can be AOT compiled
  compilable : Bool
  /// Reason if not compilable
  not_compilable_reason : String?
}

///|
/// Analyze a generator function for AOT compilation.
pub fn analyze_generator(func : @ast.TsFunc) -> GeneratorAnalysis {
  if not(func.is_generator) {
    return {
      yield_points: [],
      persisted_vars: [],
      state_count: 0,
      compilable: false,
      not_compilable_reason: Some("not a generator function"),
    }
  }
  // Collect yield points
  let yield_points : Array[YieldPoint] = []
  let _ = collect_yields_block(func.body, yield_points, 0)
  // Collect variables that need to be persisted
  let persisted_vars : Array[PersistedVar] = []
  // Add parameters
  for param in func.params {
    persisted_vars.push({ name: param.name, is_param: true })
  }
  // Collect local variables declared in the function
  collect_vars_block(func.body, persisted_vars)
  // Check if compilable
  let (compilable, reason) = check_generator_compilable(func)
  {
    yield_points,
    persisted_vars,
    state_count: yield_points.length() + 2, // initial + yields + done
    compilable,
    not_compilable_reason: reason,
  }
}

///|
fn collect_yields_block(
  block : @ast.TsBlock,
  yields : Array[YieldPoint],
  id : Int,
) -> Int {
  let mut cur = id
  for stmt in block.stmts {
    cur = collect_yields_stmt(stmt, yields, cur)
  }
  cur
}

///|
fn collect_yields_stmt(
  stmt : @ast.TsStmt,
  yields : Array[YieldPoint],
  id : Int,
) -> Int {
  match stmt {
    @ast.TsStmt::Expr(expr) => collect_yields_expr(expr, yields, id)
    @ast.TsStmt::Return(Some(expr)) => collect_yields_expr(expr, yields, id)
    @ast.TsStmt::Return(None) => id
    @ast.TsStmt::Var(_, _, init) => collect_yields_expr(init, yields, id)
    @ast.TsStmt::Let(_, _, init) => collect_yields_expr(init, yields, id)
    @ast.TsStmt::Const(_, _, init) => collect_yields_expr(init, yields, id)
    @ast.TsStmt::Assign(_, expr) => collect_yields_expr(expr, yields, id)
    @ast.TsStmt::CompoundAssign(_, _, expr) =>
      collect_yields_expr(expr, yields, id)
    @ast.TsStmt::PropAssign(obj, _, val) => {
      let id2 = collect_yields_expr(obj, yields, id)
      collect_yields_expr(val, yields, id2)
    }
    @ast.TsStmt::IndexAssign(obj, idx, val) => {
      let id2 = collect_yields_expr(obj, yields, id)
      let id3 = collect_yields_expr(idx, yields, id2)
      collect_yields_expr(val, yields, id3)
    }
    @ast.TsStmt::If(cond, then_block, else_block) => {
      let id2 = collect_yields_expr(cond, yields, id)
      let id3 = collect_yields_block(then_block, yields, id2)
      match else_block {
        Some(eb) => collect_yields_block(eb, yields, id3)
        None => id3
      }
    }
    @ast.TsStmt::Block(block) => collect_yields_block(block, yields, id)
    @ast.TsStmt::While(cond, body) => {
      let id2 = collect_yields_expr(cond, yields, id)
      collect_yields_block(body, yields, id2)
    }
    @ast.TsStmt::DoWhile(cond, body) => {
      let id2 = collect_yields_expr(cond, yields, id)
      collect_yields_block(body, yields, id2)
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      let id2 = match init {
        Some(s) => collect_yields_stmt(s, yields, id)
        None => id
      }
      let id3 = match cond {
        Some(e) => collect_yields_expr(e, yields, id2)
        None => id2
      }
      let id4 = match update {
        Some(s) => collect_yields_stmt(s, yields, id3)
        None => id3
      }
      collect_yields_block(body, yields, id4)
    }
    @ast.TsStmt::ForOf(_, _, _, iterable, body) => {
      let id2 = collect_yields_expr(iterable, yields, id)
      collect_yields_block(body, yields, id2)
    }
    @ast.TsStmt::ForAwaitOf(_, _, _, iterable, body) => {
      let id2 = collect_yields_expr(iterable, yields, id)
      collect_yields_block(body, yields, id2)
    }
    @ast.TsStmt::ForIn(_, _, _, obj, body) => {
      let id2 = collect_yields_expr(obj, yields, id)
      collect_yields_block(body, yields, id2)
    }
    @ast.TsStmt::Switch(discriminant, cases) => {
      let mut cur = collect_yields_expr(discriminant, yields, id)
      for c in cases {
        match c.test_expr {
          Some(e) => cur = collect_yields_expr(e, yields, cur)
          None => ()
        }
        cur = collect_yields_block(c.body, yields, cur)
      }
      cur
    }
    @ast.TsStmt::Try(try_block, _, catch_block, finally_block) => {
      let id2 = collect_yields_block(try_block, yields, id)
      let id3 = match catch_block {
        Some(cb) => collect_yields_block(cb, yields, id2)
        None => id2
      }
      match finally_block {
        Some(fb) => collect_yields_block(fb, yields, id3)
        None => id3
      }
    }
    @ast.TsStmt::Throw(expr) => collect_yields_expr(expr, yields, id)
    @ast.TsStmt::Label(_, inner) => collect_yields_stmt(inner, yields, id)
    _ => id
  }
}

///|
fn collect_yields_expr(
  expr : @ast.TsExpr,
  yields : Array[YieldPoint],
  id : Int,
) -> Int {
  match expr {
    @ast.TsExpr::Yield(inner) => {
      let new_id = match inner {
        Some(e) => collect_yields_expr(e, yields, id)
        None => id
      }
      yields.push({ id: new_id, expr: inner, is_delegate: false })
      new_id + 1
    }
    @ast.TsExpr::YieldStar(inner) => {
      let new_id = collect_yields_expr(inner, yields, id)
      yields.push({ id: new_id, expr: Some(inner), is_delegate: true })
      new_id + 1
    }
    @ast.TsExpr::BinOp(_, left, right) => {
      let id2 = collect_yields_expr(left, yields, id)
      collect_yields_expr(right, yields, id2)
    }
    @ast.TsExpr::UnaryOp(_, operand) => collect_yields_expr(operand, yields, id)
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      let id2 = collect_yields_expr(cond, yields, id)
      let id3 = collect_yields_expr(then_e, yields, id2)
      collect_yields_expr(else_e, yields, id3)
    }
    @ast.TsExpr::Call(_, args) => collect_yields_args(args, yields, id)
    @ast.TsExpr::New(_, args) => collect_yields_args(args, yields, id)
    @ast.TsExpr::CallExpr(callee, args) => {
      let id2 = collect_yields_expr(callee, yields, id)
      collect_yields_args(args, yields, id2)
    }
    @ast.TsExpr::NewExpr(callee, args) => {
      let id2 = collect_yields_expr(callee, yields, id)
      collect_yields_args(args, yields, id2)
    }
    @ast.TsExpr::MethodCall(receiver, _, args) => {
      let id2 = collect_yields_expr(receiver, yields, id)
      collect_yields_args(args, yields, id2)
    }
    @ast.TsExpr::PropAccess(obj, _) => collect_yields_expr(obj, yields, id)
    @ast.TsExpr::IndexAccess(obj, idx) => {
      let id2 = collect_yields_expr(obj, yields, id)
      collect_yields_expr(idx, yields, id2)
    }
    @ast.TsExpr::ArrayLit(elements) => collect_yields_args(elements, yields, id)
    @ast.TsExpr::ObjectLit(fields) => {
      let mut cur = id
      for field in fields {
        let (_, value) = field
        cur = collect_yields_expr(value, yields, cur)
      }
      cur
    }
    @ast.TsExpr::AssignExpr(_, value) => collect_yields_expr(value, yields, id)
    @ast.TsExpr::CompoundAssignExpr(left, _, right) => {
      let id2 = collect_yields_expr(left, yields, id)
      collect_yields_expr(right, yields, id2)
    }
    @ast.TsExpr::PropAssignExpr(obj, _, value) => {
      let id2 = collect_yields_expr(obj, yields, id)
      collect_yields_expr(value, yields, id2)
    }
    @ast.TsExpr::IndexAssignExpr(obj, idx, value) => {
      let id2 = collect_yields_expr(obj, yields, id)
      let id3 = collect_yields_expr(idx, yields, id2)
      collect_yields_expr(value, yields, id3)
    }
    @ast.TsExpr::Seq(left, right) => {
      let id2 = collect_yields_expr(left, yields, id)
      collect_yields_expr(right, yields, id2)
    }
    @ast.TsExpr::Spread(inner) => collect_yields_expr(inner, yields, id)
    @ast.TsExpr::Await(inner) => collect_yields_expr(inner, yields, id)
    @ast.TsExpr::TemplateLiteral(_, exprs) =>
      collect_yields_args(exprs, yields, id)
    @ast.TsExpr::TaggedTemplate(tag, _, _, exprs) => {
      let id2 = collect_yields_expr(tag, yields, id)
      collect_yields_args(exprs, yields, id2)
    }
    _ => id
  }
}

///|
fn collect_yields_args(
  args : Array[@ast.TsExpr],
  yields : Array[YieldPoint],
  id : Int,
) -> Int {
  let mut cur = id
  for arg in args {
    cur = collect_yields_expr(arg, yields, cur)
  }
  cur
}

///|
fn collect_vars_block(block : @ast.TsBlock, vars : Array[PersistedVar]) -> Unit {
  for stmt in block.stmts {
    collect_vars_stmt(stmt, vars)
  }
}

///|
fn collect_vars_stmt(stmt : @ast.TsStmt, vars : Array[PersistedVar]) -> Unit {
  match stmt {
    @ast.TsStmt::Var(binding, _, _)
    | @ast.TsStmt::Let(binding, _, _)
    | @ast.TsStmt::Const(binding, _, _) => collect_vars_binding(binding, vars)
    @ast.TsStmt::If(_, then_block, else_block) => {
      collect_vars_block(then_block, vars)
      match else_block {
        Some(eb) => collect_vars_block(eb, vars)
        None => ()
      }
    }
    @ast.TsStmt::Block(block) => collect_vars_block(block, vars)
    @ast.TsStmt::While(_, body) | @ast.TsStmt::DoWhile(_, body) =>
      collect_vars_block(body, vars)
    @ast.TsStmt::For(init, _, _, body) => {
      match init {
        Some(s) => collect_vars_stmt(s, vars)
        None => ()
      }
      collect_vars_block(body, vars)
    }
    @ast.TsStmt::ForOf(_, binding, _, _, body) => {
      collect_vars_binding(binding, vars)
      collect_vars_block(body, vars)
    }
    @ast.TsStmt::ForIn(_, binding, _, _, body) => {
      collect_vars_binding(binding, vars)
      collect_vars_block(body, vars)
    }
    @ast.TsStmt::Switch(_, cases) =>
      for c in cases {
        collect_vars_block(c.body, vars)
      }
    @ast.TsStmt::Try(try_block, catch_binding, catch_block, finally_block) => {
      collect_vars_block(try_block, vars)
      match catch_binding {
        Some(b) => collect_vars_binding(b, vars)
        None => ()
      }
      match catch_block {
        Some(cb) => collect_vars_block(cb, vars)
        None => ()
      }
      match finally_block {
        Some(fb) => collect_vars_block(fb, vars)
        None => ()
      }
    }
    @ast.TsStmt::Label(_, inner) => collect_vars_stmt(inner, vars)
    _ => ()
  }
}

///|
fn collect_vars_binding(
  binding : @ast.TsBinding,
  vars : Array[PersistedVar],
) -> Unit {
  match binding {
    @ast.TsBinding::Ident(name) => {
      // Check if already present
      for v in vars {
        if v.name == name {
          return
        }
      }
      vars.push({ name, is_param: false })
    }
    @ast.TsBinding::Array(arr) => {
      for item in arr.items {
        match item {
          Some(elem) => collect_vars_binding(elem.binding, vars)
          None => ()
        }
      }
      match arr.rest {
        Some(rest) => collect_vars_binding(rest, vars)
        None => ()
      }
    }
    @ast.TsBinding::Object(obj) => {
      for prop in obj.props {
        collect_vars_binding(prop.binding, vars)
      }
      match obj.rest {
        Some(name) => {
          for v in vars {
            if v.name == name {
              return
            }
          }
          vars.push({ name, is_param: false })
        }
        None => ()
      }
    }
    @ast.TsBinding::Target(_) => ()
  }
}

///|
/// Check if a generator can be AOT compiled.
fn check_generator_compilable(func : @ast.TsFunc) -> (Bool, String?) {
  // Check for unsupported features
  match check_block_compilable(func.body) {
    Some(reason) => (false, Some(reason))
    None => (true, None)
  }
}

///|
fn check_block_compilable(block : @ast.TsBlock) -> String? {
  for stmt in block.stmts {
    match check_stmt_compilable(stmt) {
      Some(reason) => return Some(reason)
      None => continue
    }
  }
  None
}

///|
fn check_stmt_compilable(stmt : @ast.TsStmt) -> String? {
  match stmt {
    // try/catch with yield inside is complex
    @ast.TsStmt::Try(try_block, _, catch_block, finally_block) => {
      let has_yield_in_try = block_has_yield_points(try_block)
      let has_yield_in_catch = match catch_block {
        Some(cb) => block_has_yield_points(cb)
        None => false
      }
      let has_yield_in_finally = match finally_block {
        Some(fb) => block_has_yield_points(fb)
        None => false
      }
      if has_yield_in_try || has_yield_in_catch || has_yield_in_finally {
        return Some("yield inside try/catch/finally not supported for AOT")
      }
      None
    }
    @ast.TsStmt::With(_, _) => Some("with statement not supported")
    @ast.TsStmt::If(_, then_block, else_block) => {
      match check_block_compilable(then_block) {
        Some(r) => return Some(r)
        None => ()
      }
      match else_block {
        Some(eb) => check_block_compilable(eb)
        None => None
      }
    }
    @ast.TsStmt::Block(block) => check_block_compilable(block)
    @ast.TsStmt::While(_, body) | @ast.TsStmt::DoWhile(_, body) =>
      check_block_compilable(body)
    @ast.TsStmt::For(_, _, _, body) => check_block_compilable(body)
    @ast.TsStmt::ForOf(_, _, _, _, body) => check_block_compilable(body)
    @ast.TsStmt::ForIn(_, _, _, _, body) => check_block_compilable(body)
    @ast.TsStmt::Switch(_, cases) => {
      for c in cases {
        match check_block_compilable(c.body) {
          Some(r) => return Some(r)
          None => continue
        }
      }
      None
    }
    @ast.TsStmt::Label(_, inner) => check_stmt_compilable(inner)
    _ => None
  }
}

///|
fn block_has_yield_points(block : @ast.TsBlock) -> Bool {
  for stmt in block.stmts {
    if stmt_has_yield_points(stmt) {
      return true
    }
  }
  false
}

///|
fn stmt_has_yield_points(stmt : @ast.TsStmt) -> Bool {
  match stmt {
    @ast.TsStmt::Expr(expr) => expr_has_yield_points(expr)
    @ast.TsStmt::Return(Some(expr)) => expr_has_yield_points(expr)
    @ast.TsStmt::Var(_, _, init)
    | @ast.TsStmt::Let(_, _, init)
    | @ast.TsStmt::Const(_, _, init) => expr_has_yield_points(init)
    @ast.TsStmt::Assign(_, expr) => expr_has_yield_points(expr)
    @ast.TsStmt::CompoundAssign(_, _, expr) => expr_has_yield_points(expr)
    @ast.TsStmt::PropAssign(obj, _, val) =>
      expr_has_yield_points(obj) || expr_has_yield_points(val)
    @ast.TsStmt::IndexAssign(obj, idx, val) =>
      expr_has_yield_points(obj) ||
      expr_has_yield_points(idx) ||
      expr_has_yield_points(val)
    @ast.TsStmt::If(cond, then_block, else_block) => {
      if expr_has_yield_points(cond) || block_has_yield_points(then_block) {
        return true
      }
      match else_block {
        Some(eb) => block_has_yield_points(eb)
        None => false
      }
    }
    @ast.TsStmt::Block(block) => block_has_yield_points(block)
    @ast.TsStmt::While(cond, body) | @ast.TsStmt::DoWhile(cond, body) =>
      expr_has_yield_points(cond) || block_has_yield_points(body)
    @ast.TsStmt::For(init, cond, update, body) => {
      match init {
        Some(s) => if stmt_has_yield_points(s) { return true }
        None => ()
      }
      match cond {
        Some(e) => if expr_has_yield_points(e) { return true }
        None => ()
      }
      match update {
        Some(s) => if stmt_has_yield_points(s) { return true }
        None => ()
      }
      block_has_yield_points(body)
    }
    @ast.TsStmt::ForOf(_, _, _, iterable, body) =>
      expr_has_yield_points(iterable) || block_has_yield_points(body)
    @ast.TsStmt::ForIn(_, _, _, obj, body) =>
      expr_has_yield_points(obj) || block_has_yield_points(body)
    @ast.TsStmt::Switch(discriminant, cases) => {
      if expr_has_yield_points(discriminant) {
        return true
      }
      for c in cases {
        match c.test_expr {
          Some(e) => if expr_has_yield_points(e) { return true }
          None => ()
        }
        if block_has_yield_points(c.body) {
          return true
        }
      }
      false
    }
    @ast.TsStmt::Try(try_block, _, catch_block, finally_block) => {
      if block_has_yield_points(try_block) {
        return true
      }
      match catch_block {
        Some(cb) => if block_has_yield_points(cb) { return true }
        None => ()
      }
      match finally_block {
        Some(fb) => block_has_yield_points(fb)
        None => false
      }
    }
    @ast.TsStmt::Throw(expr) => expr_has_yield_points(expr)
    @ast.TsStmt::Label(_, inner) => stmt_has_yield_points(inner)
    _ => false
  }
}

///|
fn expr_has_yield_points(expr : @ast.TsExpr) -> Bool {
  match expr {
    @ast.TsExpr::Yield(_) => true
    @ast.TsExpr::YieldStar(_) => true
    @ast.TsExpr::BinOp(_, left, right) =>
      expr_has_yield_points(left) || expr_has_yield_points(right)
    @ast.TsExpr::UnaryOp(_, operand) => expr_has_yield_points(operand)
    @ast.TsExpr::Cond(cond, then_e, else_e) =>
      expr_has_yield_points(cond) ||
      expr_has_yield_points(then_e) ||
      expr_has_yield_points(else_e)
    @ast.TsExpr::Call(_, args) | @ast.TsExpr::New(_, args) => {
      for arg in args {
        if expr_has_yield_points(arg) {
          return true
        }
      }
      false
    }
    @ast.TsExpr::CallExpr(callee, args) | @ast.TsExpr::NewExpr(callee, args) => {
      if expr_has_yield_points(callee) {
        return true
      }
      for arg in args {
        if expr_has_yield_points(arg) {
          return true
        }
      }
      false
    }
    @ast.TsExpr::MethodCall(receiver, _, args) => {
      if expr_has_yield_points(receiver) {
        return true
      }
      for arg in args {
        if expr_has_yield_points(arg) {
          return true
        }
      }
      false
    }
    @ast.TsExpr::PropAccess(obj, _) => expr_has_yield_points(obj)
    @ast.TsExpr::IndexAccess(obj, idx) =>
      expr_has_yield_points(obj) || expr_has_yield_points(idx)
    @ast.TsExpr::ArrayLit(elements) => {
      for elem in elements {
        if expr_has_yield_points(elem) {
          return true
        }
      }
      false
    }
    @ast.TsExpr::ObjectLit(fields) => {
      for field in fields {
        let (_, value) = field
        if expr_has_yield_points(value) {
          return true
        }
      }
      false
    }
    @ast.TsExpr::AssignExpr(_, value) => expr_has_yield_points(value)
    @ast.TsExpr::CompoundAssignExpr(left, _, right) =>
      expr_has_yield_points(left) || expr_has_yield_points(right)
    @ast.TsExpr::PropAssignExpr(obj, _, value) =>
      expr_has_yield_points(obj) || expr_has_yield_points(value)
    @ast.TsExpr::IndexAssignExpr(obj, idx, value) =>
      expr_has_yield_points(obj) ||
      expr_has_yield_points(idx) ||
      expr_has_yield_points(value)
    @ast.TsExpr::Seq(left, right) =>
      expr_has_yield_points(left) || expr_has_yield_points(right)
    @ast.TsExpr::Spread(inner) => expr_has_yield_points(inner)
    _ => false
  }
}
