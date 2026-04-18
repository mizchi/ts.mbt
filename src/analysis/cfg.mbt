// Control Flow Graph (CFG) analysis.

///|
/// A basic block in the CFG.
pub(all) struct BasicBlock {
  id : Int
  stmts : Array[@ast.TsStmt]
  // Outgoing edges (successor block IDs)
  successors : Array[Int]
  // Incoming edges (predecessor block IDs)
  predecessors : Array[Int]
  // Is this block reachable from entry?
  mut is_reachable : Bool
  // Does this block terminate (return/throw)?
  mut is_terminal : Bool
}

///|
pub fn BasicBlock::new(id : Int) -> BasicBlock {
  {
    id,
    stmts: [],
    successors: [],
    predecessors: [],
    is_reachable: false,
    is_terminal: false,
  }
}

///|
/// Control Flow Graph for a function.
pub(all) struct CFG {
  blocks : Array[BasicBlock]
  entry : Int // Entry block ID
  exits : Array[Int] // Exit block IDs
  // Dead code (unreachable blocks)
  dead_blocks : Array[Int]
}

///|
/// CFG builder state.
priv struct CFGBuilder {
  blocks : Array[BasicBlock]
  mut current_block_id : Int
  mut next_block_id : Int
}

///|
fn CFGBuilder::new() -> CFGBuilder {
  let entry = BasicBlock::new(0)
  { blocks: [entry], current_block_id: 0, next_block_id: 1 }
}

///|
fn CFGBuilder::current_block(self : CFGBuilder) -> BasicBlock {
  self.blocks[self.current_block_id]
}

///|
fn CFGBuilder::new_block(self : CFGBuilder) -> Int {
  let id = self.next_block_id
  self.next_block_id = self.next_block_id + 1
  self.blocks.push(BasicBlock::new(id))
  id
}

///|
fn CFGBuilder::add_edge(self : CFGBuilder, from : Int, to : Int) -> Unit {
  if !self.blocks[from].successors.contains(to) {
    self.blocks[from].successors.push(to)
  }
  if !self.blocks[to].predecessors.contains(from) {
    self.blocks[to].predecessors.push(from)
  }
}

///|
fn CFGBuilder::set_current(self : CFGBuilder, id : Int) -> Unit {
  self.current_block_id = id
}

///|
/// Build CFG for a function.
pub fn build_cfg(func : @ast.TsFunc) -> CFG {
  let builder = CFGBuilder::new()
  let exits : Array[Int] = []
  // Build blocks from statements
  for stmt in func.body.stmts {
    build_stmt_cfg(builder, stmt, exits)
  }
  // Mark reachability
  mark_reachable(builder.blocks, 0)
  // Find dead blocks
  let dead_blocks : Array[Int] = []
  for block in builder.blocks {
    if !block.is_reachable {
      dead_blocks.push(block.id)
    }
  }
  { blocks: builder.blocks, entry: 0, exits, dead_blocks }
}

///|
fn build_stmt_cfg(
  builder : CFGBuilder,
  stmt : @ast.TsStmt,
  exits : Array[Int],
) -> Unit {
  match stmt {
    @ast.TsStmt::Return(_) => {
      builder.current_block().stmts.push(stmt)
      builder.current_block().is_terminal = true
      exits.push(builder.current_block_id)
      // Create new block for any following statements (dead code)
      let new_id = builder.new_block()
      builder.set_current(new_id)
    }
    @ast.TsStmt::Throw(_) => {
      builder.current_block().stmts.push(stmt)
      builder.current_block().is_terminal = true
      // Create new block for any following statements (dead code)
      let new_id = builder.new_block()
      builder.set_current(new_id)
    }
    @ast.TsStmt::Break(_) | @ast.TsStmt::Continue(_) => {
      builder.current_block().stmts.push(stmt)
      // Create new block for any following statements (dead code)
      let new_id = builder.new_block()
      builder.set_current(new_id)
    }
    @ast.TsStmt::If(cond, then_block, else_block) => {
      // Add condition to current block
      builder.current_block().stmts.push(@ast.TsStmt::Expr(cond))
      let cond_block = builder.current_block_id
      // Create then block
      let then_id = builder.new_block()
      builder.add_edge(cond_block, then_id)
      builder.set_current(then_id)
      for s in then_block.stmts {
        build_stmt_cfg(builder, s, exits)
      }
      let then_end = builder.current_block_id
      // Create else block
      let else_end = match else_block {
        Some(eb) => {
          let else_id = builder.new_block()
          builder.add_edge(cond_block, else_id)
          builder.set_current(else_id)
          for s in eb.stmts {
            build_stmt_cfg(builder, s, exits)
          }
          builder.current_block_id
        }
        None =>
          // No else - condition block goes directly to merge
          cond_block
      }
      // Create merge block
      let merge_id = builder.new_block()
      if !builder.blocks[then_end].is_terminal {
        builder.add_edge(then_end, merge_id)
      }
      match else_block {
        Some(_) =>
          if !builder.blocks[else_end].is_terminal {
            builder.add_edge(else_end, merge_id)
          }
        None => builder.add_edge(cond_block, merge_id)
      }
      builder.set_current(merge_id)
    }
    @ast.TsStmt::While(cond, body) => {
      // Create header block for condition
      let header_id = builder.new_block()
      builder.add_edge(builder.current_block_id, header_id)
      builder.set_current(header_id)
      builder.current_block().stmts.push(@ast.TsStmt::Expr(cond))
      // Create body block
      let body_id = builder.new_block()
      builder.add_edge(header_id, body_id)
      builder.set_current(body_id)
      for s in body.stmts {
        build_stmt_cfg(builder, s, exits)
      }
      // Back edge to header
      builder.add_edge(builder.current_block_id, header_id)
      // Create exit block
      let exit_id = builder.new_block()
      builder.add_edge(header_id, exit_id)
      builder.set_current(exit_id)
    }
    @ast.TsStmt::DoWhile(cond, body) => {
      // Create body block
      let body_id = builder.new_block()
      builder.add_edge(builder.current_block_id, body_id)
      builder.set_current(body_id)
      for s in body.stmts {
        build_stmt_cfg(builder, s, exits)
      }
      let body_end = builder.current_block_id
      // Create condition block
      let cond_id = builder.new_block()
      builder.add_edge(body_end, cond_id)
      builder.set_current(cond_id)
      builder.current_block().stmts.push(@ast.TsStmt::Expr(cond))
      // Back edge to body
      builder.add_edge(cond_id, body_id)
      // Create exit block
      let exit_id = builder.new_block()
      builder.add_edge(cond_id, exit_id)
      builder.set_current(exit_id)
    }
    @ast.TsStmt::For(init, cond, update, body) => {
      // Init in current block
      match init {
        Some(i) => builder.current_block().stmts.push(i)
        None => ()
      }
      // Create header block for condition
      let header_id = builder.new_block()
      builder.add_edge(builder.current_block_id, header_id)
      builder.set_current(header_id)
      match cond {
        Some(c) => builder.current_block().stmts.push(@ast.TsStmt::Expr(c))
        None => ()
      }
      // Create body block
      let body_id = builder.new_block()
      builder.add_edge(header_id, body_id)
      builder.set_current(body_id)
      for s in body.stmts {
        build_stmt_cfg(builder, s, exits)
      }
      // Update block
      match update {
        Some(u) => builder.current_block().stmts.push(u)
        None => ()
      }
      // Back edge to header
      builder.add_edge(builder.current_block_id, header_id)
      // Create exit block
      let exit_id = builder.new_block()
      builder.add_edge(header_id, exit_id)
      builder.set_current(exit_id)
    }
    @ast.TsStmt::Block(block) =>
      for s in block.stmts {
        build_stmt_cfg(builder, s, exits)
      }
    @ast.TsStmt::Switch(disc, cases) => {
      builder.current_block().stmts.push(@ast.TsStmt::Expr(disc))
      let switch_block = builder.current_block_id
      let exit_id = builder.new_block()
      for case_ in cases {
        let case_id = builder.new_block()
        builder.add_edge(switch_block, case_id)
        builder.set_current(case_id)
        for s in case_.body.stmts {
          build_stmt_cfg(builder, s, exits)
        }
        if !builder.blocks[builder.current_block_id].is_terminal {
          builder.add_edge(builder.current_block_id, exit_id)
        }
      }
      builder.set_current(exit_id)
    }
    @ast.TsStmt::Try(try_block, _, catch_block, finally_block) => {
      // Simplified: treat try/catch as sequential
      for s in try_block.stmts {
        build_stmt_cfg(builder, s, exits)
      }
      match catch_block {
        Some(cb) =>
          for s in cb.stmts {
            build_stmt_cfg(builder, s, exits)
          }
        None => ()
      }
      match finally_block {
        Some(fb) =>
          for s in fb.stmts {
            build_stmt_cfg(builder, s, exits)
          }
        None => ()
      }
    }
    _ =>
      // Simple statement - add to current block
      builder.current_block().stmts.push(stmt)
  }
}

///|
/// Mark reachable blocks starting from entry.
fn mark_reachable(blocks : Array[BasicBlock], entry : Int) -> Unit {
  let worklist : Array[Int] = [entry]
  while worklist.length() > 0 {
    let id = worklist.pop().unwrap()
    if blocks[id].is_reachable {
      continue
    }
    blocks[id].is_reachable = true
    for succ in blocks[id].successors {
      if !blocks[succ].is_reachable {
        worklist.push(succ)
      }
    }
  }
}

///|
/// Check if function has dead code.
pub fn has_dead_code(cfg : CFG) -> Bool {
  cfg.dead_blocks.length() > 0
}

///|
/// Get unreachable statements.
pub fn get_dead_code(cfg : CFG) -> Array[@ast.TsStmt] {
  let dead : Array[@ast.TsStmt] = []
  for block_id in cfg.dead_blocks {
    for stmt in cfg.blocks[block_id].stmts {
      dead.push(stmt)
    }
  }
  dead
}

///|
/// Analyze function for dead code.
pub fn analyze_dead_code(func : @ast.TsFunc) -> Array[@ast.TsStmt] {
  let cfg = build_cfg(func)
  get_dead_code(cfg)
}
