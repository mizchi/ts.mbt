///|
using @debug {trait Debug}

///|
fn[T : Debug] write_debug_show(logger : &Logger, value : T) -> Unit {
  logger.write_string(@debug.to_string(value))
}

///|
pub impl Show for CodeGenError with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for CompileError with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for GenStateMachine with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for GenVar with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for GenState with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for GenInstr with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for GenExpr with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for GenBinOp with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for GenUnaryOp with output(self, logger) {
  write_debug_show(logger, self)
}
