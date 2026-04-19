///|
using @debug {trait Debug}

///|
fn[T : Debug] write_debug_show(logger : &Logger, value : T) -> Unit {
  logger.write_string(@debug.to_string(value))
}

///|
pub impl Show for RefOp with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for SideEffect with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl[T : Debug] Show for AnalysisResult[T] with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for SourceLoc with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for DeclKind with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for BindingInfo with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for ScopeKind with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for AnalysisError with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for AnalysisErrorKind with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for UseKind with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for SymbolRef with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for UsageInfo with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for ConstValue with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for InlineRecommendation with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for ResolvedExportKind with output(self, logger) {
  write_debug_show(logger, self)
}
