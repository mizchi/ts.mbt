///|
using @debug {trait Debug}

///|
fn[T : Debug] write_debug_show(logger : &Logger, value : T) -> Unit {
  logger.write_string(@debug.to_string(value))
}

///|
pub impl Show for ParseError with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for Parser with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TokenKind with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for Token with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for Lexer with fn output(self, logger) {
  write_debug_show(logger, self)
}
