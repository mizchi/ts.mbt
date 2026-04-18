// Inlining analysis - identify functions suitable for inlining.

///|
/// Inlining recommendation.
pub(all) enum InlineRecommendation {
  Inline // Should be inlined
  MaybeInline // Could be inlined if called few times
  NoInline // Should not be inlined
} derive(Eq, Debug)

///|
/// Information about a function's inlining suitability.
pub(all) struct InlineInfo {
  name : String
  recommendation : InlineRecommendation
  stmt_count : Int
  expr_count : Int
  has_loops : Bool
  has_recursion : Bool
  call_count : Int // How many times the function is called
  is_pure : Bool
}

///|
/// Thresholds for inlining decisions.
let inline_stmt_threshold : Int = 3

///|
let inline_expr_threshold : Int = 10

///|
let maybe_inline_stmt_threshold : Int = 8

///|
/// Analyze a function for inlining suitability.
pub fn analyze_inline(func : @ast.TsFunc, call_count : Int) -> InlineInfo {
  let mut stmt_count = 0
  let mut expr_count = 0
  let mut has_loops = false
  let mut has_recursion = false
  // Count statements and expressions
  for stmt in func.body.stmts {
    let (sc, ec, loops, rec) = count_stmt_complexity(stmt, func.name)
    stmt_count = stmt_count + sc
    expr_count = expr_count + ec
    has_loops = has_loops || loops
    has_recursion = has_recursion || rec
  }
  // Check purity
  let purity = analyze_func_purity(func)
  // Determine recommendation
  let recommendation = if has_recursion {
    NoInline
  } else if stmt_count <= inline_stmt_threshold &&
    expr_count <= inline_expr_threshold &&
    !has_loops {
    Inline
  } else if stmt_count <= maybe_inline_stmt_threshold && call_count <= 2 {
    MaybeInline
  } else {
    NoInline
  }
  {
    name: func.name,
    recommendation,
    stmt_count,
    expr_count,
    has_loops,
    has_recursion,
    call_count,
    is_pure: purity.is_pure,
  }
}

///|
/// Count statement complexity (stmt_count, expr_count, has_loops, has_recursion).
fn count_stmt_complexity(
  stmt : @ast.TsStmt,
  func_name : String,
) -> (Int, Int, Bool, Bool) {
  match stmt {
    @ast.TsStmt::Expr(e) => {
      let (ec, rec) = count_expr_complexity(e, func_name)
      (1, ec, false, rec)
    }
    @ast.TsStmt::Return(Some(e)) => {
      let (ec, rec) = count_expr_complexity(e, func_name)
      (1, ec, false, rec)
    }
    @ast.TsStmt::Return(None) => (1, 0, false, false)
    @ast.TsStmt::Var(_, _, init)
    | @ast.TsStmt::Let(_, _, init)
    | @ast.TsStmt::Const(_, _, init) => {
      let (ec, rec) = count_expr_complexity(init, func_name)
      (1, ec, false, rec)
    }
    @ast.TsStmt::Assign(_, e) => {
      let (ec, rec) = count_expr_complexity(e, func_name)
      (1, ec, false, rec)
    }
    @ast.TsStmt::If(cond, then_block, else_block) => {
      let (cond_ec, cond_rec) = count_expr_complexity(cond, func_name)
      let mut sc = 1
      let mut ec = cond_ec
      let mut rec = cond_rec
      for s in then_block.stmts {
        let (ssc, sec, _, srec) = count_stmt_complexity(s, func_name)
        sc = sc + ssc
        ec = ec + sec
        rec = rec || srec
      }
      match else_block {
        Some(eb) =>
          for s in eb.stmts {
            let (ssc, sec, _, srec) = count_stmt_complexity(s, func_name)
            sc = sc + ssc
            ec = ec + sec
            rec = rec || srec
          }
        None => ()
      }
      (sc, ec, false, rec)
    }
    @ast.TsStmt::While(cond, body) => {
      let (cond_ec, cond_rec) = count_expr_complexity(cond, func_name)
      let mut sc = 1
      let mut ec = cond_ec
      let mut rec = cond_rec
      for s in body.stmts {
        let (ssc, sec, _, srec) = count_stmt_complexity(s, func_name)
        sc = sc + ssc
        ec = ec + sec
        rec = rec || srec
      }
      (sc, ec, true, rec) // has_loops = true
    }
    @ast.TsStmt::DoWhile(cond, body) => {
      let (cond_ec, cond_rec) = count_expr_complexity(cond, func_name)
      let mut sc = 1
      let mut ec = cond_ec
      let mut rec = cond_rec
      for s in body.stmts {
        let (ssc, sec, _, srec) = count_stmt_complexity(s, func_name)
        sc = sc + ssc
        ec = ec + sec
        rec = rec || srec
      }
      (sc, ec, true, rec)
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      let mut sc = 1
      let mut ec = 0
      let mut rec = false
      match init {
        Some(i) => {
          let (ssc, sec, _, srec) = count_stmt_complexity(i, func_name)
          sc = sc + ssc
          ec = ec + sec
          rec = rec || srec
        }
        None => ()
      }
      match cond {
        Some(c) => {
          let (cec, crec) = count_expr_complexity(c, func_name)
          ec = ec + cec
          rec = rec || crec
        }
        None => ()
      }
      match update {
        Some(u) => {
          let (ssc, sec, _, srec) = count_stmt_complexity(u, func_name)
          sc = sc + ssc
          ec = ec + sec
          rec = rec || srec
        }
        None => ()
      }
      for s in body.stmts {
        let (ssc, sec, _, srec) = count_stmt_complexity(s, func_name)
        sc = sc + ssc
        ec = ec + sec
        rec = rec || srec
      }
      (sc, ec, true, rec)
    }
    @ast.TsStmt::ForOf(_, _, _, iter, body)
    | @ast.TsStmt::ForAwaitOf(_, _, _, iter, body)
    | @ast.TsStmt::ForIn(_, _, _, iter, body) => {
      let (iter_ec, iter_rec) = count_expr_complexity(iter, func_name)
      let mut sc = 1
      let mut ec = iter_ec
      let mut rec = iter_rec
      for s in body.stmts {
        let (ssc, sec, _, srec) = count_stmt_complexity(s, func_name)
        sc = sc + ssc
        ec = ec + sec
        rec = rec || srec
      }
      (sc, ec, true, rec)
    }
    @ast.TsStmt::Block(block) => {
      let mut sc = 0
      let mut ec = 0
      let mut loops = false
      let mut rec = false
      for s in block.stmts {
        let (ssc, sec, sloops, srec) = count_stmt_complexity(s, func_name)
        sc = sc + ssc
        ec = ec + sec
        loops = loops || sloops
        rec = rec || srec
      }
      (sc, ec, loops, rec)
    }
    @ast.TsStmt::Switch(disc, cases) => {
      let (disc_ec, disc_rec) = count_expr_complexity(disc, func_name)
      let mut sc = 1
      let mut ec = disc_ec
      let mut rec = disc_rec
      for case_ in cases {
        match case_.test_expr {
          Some(test_e) => {
            let (tec, trec) = count_expr_complexity(test_e, func_name)
            ec = ec + tec
            rec = rec || trec
          }
          None => ()
        }
        for s in case_.body.stmts {
          let (ssc, sec, _, srec) = count_stmt_complexity(s, func_name)
          sc = sc + ssc
          ec = ec + sec
          rec = rec || srec
        }
      }
      (sc, ec, false, rec)
    }
    @ast.TsStmt::Try(try_block, _, catch_block, finally_block) => {
      let mut sc = 1
      let mut ec = 0
      let mut rec = false
      for s in try_block.stmts {
        let (ssc, sec, _, srec) = count_stmt_complexity(s, func_name)
        sc = sc + ssc
        ec = ec + sec
        rec = rec || srec
      }
      match catch_block {
        Some(cb) =>
          for s in cb.stmts {
            let (ssc, sec, _, srec) = count_stmt_complexity(s, func_name)
            sc = sc + ssc
            ec = ec + sec
            rec = rec || srec
          }
        None => ()
      }
      match finally_block {
        Some(fb) =>
          for s in fb.stmts {
            let (ssc, sec, _, srec) = count_stmt_complexity(s, func_name)
            sc = sc + ssc
            ec = ec + sec
            rec = rec || srec
          }
        None => ()
      }
      (sc, ec, false, rec)
    }
    @ast.TsStmt::Throw(e) => {
      let (ec, rec) = count_expr_complexity(e, func_name)
      (1, ec, false, rec)
    }
    _ => (1, 0, false, false)
  }
}

///|
/// Count expression complexity (expr_count, has_recursion).
fn count_expr_complexity(expr : @ast.TsExpr, func_name : String) -> (Int, Bool) {
  match expr {
    // Literals
    @ast.TsExpr::IntLit(_)
    | @ast.TsExpr::NumberLit(_)
    | @ast.TsExpr::StringLit(_)
    | @ast.TsExpr::BoolLit(_)
    | @ast.TsExpr::NullLit
    | @ast.TsExpr::ArrayHole => (1, false)
    // Variable
    @ast.TsExpr::Var(_) => (1, false)
    // Binary operation
    @ast.TsExpr::BinOp(_, left, right) => {
      let (lec, lrec) = count_expr_complexity(left, func_name)
      let (rec_, rrec) = count_expr_complexity(right, func_name)
      (1 + lec + rec_, lrec || rrec)
    }
    // Unary operation
    @ast.TsExpr::UnaryOp(_, operand) => {
      let (ec, rec) = count_expr_complexity(operand, func_name)
      (1 + ec, rec)
    }
    // Call - check for recursion
    @ast.TsExpr::Call(name, args) => {
      let is_recursive = name == func_name
      let mut ec = 1
      for arg in args {
        let (aec, arec) = count_expr_complexity(arg, func_name)
        ec = ec + aec
        if arec {
          return (ec, true)
        }
      }
      (ec, is_recursive)
    }
    @ast.TsExpr::CallExpr(callee, args) => {
      let (cec, crec) = count_expr_complexity(callee, func_name)
      let mut ec = 1 + cec
      let mut rec = crec
      for arg in args {
        let (aec, arec) = count_expr_complexity(arg, func_name)
        ec = ec + aec
        rec = rec || arec
      }
      (ec, rec)
    }
    // Method call
    @ast.TsExpr::MethodCall(recv, _, args) => {
      let (rec_, rrec) = count_expr_complexity(recv, func_name)
      let mut ec = 1 + rec_
      let mut rec = rrec
      for arg in args {
        let (aec, arec) = count_expr_complexity(arg, func_name)
        ec = ec + aec
        rec = rec || arec
      }
      (ec, rec)
    }
    // Array literal
    @ast.TsExpr::ArrayLit(elements) => {
      let mut ec = 1
      let mut rec = false
      for elem in elements {
        let (eec, erec) = count_expr_complexity(elem, func_name)
        ec = ec + eec
        rec = rec || erec
      }
      (ec, rec)
    }
    // Object literal
    @ast.TsExpr::ObjectLit(props) => {
      let mut ec = 1
      let mut rec = false
      for prop in props {
        let (pec, prec) = count_expr_complexity(prop.1, func_name)
        ec = ec + pec
        rec = rec || prec
      }
      (ec, rec)
    }
    // Conditional
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      let (cec, crec) = count_expr_complexity(cond, func_name)
      let (tec, trec) = count_expr_complexity(then_e, func_name)
      let (eec, erec) = count_expr_complexity(else_e, func_name)
      (1 + cec + tec + eec, crec || trec || erec)
    }
    // Property/index access
    @ast.TsExpr::PropAccess(obj, _) => {
      let (ec, rec) = count_expr_complexity(obj, func_name)
      (1 + ec, rec)
    }
    @ast.TsExpr::IndexAccess(arr, idx) => {
      let (aec, arec) = count_expr_complexity(arr, func_name)
      let (iec, irec) = count_expr_complexity(idx, func_name)
      (1 + aec + iec, arec || irec)
    }
    // Assignment expressions
    @ast.TsExpr::AssignExpr(_, e) | @ast.TsExpr::AssignPattern(_, e) => {
      let (ec, rec) = count_expr_complexity(e, func_name)
      (1 + ec, rec)
    }
    // Arrow function / function expression - count as large
    @ast.TsExpr::ArrowFunc(_, _, _) | @ast.TsExpr::FuncExpr(_) => (10, false) // Penalty for nested functions
    _ => (1, false)
  }
}

///|
/// Analyze all functions in a module for inlining.
pub fn analyze_module_inline(module_ : @ast.TsModule) -> Array[InlineInfo] {
  // First pass: count function calls
  let call_counts : Map[String, Int] = {}
  for func in module_.funcs {
    count_function_calls(func, call_counts)
  }
  // Second pass: analyze each function
  let results : Array[InlineInfo] = []
  for func in module_.funcs {
    let call_count = match call_counts.get(func.name) {
      Some(c) => c
      None => 0
    }
    results.push(analyze_inline(func, call_count))
  }
  results
}

///|
/// Count function calls in a function.
fn count_function_calls(func : @ast.TsFunc, counts : Map[String, Int]) -> Unit {
  for stmt in func.body.stmts {
    count_calls_in_stmt(stmt, counts)
  }
}

///|
fn count_calls_in_stmt(stmt : @ast.TsStmt, counts : Map[String, Int]) -> Unit {
  match stmt {
    @ast.TsStmt::Expr(e) => count_calls_in_expr(e, counts)
    @ast.TsStmt::Return(Some(e)) => count_calls_in_expr(e, counts)
    @ast.TsStmt::Var(_, _, init)
    | @ast.TsStmt::Let(_, _, init)
    | @ast.TsStmt::Const(_, _, init) => count_calls_in_expr(init, counts)
    @ast.TsStmt::Assign(_, e) => count_calls_in_expr(e, counts)
    @ast.TsStmt::If(cond, then_block, else_block) => {
      count_calls_in_expr(cond, counts)
      for s in then_block.stmts {
        count_calls_in_stmt(s, counts)
      }
      match else_block {
        Some(eb) =>
          for s in eb.stmts {
            count_calls_in_stmt(s, counts)
          }
        None => ()
      }
    }
    @ast.TsStmt::While(cond, body) | @ast.TsStmt::DoWhile(cond, body) => {
      count_calls_in_expr(cond, counts)
      for s in body.stmts {
        count_calls_in_stmt(s, counts)
      }
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      match init {
        Some(i) => count_calls_in_stmt(i, counts)
        None => ()
      }
      match cond {
        Some(c) => count_calls_in_expr(c, counts)
        None => ()
      }
      match update {
        Some(u) => count_calls_in_stmt(u, counts)
        None => ()
      }
      for s in body.stmts {
        count_calls_in_stmt(s, counts)
      }
    }
    @ast.TsStmt::Block(block) =>
      for s in block.stmts {
        count_calls_in_stmt(s, counts)
      }
    _ => ()
  }
}

///|
fn count_calls_in_expr(expr : @ast.TsExpr, counts : Map[String, Int]) -> Unit {
  match expr {
    @ast.TsExpr::Call(name, args) => {
      let current = match counts.get(name) {
        Some(c) => c
        None => 0
      }
      counts[name] = current + 1
      for arg in args {
        count_calls_in_expr(arg, counts)
      }
    }
    @ast.TsExpr::CallExpr(callee, args) => {
      count_calls_in_expr(callee, counts)
      for arg in args {
        count_calls_in_expr(arg, counts)
      }
    }
    @ast.TsExpr::MethodCall(recv, _, args) => {
      count_calls_in_expr(recv, counts)
      for arg in args {
        count_calls_in_expr(arg, counts)
      }
    }
    @ast.TsExpr::BinOp(_, left, right) => {
      count_calls_in_expr(left, counts)
      count_calls_in_expr(right, counts)
    }
    @ast.TsExpr::UnaryOp(_, operand) => count_calls_in_expr(operand, counts)
    @ast.TsExpr::ArrayLit(elements) =>
      for elem in elements {
        count_calls_in_expr(elem, counts)
      }
    @ast.TsExpr::ObjectLit(props) =>
      for prop in props {
        count_calls_in_expr(prop.1, counts)
      }
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      count_calls_in_expr(cond, counts)
      count_calls_in_expr(then_e, counts)
      count_calls_in_expr(else_e, counts)
    }
    @ast.TsExpr::PropAccess(obj, _) => count_calls_in_expr(obj, counts)
    @ast.TsExpr::IndexAccess(arr, idx) => {
      count_calls_in_expr(arr, counts)
      count_calls_in_expr(idx, counts)
    }
    _ => ()
  }
}
