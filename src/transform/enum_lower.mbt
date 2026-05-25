// TypeScript `enum` lowering — bundle pipeline edge.
//
// The actual lowering lives in the parser package
// (`@parser.lower_enum_decl_to_runtime_stmts`) so both stmt-level
// parsing (`parse_block_from_source`) and the bundle's
// module-block parse can share it. This file is the wrapper the
// bundler calls to splice runtime stmts in front of the lowered
// block.

///|
pub fn lower_enums(enums : Array[@ast.TsEnumDecl]) -> Array[@ast.TsStmt] {
  let out : Array[@ast.TsStmt] = []
  for e in enums {
    for s in @parser.lower_enum_decl_to_runtime_stmts(e) {
      out.push(s)
    }
  }
  out
}
