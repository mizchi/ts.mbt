///|
test "dbg: use strict + eval shapes" {
  let src =
    #|"use strict";
    #|eval++;
    #|var x = 1;
    #|delete x;
  let module_ = parse_module_or_empty(src)
  inspect(
    module_.top_level_stmts,
    content=(
      #|[Expr(StringLit("use strict")), Expr(UnaryOp(PostInc, Var("eval"))), Var(Ident("x"), Any, IntLit(1)), Expr(UnaryOp(Delete, Var("x")))]
    ),
  )
}
