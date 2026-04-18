// Memory leak detection - combine analyses to find potential memory leaks.

///|
/// Type of potential memory leak.
pub(all) enum LeakKind {
  MissingDrop(String, Int) // Variable not dropped at correct point
  CyclicReference(Array[String]) // Circular reference between variables
  EscapedWithoutTracking(String) // Value escapes but not tracked
  CapturedInLongLivedClosure(String) // Captured in closure that outlives expected scope
  UnboundedGrowth(String, Int) // Variable in loop that accumulates references
}

///|
/// A potential memory leak.
pub(all) struct PotentialLeak {
  kind : LeakKind
  message : String
  stmt_index : Int
  severity : LeakSeverity
}

///|
/// Severity of the leak.
pub(all) enum LeakSeverity {
  Warning // Might leak under certain conditions
  Error // Will definitely leak
  Info // Informational, may not be a real leak
}

///|
/// Combined leak analysis result.
pub(all) struct LeakAnalysis {
  leaks : Array[PotentialLeak]
  // Statistics
  mut total_vars : Int
  mut dropped_vars : Int
  mut escaped_vars : Int
  mut cyclic_vars : Int
}

///|
pub fn LeakAnalysis::new() -> LeakAnalysis {
  { leaks: [], total_vars: 0, dropped_vars: 0, escaped_vars: 0, cyclic_vars: 0 }
}

///|
/// Perform comprehensive leak analysis on a function.
pub fn analyze_leaks(func : @ast.TsFunc) -> LeakAnalysis {
  let result = LeakAnalysis::new()

  // Run all sub-analyses
  let liveness = analyze_liveness(func)
  let aliases = analyze_aliases(func)
  let cycles = analyze_cycles(func)

  // Count statistics
  result.total_vars = liveness.lifetimes.length()
  result.escaped_vars = liveness.captured_vars.length()
  result.cyclic_vars = cycles.cyclic_vars.length()

  // Count properly dropped vars
  let mut dropped = 0
  for entry in liveness.drop_points {
    dropped = dropped + entry.1.length()
  }
  result.dropped_vars = dropped

  // Check 1: Cyclic references
  for cycle in cycles.potential_cycles {
    result.leaks.push({
      kind: CyclicReference(cycle.variables),
      message: "Potential circular reference detected between: " +
      cycle.variables
      .iter()
      .fold(init="", fn(acc, v) { if acc == "" { v } else { acc + " -> " + v } }),
      stmt_index: if cycle.edges.length() > 0 {
        cycle.edges[0].stmt_index
      } else {
        0
      },
      severity: Warning,
    })
  }

  // Check 2: Variables that escape but aren't tracked
  for name in aliases.escaped {
    if !liveness.captured_vars.contains(name) {
      // Escaped but not in captured list - may indicate tracking issue
      match liveness.lifetimes.get(name) {
        Some(lifetime) =>
          if !lifetime.escapes {
            result.leaks.push({
              kind: EscapedWithoutTracking(name),
              message: "Variable '" +
              name +
              "' escapes but may not be properly tracked",
              stmt_index: lifetime.last_use,
              severity: Info,
            })
          }
        None => ()
      }
    }
  }

  // Check 3: Variables captured in closures
  for name in liveness.captured_vars {
    match liveness.lifetimes.get(name) {
      Some(lifetime) =>
        // If the captured variable is also aliased, it's higher risk
        if aliases.escaped.contains(name) {
          result.leaks.push({
            kind: CapturedInLongLivedClosure(name),
            message: "Variable '" +
            name +
            "' is captured in closure and also escapes",
            stmt_index: lifetime.last_use,
            severity: Warning,
          })
        }
      None => ()
    }
  }

  // Check 4: Variables in loops that may accumulate
  let loop_vars = find_loop_accumulating_vars(func)
  for pair in loop_vars {
    let name = pair.0
    let stmt_idx = pair.1
    result.leaks.push({
      kind: UnboundedGrowth(name, stmt_idx),
      message: "Variable '" + name + "' may grow unboundedly in loop",
      stmt_index: stmt_idx,
      severity: Warning,
    })
  }
  result
}

///|
fn find_loop_accumulating_vars(func : @ast.TsFunc) -> Array[(String, Int)] {
  let results : Array[(String, Int)] = []
  let mut stmt_idx = 0
  for stmt in func.body.stmts {
    stmt_idx = stmt_idx + 1
    find_accumulating_in_stmt(stmt, stmt_idx, results)
  }
  results
}

///|
fn find_accumulating_in_stmt(
  stmt : @ast.TsStmt,
  idx : Int,
  results : Array[(String, Int)],
) -> Unit {
  match stmt {
    @ast.TsStmt::While(_, body) | @ast.TsStmt::DoWhile(_, body) =>
      // Look for push/concat/append patterns in loop
      for s in body.stmts {
        find_accumulating_patterns(s, idx, results)
      }
    @ast.TsStmt::For(_, _, _, body) =>
      for s in body.stmts {
        find_accumulating_patterns(s, idx, results)
      }
    @ast.TsStmt::ForOf(_, _, _, _, body)
    | @ast.TsStmt::ForAwaitOf(_, _, _, _, body)
    | @ast.TsStmt::ForIn(_, _, _, _, body) =>
      for s in body.stmts {
        find_accumulating_patterns(s, idx, results)
      }
    @ast.TsStmt::If(_, then_block, else_block) => {
      for s in then_block.stmts {
        find_accumulating_in_stmt(s, idx, results)
      }
      match else_block {
        Some(eb) =>
          for s in eb.stmts {
            find_accumulating_in_stmt(s, idx, results)
          }
        None => ()
      }
    }
    @ast.TsStmt::Block(block) =>
      for s in block.stmts {
        find_accumulating_in_stmt(s, idx, results)
      }
    _ => ()
  }
}

///|
fn find_accumulating_patterns(
  stmt : @ast.TsStmt,
  idx : Int,
  results : Array[(String, Int)],
) -> Unit {
  match stmt {
    @ast.TsStmt::Expr(e) => find_accumulating_in_expr(e, idx, results)
    _ => ()
  }
}

///|
fn find_accumulating_in_expr(
  expr : @ast.TsExpr,
  idx : Int,
  results : Array[(String, Int)],
) -> Unit {
  match expr {
    // arr.push(...) - accumulating pattern
    @ast.TsExpr::MethodCall(recv, method_name, _) =>
      if method_name == "push" ||
        method_name == "unshift" ||
        method_name == "concat" ||
        method_name == "append" {
        match recv {
          @ast.TsExpr::Var(name) =>
            // Check if this variable is defined outside the loop
            // For now, just report it
            if !results.iter().any(fn(p) { p.0 == name }) {
              results.push((name, idx))
            }
          _ => ()
        }
      }
    // a = a.concat(...) - also accumulating
    @ast.TsExpr::AssignExpr(name, value) =>
      match value {
        @ast.TsExpr::MethodCall(recv, method_name, _) =>
          if method_name == "concat" {
            match recv {
              @ast.TsExpr::Var(recv_name) =>
                if recv_name == name {
                  if !results.iter().any(fn(p) { p.0 == name }) {
                    results.push((name, idx))
                  }
                }
              _ => ()
            }
          }
        // a = [...a, x] - spread accumulating
        @ast.TsExpr::ArrayLit(elements) =>
          for elem in elements {
            match elem {
              @ast.TsExpr::Spread(inner) =>
                match inner {
                  @ast.TsExpr::Var(spread_name) =>
                    if spread_name == name {
                      if !results.iter().any(fn(p) { p.0 == name }) {
                        results.push((name, idx))
                      }
                    }
                  _ => ()
                }
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
}

///|
/// Check if analysis found any leaks.
pub fn has_leaks(analysis : LeakAnalysis) -> Bool {
  analysis.leaks.length() > 0
}

///|
/// Get only error-severity leaks.
pub fn get_errors(analysis : LeakAnalysis) -> Array[PotentialLeak] {
  analysis.leaks
  .iter()
  .filter(fn(l) {
    match l.severity {
      Error => true
      _ => false
    }
  })
  .collect()
}

///|
/// Get warnings and errors.
pub fn get_warnings(analysis : LeakAnalysis) -> Array[PotentialLeak] {
  analysis.leaks
  .iter()
  .filter(fn(l) {
    match l.severity {
      Error | Warning => true
      _ => false
    }
  })
  .collect()
}

///|
/// Format leak report.
pub fn format_leak_report(analysis : LeakAnalysis) -> String {
  let mut report = "=== Memory Leak Analysis ===\n"
  report = report + "Total variables: " + analysis.total_vars.to_string() + "\n"
  report = report +
    "Properly dropped: " +
    analysis.dropped_vars.to_string() +
    "\n"
  report = report +
    "Escaped/captured: " +
    analysis.escaped_vars.to_string() +
    "\n"
  report = report + "In cycles: " + analysis.cyclic_vars.to_string() + "\n\n"
  if analysis.leaks.length() == 0 {
    report = report + "No potential leaks detected.\n"
  } else {
    report = report + "Potential issues:\n"
    for leak in analysis.leaks {
      let severity_str = match leak.severity {
        Error => "[ERROR]"
        Warning => "[WARN]"
        Info => "[INFO]"
      }
      report = report + severity_str + " " + leak.message + "\n"
    }
  }
  report
}
