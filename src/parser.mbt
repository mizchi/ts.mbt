// TypeScript サブセット用パーサー

///|
/// パースエラー
pub suberror ParseError {
  ParseError(String)
} derive(Show)

///|
/// パーサー
pub struct Parser {
  tokens : Array[Token]
  mut pos : Int
} derive(Show)

///|
/// パーサー作成
pub fn Parser::new(tokens : Array[Token]) -> Parser {
  { tokens, pos: 0 }
}

///|
/// ソースからパーサー作成
pub fn Parser::from_source(src : String) -> Parser {
  let lexer = Lexer::new(src)
  let tokens = lexer.tokenize()
  Parser::new(tokens)
}

///|
/// 現在のトークンを取得
fn Parser::peek(self : Parser) -> Token {
  if self.pos >= self.tokens.length() {
    { kind: Eof, pos: 0 }
  } else {
    self.tokens[self.pos]
  }
}

///|
/// トークンを消費
fn Parser::advance(self : Parser) -> Token {
  let tok = self.peek()
  if tok.kind != Eof {
    self.pos += 1
  }
  tok
}

///|
/// 特定のトークンを期待して消費
fn Parser::expect(
  self : Parser,
  expected : TokenKind,
) -> Token raise ParseError {
  let tok = self.peek()
  if tok.kind == expected {
    self.advance()
  } else {
    raise ParseError("Expected \{expected}, got \{tok.kind}")
  }
}

///|
/// トークン種別が一致するか
fn Parser::check(self : Parser, kind : TokenKind) -> Bool {
  self.peek().kind == kind
}

///|
/// 指定オフセット先のトークンを取得
fn Parser::peek_at(self : Parser, offset : Int) -> Token {
  let idx = self.pos + offset
  if idx >= self.tokens.length() {
    { kind: Eof, pos: 0 }
  } else {
    self.tokens[idx]
  }
}

///|
/// アロー関数パターンかどうかを判定 (現在位置が `(` であること前提)
fn Parser::is_arrow_function(self : Parser) -> Bool {
  // () => の場合
  if self.peek_at(1).kind == RParen && self.peek_at(2).kind == Arrow {
    return true
  }
  // (ident) => または (ident: type) => または複数パラメータの場合
  // 簡易判定: ( の後を辿って ) を見つけ、その次が => かどうか
  let mut i = 1
  let mut depth = 1
  while depth > 0 && i < 100 { // 安全のため上限
    let tok = self.peek_at(i)
    match tok.kind {
      LParen => depth += 1
      RParen => depth -= 1
      Eof => break
      _ => ()
    }
    i += 1
  }
  // i-1 が ) の位置、i が ) の次
  self.peek_at(i).kind == Arrow
}

///|
/// 一致すれば消費
fn Parser::match_(self : Parser, kind : TokenKind) -> Bool {
  if self.check(kind) {
    let _ = self.advance()
    true
  } else {
    false
  }
}

// ============================================
// 型パース
// ============================================

///|
/// 型をパース
fn Parser::parse_type(self : Parser) -> TsType raise ParseError {
  let tok = self.advance()
  let base_type : TsType = match tok.kind {
    NumberType => Number
    IntType => Int
    BooleanType => Boolean
    StringType => String_
    VoidType => Void
    Ident(name) => Named(name)
    _ => raise ParseError("Expected type, got \{tok.kind}")
  }
  // 配列型をチェック: type[]
  if self.match_(LBracket) {
    let _ = self.expect(RBracket)
    Array(base_type)
  } else {
    base_type
  }
}

// ============================================
// 式パース
// ============================================

///|
/// 式をパース (最低優先度)
pub fn Parser::parse_expr(self : Parser) -> TsExpr raise ParseError {
  self.parse_ternary()
}

///|
/// 三項演算子: cond ? then : else
fn Parser::parse_ternary(self : Parser) -> TsExpr raise ParseError {
  let cond = self.parse_or()
  if self.match_(Question) {
    let then_expr = self.parse_expr()
    let _ = self.expect(Colon)
    let else_expr = self.parse_expr()
    Cond(cond, then_expr, else_expr)
  } else {
    cond
  }
}

///|
/// || (論理OR)
fn Parser::parse_or(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_and()
  while self.match_(PipePipe) {
    let right = self.parse_and()
    left = BinOp(Or, left, right)
  }
  left
}

///|
/// && (論理AND)
fn Parser::parse_and(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_equality()
  while self.match_(AmpAmp) {
    let right = self.parse_equality()
    left = BinOp(And, left, right)
  }
  left
}

///|
/// === !== == != (等価比較)
fn Parser::parse_equality(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_comparison()
  while true {
    if self.match_(EqEqEq) {
      let right = self.parse_comparison()
      left = BinOp(BinEq, left, right)
    } else if self.match_(BangEqEq) {
      let right = self.parse_comparison()
      left = BinOp(BinNe, left, right)
    } else if self.match_(EqEq) {
      let right = self.parse_comparison()
      left = BinOp(AbstractEq, left, right)
    } else if self.match_(BangEq) {
      let right = self.parse_comparison()
      left = BinOp(AbstractNe, left, right)
    } else {
      break
    }
  }
  left
}

///|
/// < <= > >= (比較)
fn Parser::parse_comparison(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_additive()
  while true {
    if self.match_(Lt) {
      let right = self.parse_additive()
      left = BinOp(BinLt, left, right)
    } else if self.match_(Le) {
      let right = self.parse_additive()
      left = BinOp(BinLe, left, right)
    } else if self.match_(Gt) {
      let right = self.parse_additive()
      left = BinOp(BinGt, left, right)
    } else if self.match_(Ge) {
      let right = self.parse_additive()
      left = BinOp(BinGe, left, right)
    } else {
      break
    }
  }
  left
}

///|
/// + - (加減算)
fn Parser::parse_additive(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_multiplicative()
  while true {
    if self.match_(Plus) {
      let right = self.parse_multiplicative()
      left = BinOp(Add, left, right)
    } else if self.match_(Minus) {
      let right = self.parse_multiplicative()
      left = BinOp(Sub, left, right)
    } else {
      break
    }
  }
  left
}

///|
/// * / % (乗除算)
fn Parser::parse_multiplicative(self : Parser) -> TsExpr raise ParseError {
  let mut left = self.parse_unary()
  while true {
    if self.match_(Star) {
      let right = self.parse_unary()
      left = BinOp(Mul, left, right)
    } else if self.match_(Slash) {
      let right = self.parse_unary()
      left = BinOp(Div, left, right)
    } else if self.match_(Percent) {
      let right = self.parse_unary()
      left = BinOp(Mod, left, right)
    } else {
      break
    }
  }
  left
}

///|
/// 単項演算子
fn Parser::parse_unary(self : Parser) -> TsExpr raise ParseError {
  if self.match_(Minus) {
    let operand = self.parse_unary()
    UnaryOp(Neg, operand)
  } else if self.match_(Bang) {
    let operand = self.parse_unary()
    UnaryOp(Not, operand)
  } else if self.match_(PlusPlus) {
    // ++x (前置インクリメント)
    let operand = self.parse_unary()
    UnaryOp(PreInc, operand)
  } else if self.match_(MinusMinus) {
    // --x (前置デクリメント)
    let operand = self.parse_unary()
    UnaryOp(PreDec, operand)
  } else {
    self.parse_postfix()
  }
}

///|
/// 後置演算子 (x++, x--)
fn Parser::parse_postfix(self : Parser) -> TsExpr raise ParseError {
  let mut expr = self.parse_call()
  while true {
    if self.match_(PlusPlus) {
      expr = UnaryOp(PostInc, expr)
    } else if self.match_(MinusMinus) {
      expr = UnaryOp(PostDec, expr)
    } else {
      break
    }
  }
  expr
}

///|
/// 関数呼び出し、配列アクセス、プロパティアクセス、メソッド呼び出し
fn Parser::parse_call(self : Parser) -> TsExpr raise ParseError {
  let mut expr = self.parse_primary()

  // 後置演算子をチェック
  while true {
    if self.match_(LParen) {
      // 関数呼び出し or メソッド呼び出し
      match expr {
        Var(name) => {
          let args = self.parse_args()
          let _ = self.expect(RParen)
          expr = Call(name, args)
        }
        PropAccess(receiver, method) => {
          // メソッド呼び出し: receiver.method(args)
          let args = self.parse_args()
          let _ = self.expect(RParen)
          expr = MethodCall(receiver, method, args)
        }
        _ => raise ParseError("Cannot call non-function")
      }
    } else if self.match_(LBracket) {
      // 配列アクセス
      let index = self.parse_expr()
      let _ = self.expect(RBracket)
      expr = IndexAccess(expr, index)
    } else if self.check(Dot) {
      // プロパティアクセス
      let _ = self.advance()
      let prop = match self.advance().kind {
        Ident(name) => name
        k => raise ParseError("Expected property name, got \{k}")
      }
      expr = PropAccess(expr, prop)
    } else {
      break
    }
  }
  expr
}

///|
/// 引数リストをパース
fn Parser::parse_args(self : Parser) -> Array[TsExpr] raise ParseError {
  let args : Array[TsExpr] = []
  if not(self.check(RParen)) {
    args.push(self.parse_expr())
    while self.match_(Comma) {
      args.push(self.parse_expr())
    }
  }
  args
}

///|
/// プライマリ式 (リテラル、変数、括弧、配列、new)
fn Parser::parse_primary(self : Parser) -> TsExpr raise ParseError {
  let tok = self.peek()
  match tok.kind {
    Number(n) => {
      let _ = self.advance()
      NumberLit(n)
    }
    Int(i) => {
      let _ = self.advance()
      IntLit(i)
    }
    Bool(b) => {
      let _ = self.advance()
      BoolLit(b)
    }
    Str(s) => {
      let _ = self.advance()
      StringLit(s)
    }
    Ident(name) => {
      let _ = self.advance()
      Var(name)
    }
    LParen =>
      // アロー関数かどうか判定
      if self.is_arrow_function() {
        // アロー関数: (params) => body
        let _ = self.advance() // (
        let params = self.parse_params()
        let _ = self.expect(RParen)
        let _ = self.expect(Arrow)
        // ボディ: ブロックか式
        let body = if self.check(LBrace) {
          let block = self.parse_block()
          ArrowBlock(block)
        } else {
          let expr = self.parse_expr()
          ArrowExpr(expr)
        }
        ArrowFunc(params, body)
      } else {
        // 通常の括弧付き式
        let _ = self.advance()
        let expr = self.parse_expr()
        let _ = self.expect(RParen)
        expr
      }
    LBracket => {
      // 配列リテラル: [1, 2, 3]
      let _ = self.advance()
      let elements : Array[TsExpr] = []
      if not(self.check(RBracket)) {
        elements.push(self.parse_expr())
        while self.match_(Comma) {
          elements.push(self.parse_expr())
        }
      }
      let _ = self.expect(RBracket)
      ArrayLit(elements)
    }
    New => {
      // new 式: new Array<number>(10)
      let _ = self.advance()
      let type_name = match self.advance().kind {
        Ident(n) => n
        k => raise ParseError("Expected type name after new, got \{k}")
      }
      // ジェネリクス型パラメータをスキップ (簡易実装)
      if self.match_(Lt) {
        let _ = self.parse_type()
        let _ = self.expect(Gt)

      }
      let _ = self.expect(LParen)
      let args = self.parse_args()
      let _ = self.expect(RParen)
      New(type_name, args)
    }
    LBrace => {
      // オブジェクトリテラル: { key: value, ... }
      let _ = self.advance()
      let fields : Array[(String, TsExpr)] = []
      if not(self.check(RBrace)) {
        // 最初のフィールド
        let key = match self.advance().kind {
          Ident(n) => n
          Str(s) => s
          k => raise ParseError("Expected property name, got \{k}")
        }
        let _ = self.expect(Colon)
        let value = self.parse_expr()
        fields.push((key, value))
        // 残りのフィールド
        while self.match_(Comma) {
          if self.check(RBrace) {
            break // trailing comma
          }
          let key = match self.advance().kind {
            Ident(n) => n
            Str(s) => s
            k => raise ParseError("Expected property name, got \{k}")
          }
          let _ = self.expect(Colon)
          let value = self.parse_expr()
          fields.push((key, value))
        }
      }
      let _ = self.expect(RBrace)
      ObjectLit(fields)
    }
    Null => {
      // null リテラル
      let _ = self.advance()
      NullLit
    }
    _ => raise ParseError("Unexpected token: \{tok.kind}")
  }
}

// ============================================
// 文パース
// ============================================

///|
/// 文をパース
pub fn Parser::parse_stmt(self : Parser) -> TsStmt raise ParseError {
  let tok = self.peek()
  match tok.kind {
    Let => self.parse_let()
    Const => self.parse_const()
    Return => self.parse_return()
    If => self.parse_if()
    While => self.parse_while()
    For => self.parse_for()
    Function => {
      // 内部関数定義: function name() { ... }
      // Let(name, Any, FuncExpr(func)) として扱う
      let func = self.parse_function()
      Let(func.name, Any, FuncExpr(func))
    }
    Break => {
      let _ = self.advance()
      let _ = self.expect(Semicolon)
      Break
    }
    Continue => {
      let _ = self.advance()
      let _ = self.expect(Semicolon)
      Continue
    }
    LBrace =>
      // ブロックは式として扱わない（文の配列として処理）
      raise ParseError("Unexpected block")
    _ =>
      // 代入 or 式文
      self.parse_assign_or_expr()
  }
}

///|
/// let 文 (型注釈はオプショナル)
fn Parser::parse_let(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Let)
  let name = match self.advance().kind {
    Ident(n) => n
    k => raise ParseError("Expected identifier, got \{k}")
  }
  // 型注釈 (オプショナル)
  let type_ = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any // 型注釈がなければ Any
  }
  let _ = self.expect(Eq)
  let init = self.parse_expr()
  let _ = self.expect(Semicolon)
  Let(name, type_, init)
}

///|
/// const 文 (型注釈はオプショナル)
fn Parser::parse_const(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Const)
  let name = match self.advance().kind {
    Ident(n) => n
    k => raise ParseError("Expected identifier, got \{k}")
  }
  // 型注釈 (オプショナル)
  let type_ = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any // 型注釈がなければ Any
  }
  let _ = self.expect(Eq)
  let init = self.parse_expr()
  let _ = self.expect(Semicolon)
  Const(name, type_, init)
}

///|
/// return 文
fn Parser::parse_return(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(Return)
  if self.check(Semicolon) {
    let _ = self.advance()
    Return(None)
  } else {
    let expr = self.parse_expr()
    let _ = self.expect(Semicolon)
    Return(Some(expr))
  }
}

///|
/// if 文
fn Parser::parse_if(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(If)
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  let then_block = self.parse_block()
  let else_block = if self.match_(Else) {
    if self.check(If) {
      // else if
      { stmts: [self.parse_if()] }
    } else {
      self.parse_block()
    }
  } else {
    { stmts: [] }
  }
  If(cond, then_block, Some(else_block))
}

///|
/// while 文
fn Parser::parse_while(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(While)
  let _ = self.expect(LParen)
  let cond = self.parse_expr()
  let _ = self.expect(RParen)
  let body = self.parse_block()
  While(cond, body)
}

///|
/// for 文 (通常のforまたはfor...of)
fn Parser::parse_for(self : Parser) -> TsStmt raise ParseError {
  let _ = self.expect(For)
  let _ = self.expect(LParen)

  // for...of のチェック: for (const x of arr) or for (let x of arr)
  if self.check(Let) || self.check(Const) {
    let _ = self.advance() // let/const
    let var_name = match self.advance().kind {
      Ident(n) => n
      k => raise ParseError("Expected variable name, got \{k}")
    }
    // for...of かチェック
    if self.check(Of) {
      let _ = self.advance() // of
      let iterable = self.parse_expr()
      let _ = self.expect(RParen)
      let body = self.parse_block()
      // 配列の要素型を推論 (デフォルトは Number)
      return ForOf(var_name, Number, iterable, body)
    }
    // 通常の for (let x: type = init; ...) or for (let x = init; ...)
    let var_type = if self.check(Colon) {
      let _ = self.advance()
      self.parse_type()
    } else {
      Any // 型注釈がなければ Any
    }
    let _ = self.expect(Eq)
    let init_expr = self.parse_expr()
    let _ = self.expect(Semicolon)
    let init : TsStmt? = Some(Let(var_name, var_type, init_expr))
    return self.parse_for_rest(init)
  }

  // init
  let init : TsStmt? = if self.check(Semicolon) {
    let _ = self.advance()
    None
  } else {
    let stmt = self.parse_assign_or_expr()
    Some(stmt)
  }
  self.parse_for_rest(init)
}

///|
/// for文の残りをパース (cond, update, body)
fn Parser::parse_for_rest(
  self : Parser,
  init : TsStmt?,
) -> TsStmt raise ParseError {

  // cond
  let cond : TsExpr? = if self.check(Semicolon) {
    None
  } else {
    Some(self.parse_expr())
  }
  let _ = self.expect(Semicolon)

  // update (セミコロンなし)
  let update : TsStmt? = if self.check(RParen) {
    None
  } else {
    let expr = self.parse_expr()
    if self.match_(Eq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(Assign(name, value))
        IndexAccess(arr, index) => Some(IndexAssign(arr, index, value))
        PropAccess(obj, prop) => Some(PropAssign(obj, prop, value))
        _ => raise ParseError("Invalid assignment target in for update")
      }
    } else if self.match_(PlusEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, AddAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else if self.match_(MinusEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, SubAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else if self.match_(StarEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, MulAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else if self.match_(SlashEq) {
      let value = self.parse_expr()
      match expr {
        Var(name) => Some(CompoundAssign(name, DivAssign, value))
        _ => raise ParseError("Invalid compound assignment in for update")
      }
    } else {
      Some(Expr(expr))
    }
  }
  let _ = self.expect(RParen)
  let body = self.parse_block()
  For(init, cond, update, body)
}

///|
/// 代入または式文
fn Parser::parse_assign_or_expr(self : Parser) -> TsStmt raise ParseError {
  // まず式をパース
  let expr = self.parse_expr()

  // 代入かチェック
  if self.match_(Eq) {
    let value = self.parse_expr()
    let _ = self.expect(Semicolon)
    match expr {
      Var(name) => Assign(name, value)
      IndexAccess(arr, index) => IndexAssign(arr, index, value)
      PropAccess(obj, prop) => PropAssign(obj, prop, value)
      _ => raise ParseError("Invalid assignment target")
    }
  } else if self.match_(PlusEq) {
    let value = self.parse_expr()
    let _ = self.expect(Semicolon)
    match expr {
      Var(name) => CompoundAssign(name, AddAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else if self.match_(MinusEq) {
    let value = self.parse_expr()
    let _ = self.expect(Semicolon)
    match expr {
      Var(name) => CompoundAssign(name, SubAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else if self.match_(StarEq) {
    let value = self.parse_expr()
    let _ = self.expect(Semicolon)
    match expr {
      Var(name) => CompoundAssign(name, MulAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else if self.match_(SlashEq) {
    let value = self.parse_expr()
    let _ = self.expect(Semicolon)
    match expr {
      Var(name) => CompoundAssign(name, DivAssign, value)
      _ => raise ParseError("Invalid compound assignment target")
    }
  } else {
    let _ = self.expect(Semicolon)
    Expr(expr)
  }
}

///|
/// ブロックをパース
pub fn Parser::parse_block(self : Parser) -> TsBlock raise ParseError {
  let _ = self.expect(LBrace)
  let stmts : Array[TsStmt] = []
  while not(self.check(RBrace)) && not(self.check(Eof)) {
    stmts.push(self.parse_stmt())
  }
  let _ = self.expect(RBrace)
  { stmts, }
}

// ============================================
// 関数・モジュールパース
// ============================================

///|
/// パラメータをパース
fn Parser::parse_param(self : Parser) -> TsParam raise ParseError {
  let name = match self.advance().kind {
    Ident(n) => n
    k => raise ParseError("Expected parameter name, got \{k}")
  }
  // 型注釈 (オプショナル)
  let type_ = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any // 型注釈がなければ Any
  }
  // デフォルト値をチェック
  let default : TsExpr? = if self.match_(Eq) {
    Some(self.parse_expr())
  } else {
    None
  }
  { name, type_, default }
}

///|
/// パラメータリストをパース
fn Parser::parse_params(self : Parser) -> Array[TsParam] raise ParseError {
  let params : Array[TsParam] = []
  if not(self.check(RParen)) {
    params.push(self.parse_param())
    while self.match_(Comma) {
      params.push(self.parse_param())
    }
  }
  params
}

///|
/// 関数をパース
pub fn Parser::parse_function(self : Parser) -> TsFunc raise ParseError {
  let _ = self.expect(Function)
  let name = match self.advance().kind {
    Ident(n) => n
    k => raise ParseError("Expected function name, got \{k}")
  }
  let _ = self.expect(LParen)
  let params = self.parse_params()
  let _ = self.expect(RParen)
  // 戻り値型 (オプショナル)
  let return_type = if self.check(Colon) {
    let _ = self.advance()
    self.parse_type()
  } else {
    Any // 型注釈がなければ Any
  }
  let body = self.parse_block()
  { name, params, return_type, body }
}

///|
/// インターフェースをパース
pub fn Parser::parse_interface(self : Parser) -> TsInterface raise ParseError {
  let _ = self.expect(Interface)
  let name = match self.advance().kind {
    Ident(n) => n
    k => raise ParseError("Expected interface name, got \{k}")
  }
  let _ = self.expect(LBrace)
  let fields : Array[(String, TsType)] = []
  while not(self.check(RBrace)) && not(self.check(Eof)) {
    // field: type;
    let field_name = match self.advance().kind {
      Ident(n) => n
      k => raise ParseError("Expected field name, got \{k}")
    }
    let _ = self.expect(Colon)
    let field_type = self.parse_type()
    let _ = self.expect(Semicolon)
    fields.push((field_name, field_type))
  }
  let _ = self.expect(RBrace)
  { name, fields }
}

///|
/// declare function をパース
/// declare function name(params): returnType;
pub fn Parser::parse_import(self : Parser) -> TsImport raise ParseError {
  let _ = self.expect(Declare)
  let _ = self.expect(Function)

  // 関数名
  let name = match self.advance().kind {
    Ident(n) => n
    _ => raise ParseError("Expected function name after 'declare function'")
  }

  // パラメータ
  let _ = self.expect(LParen)
  let params : Array[(String, TsType)] = []
  while not(self.check(RParen)) {
    let param_name = match self.advance().kind {
      Ident(n) => n
      _ => raise ParseError("Expected parameter name")
    }
    let _ = self.expect(Colon)
    let param_type = self.parse_type()
    params.push((param_name, param_type))
    if self.check(Comma) {
      let _ = self.advance()

    }
  }
  let _ = self.expect(RParen)

  // 戻り値型
  let _ = self.expect(Colon)
  let return_type = self.parse_type()

  // セミコロン
  let _ = self.expect(Semicolon)
  { name, module_: "env", params, return_type }
}

///|
/// モジュールをパース
pub fn Parser::parse_module(self : Parser) -> TsModule raise ParseError {
  let funcs : Array[TsFunc] = []
  let interfaces : Array[TsInterface] = []
  let imports : Array[TsImport] = []
  while not(self.check(Eof)) {
    if self.check(Function) {
      funcs.push(self.parse_function())
    } else if self.check(Interface) {
      interfaces.push(self.parse_interface())
    } else if self.check(Declare) {
      imports.push(self.parse_import())
    } else {
      raise ParseError("Expected function, interface, or declare declaration")
    }
  }
  { funcs, interfaces, imports }
}
