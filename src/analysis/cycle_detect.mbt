// Cycle detection - detect potential circular references that may cause memory leaks.

///|
/// A reference edge in the object graph.
pub(all) struct RefEdge {
  from_var : String
  to_var : String
  // Statement index where this reference is created
  stmt_index : Int
}

///|
/// Potential cycle information.
pub(all) struct PotentialCycle {
  // Variables involved in the cycle
  variables : Array[String]
  // Edges forming the cycle
  edges : Array[RefEdge]
}

///|
/// Cycle detection result.
pub(all) struct CycleInfo {
  // All reference edges found
  edges : Array[RefEdge]
  // Detected potential cycles
  potential_cycles : Array[PotentialCycle]
  // Variables that are part of potential cycles
  cyclic_vars : Array[String]
}

///|
pub fn CycleInfo::new() -> CycleInfo {
  { edges: [], potential_cycles: [], cyclic_vars: [] }
}

///|
/// Analyze a function for potential circular references.
pub fn analyze_cycles(func : @ast.TsFunc) -> CycleInfo {
  let info = CycleInfo::new()

  // Phase 1: Collect all reference edges (assignments to object properties)
  let mut stmt_idx = 0
  for stmt in func.body.stmts {
    stmt_idx = stmt_idx + 1
    collect_ref_edges(stmt, stmt_idx, info)
  }

  // Phase 2: Build adjacency list and detect cycles using DFS
  let adj : Map[String, Array[String]] = {}
  for edge in info.edges {
    match adj.get(edge.from_var) {
      Some(neighbors) =>
        if !neighbors.contains(edge.to_var) {
          neighbors.push(edge.to_var)
        }
      None => adj[edge.from_var] = [edge.to_var]
    }
  }

  // Phase 3: Find cycles using DFS with color marking
  let white : Array[String] = [] // Not visited
  let gray : Array[String] = [] // In current path
  let black : Array[String] = [] // Fully processed

  // Initialize all nodes as white
  for entry in adj {
    if !white.contains(entry.0) {
      white.push(entry.0)
    }
    for neighbor in entry.1 {
      if !white.contains(neighbor) {
        white.push(neighbor)
      }
    }
  }

  // DFS from each unvisited node
  for start in white {
    if !black.contains(start) && !gray.contains(start) {
      dfs_find_cycles(start, adj, gray, black, info)
    }
  }
  info
}

///|
fn dfs_find_cycles(
  node : String,
  adj : Map[String, Array[String]],
  gray : Array[String],
  black : Array[String],
  info : CycleInfo,
) -> Unit {
  // Mark as in-progress (gray)
  gray.push(node)
  match adj.get(node) {
    Some(neighbors) =>
      for neighbor in neighbors {
        if gray.contains(neighbor) {
          // Found a cycle! Trace back to find the cycle path
          let cycle_vars : Array[String] = []
          let mut in_cycle = false
          for v in gray {
            if v == neighbor {
              in_cycle = true
            }
            if in_cycle {
              cycle_vars.push(v)
              if !info.cyclic_vars.contains(v) {
                info.cyclic_vars.push(v)
              }
            }
          }

          // Find edges in this cycle
          let cycle_edges : Array[RefEdge] = []
          for edge in info.edges {
            if cycle_vars.contains(edge.from_var) &&
              cycle_vars.contains(edge.to_var) {
              cycle_edges.push(edge)
            }
          }
          info.potential_cycles.push({
            variables: cycle_vars,
            edges: cycle_edges,
          })
        } else if !black.contains(neighbor) {
          dfs_find_cycles(neighbor, adj, gray, black, info)
        }
      }
    None => ()
  }

  // Remove from gray, add to black
  let new_gray : Array[String] = []
  for v in gray {
    if v != node {
      new_gray.push(v)
    }
  }
  // Can't reassign gray, so we'll just track in black
  black.push(node)
}

///|
fn collect_ref_edges(stmt : @ast.TsStmt, idx : Int, info : CycleInfo) -> Unit {
  match stmt {
    // a.b = c  -> edge from a to value of c
    @ast.TsStmt::Expr(e) => collect_ref_edges_expr(e, idx, info)
    @ast.TsStmt::Var(binding, _, init)
    | @ast.TsStmt::Let(binding, _, init)
    | @ast.TsStmt::Const(binding, _, init) => {
      // For object literals with references
      collect_ref_edges_expr(init, idx, info)
      // Track the binding
      let names : Array[String] = []
      collect_binding_names(binding, names)
      for name in names {
        match get_referenced_var(init) {
          Some(ref_var) =>
            info.edges.push({ from_var: name, to_var: ref_var, stmt_index: idx })
          None => ()
        }
      }
    }
    @ast.TsStmt::If(_, then_block, else_block) => {
      for s in then_block.stmts {
        collect_ref_edges(s, idx, info)
      }
      match else_block {
        Some(eb) =>
          for s in eb.stmts {
            collect_ref_edges(s, idx, info)
          }
        None => ()
      }
    }
    @ast.TsStmt::While(_, body) | @ast.TsStmt::DoWhile(_, body) =>
      for s in body.stmts {
        collect_ref_edges(s, idx, info)
      }
    @ast.TsStmt::For(init, _, update, body) => {
      match init {
        Some(i) => collect_ref_edges(i, idx, info)
        None => ()
      }
      match update {
        Some(u) => collect_ref_edges(u, idx, info)
        None => ()
      }
      for s in body.stmts {
        collect_ref_edges(s, idx, info)
      }
    }
    @ast.TsStmt::Block(block) =>
      for s in block.stmts {
        collect_ref_edges(s, idx, info)
      }
    _ => ()
  }
}

///|
fn collect_ref_edges_expr(
  expr : @ast.TsExpr,
  idx : Int,
  info : CycleInfo,
) -> Unit {
  match expr {
    // a.b = c  -> creates reference from a to c's value
    @ast.TsExpr::PropAssignExpr(obj, _, value) => {
      match (get_var_name(obj), get_referenced_var(value)) {
        (Some(from), Some(to)) =>
          info.edges.push({ from_var: from, to_var: to, stmt_index: idx })
        _ => ()
      }
      collect_ref_edges_expr(value, idx, info)
    }
    // a[i] = c
    @ast.TsExpr::IndexAssignExpr(arr, _, value) => {
      match (get_var_name(arr), get_referenced_var(value)) {
        (Some(from), Some(to)) =>
          info.edges.push({ from_var: from, to_var: to, stmt_index: idx })
        _ => ()
      }
      collect_ref_edges_expr(value, idx, info)
    }
    // Object literals with property references
    @ast.TsExpr::ObjectLit(props) =>
      for prop in props {
        collect_ref_edges_expr(prop.1, idx, info)
      }
    @ast.TsExpr::ArrayLit(elements) =>
      for elem in elements {
        collect_ref_edges_expr(elem, idx, info)
      }
    @ast.TsExpr::BinOp(_, left, right) => {
      collect_ref_edges_expr(left, idx, info)
      collect_ref_edges_expr(right, idx, info)
    }
    @ast.TsExpr::Call(_, args) =>
      for arg in args {
        collect_ref_edges_expr(arg, idx, info)
      }
    @ast.TsExpr::MethodCall(recv, _, args) => {
      collect_ref_edges_expr(recv, idx, info)
      for arg in args {
        collect_ref_edges_expr(arg, idx, info)
      }
    }
    @ast.TsExpr::Cond(cond, then_e, else_e) => {
      collect_ref_edges_expr(cond, idx, info)
      collect_ref_edges_expr(then_e, idx, info)
      collect_ref_edges_expr(else_e, idx, info)
    }
    _ => ()
  }
}

///|
fn get_var_name(expr : @ast.TsExpr) -> String? {
  match expr {
    @ast.TsExpr::Var(name) => Some(name)
    _ => None
  }
}

///|
fn get_referenced_var(expr : @ast.TsExpr) -> String? {
  match expr {
    @ast.TsExpr::Var(name) => Some(name)
    @ast.TsExpr::PropAccess(obj, _) => get_var_name(obj)
    @ast.TsExpr::IndexAccess(arr, _) => get_var_name(arr)
    _ => None
  }
}

///|
/// Check if a function has potential memory leaks from cycles.
pub fn has_potential_cycles(info : CycleInfo) -> Bool {
  info.potential_cycles.length() > 0
}

///|
/// Get variables involved in potential cycles (may need weak references).
pub fn get_cyclic_vars(info : CycleInfo) -> Array[String] {
  info.cyclic_vars
}
