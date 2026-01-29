// ============================================
// type
// ============================================

///|
// / type
fn Parser::parse_type(self : Parser) -> @ast.TsType raise ParseError {
  let tok = self.advance()
  let base_type : @ast.TsType = match tok.kind {
    NumberType => Number
    IntType => Int
    BooleanType => Boolean
    StringType => String_
    VoidType => Void
    Ident(name) => Named(name)
    _ => raise ParseError("Expected type, got \{tok.kind}")
  }
  // arraytypecheck: type[]
  if self.match_(LBracket) {
    let _ = self.expect(RBracket)
    Array(base_type)
  } else {
    base_type
  }
}

