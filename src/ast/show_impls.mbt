///|
using @debug {trait Debug}

///|
fn[T : Debug] write_debug_show(logger : &Logger, value : T) -> Unit {
  logger.write_string(@debug.to_string(value))
}

///|
pub impl Show for TsType with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsExpr with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsArrowBody with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsBinOp with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsUnaryOp with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsCompoundOp with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsForOfKind with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsStmt with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsBlock with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsSwitchCase with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsParam with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsBinding with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsBindingElem with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsArrayBinding with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsObjectBindingProp with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsObjectBinding with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsFunc with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsInterface with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsTypeAlias with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsImport with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsValueDecl with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsClassPropertyDecl with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsClassMethodDecl with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsClassDecl with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsEnumMemberValue with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsEnumMember with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsEnumDecl with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsModule with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsImportDecl with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsExportSpec with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsReExportKind with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsReExportSpec with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TsModuleBlock with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TypedExpr with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TypedStmt with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TypedFunc with fn output(self, logger) {
  write_debug_show(logger, self)
}

///|
pub impl Show for TypedModule with fn output(self, logger) {
  write_debug_show(logger, self)
}
