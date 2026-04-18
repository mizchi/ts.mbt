///|
using @debug {trait Debug}

///|
fn[T : Debug] write_debug_show(logger : &Logger, value : T) -> Unit {
  logger.write_string(@debug.to_string(value))
}

///|
pub impl Show for JSTag with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for JSValue with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for JSByteBuffer with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TypedArrayKind with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TypedArrayData with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for JSProp with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for JSPropMap with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for JSArray with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for JSBinding with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for JSEnv with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for JSClosure with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for JSFuncBody with output(self, logger) {
  write_debug_show(logger, self)
}
