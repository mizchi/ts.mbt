///|
using @debug {trait Debug}

///|
fn[T : Debug] write_debug_show(logger : &Logger, value : T) -> Unit {
  logger.write_string(@debug.to_string(value))
}

///|
pub impl Show for TsType with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsExpr with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsArrowBody with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsBinOp with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsUnaryOp with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsCompoundOp with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsForOfKind with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsStmt with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsBlock with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsSwitchCase with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsParam with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsBinding with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsBindingElem with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsArrayBinding with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsObjectBindingProp with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsObjectBinding with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsFunc with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsInterface with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsImport with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsModule with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsImportDecl with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsExportSpec with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsReExportKind with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsReExportSpec with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsModuleBlock with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TypedExpr with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TypedStmt with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TypedFunc with output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TypedModule with output(self, logger) {
  write_debug_show(logger, self)
}
