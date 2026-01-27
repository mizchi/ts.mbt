// test262 sta.js implementation

///|
// / Test262Error - test262error
pub struct Test262Error {
  message : String
}

///|
// / Test262Error create
pub fn Test262Error::new(message : String) -> Test262Error {
  { message, }
}

///|
// / Test262Error stringconversion
pub fn Test262Error::to_string(self : Test262Error) -> String {
  "Test262Error: " + self.message
}

///|
// / $DONOTEVALUATE runfunction
pub fn dont_evaluate() -> JSValue {
  // function, test
  // TODO: Test262Error
  JSValue::Undefined
}
