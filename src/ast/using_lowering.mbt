///|
/// The prefix of the holder bindings the parser's `using` lowering
/// declares (`let __ts_using_0, __ts_using_1;`). Each holder stores one
/// resource so the lowered `finally` can dispose it; the `using` binding
/// itself stays a `const` in place.
pub const USING_HOLDER_PREFIX : String = "__ts_using_"

///|
/// Whether `fin` is exactly the `finally` block the parser's `using`
/// lowering generates: one disposal per holder, last first, each further
/// one nested in the `finally` of a `try` around the one before.
///
///   holder?.[Symbol.dispose]?.()
///   await (holder?.[Symbol.asyncDispose] != null
///     ? holder?.[Symbol.asyncDispose]?.()
///     : void holder?.[Symbol.dispose]?.())
///
/// The parser reads it to move a label onto a lowered `for (using …)` loop
/// and the checker to read a lowered block's returns. A `finally` of this
/// shape holds no `break`, `continue` or `return` and declares nothing,
/// which is the property both of them rely on.
pub fn is_using_dispose_finally(fin : TsBlock) -> Bool {
  match fin.stmts {
    [Expr(e)] => is_using_dispose_expr(e)
    [Try({ stmts: [Expr(e)], .. }, None, None, Some(inner))] =>
      is_using_dispose_expr(e) && is_using_dispose_finally(inner)
    _ => false
  }
}

///|
fn is_using_dispose_expr(e : TsExpr) -> Bool {
  match e {
    Await(
      Cond(BinOp(AbstractNe, OptionalChain(m), NullLit), a, UnaryOp(Void, c))
    ) =>
      match using_dispose_member_holder(m, "asyncDispose") {
        Some(h) =>
          using_dispose_call_holder(a, "asyncDispose") == Some(h) &&
          using_dispose_call_holder(c, "dispose") == Some(h)
        None => false
      }
    _ => using_dispose_call_holder(e, "dispose") is Some(_)
  }
}

///|
/// The holder `e` disposes when it is `holder?.[Symbol.key]?.()`.
fn using_dispose_call_holder(e : TsExpr, key : String) -> String? {
  match e {
    OptionalChain(CallExpr(OptionalChain(m), [])) =>
      using_dispose_member_holder(m, key)
    _ => None
  }
}

///|
/// The holder `e` reads when it is `holder[Symbol.key]`.
fn using_dispose_member_holder(e : TsExpr, key : String) -> String? {
  match e {
    IndexAccess(Var(h), PropAccess(Var("Symbol"), k)) if k == key &&
      h.has_prefix(USING_HOLDER_PREFIX) => Some(h)
    _ => None
  }
}
