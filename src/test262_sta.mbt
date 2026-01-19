// test262 sta.js implementation

///|
/// Test262Error - test262固有のエラークラス
pub struct Test262Error {
  message : String
}

///|
/// Test262Error を作成
pub fn Test262Error::new(message : String) -> Test262Error {
  { message, }
}

///|
/// Test262Error を文字列に変換
pub fn Test262Error::to_string(self : Test262Error) -> String {
  "Test262Error: " + self.message
}

///|
/// $DONOTEVALUATE を実行する関数
pub fn dont_evaluate() -> JSValue {
  // この関数が呼び出された場合、テストは失敗するはず
  // TODO: Test262Error をスローするように修正する必要がある
  JSValue::Undefined
}
