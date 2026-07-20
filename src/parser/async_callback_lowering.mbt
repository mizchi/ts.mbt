///|
/// Async-callback lowering, shared by the decl (`.mbti`) and ffi
/// (`bridge.mbt`) layers so the two rendered surfaces cannot drift.
///
/// A rendered param type `(A, B) -> Promise[T]` is a JS callback that
/// must return a promise (React 19 `useActionState`-style actions,
/// promise-returning handlers). On public wrappers these lower to
/// `async (A, B) -> T raise`, glued back through the generated
/// package's `Promise::from_async`. The optional form
/// `((A, B) -> Promise[T])?` lowers to `(async (A, B) -> T raise)?`
/// with `Option::map` glue.
pub struct AsyncCallbackLowering {
  lowered_type : String
  arity : Int
  is_optional : Bool
}

///|
fn async_cb_find_matching_paren(text : String, open_index : Int) -> Int? {
  let mut depth = 0
  for i, c in text.iter2() {
    if i < open_index {
      continue
    }
    if c == '(' {
      depth += 1
    } else if c == ')' {
      depth -= 1
      if depth == 0 {
        return Some(i)
      }
    }
  }
  None
}

///|
fn async_cb_split_top_level_commas(source : String) -> Array[String] {
  let parts : Array[String] = []
  let mut current = ""
  let mut paren_depth = 0
  let mut bracket_depth = 0
  for c in source {
    if c == ',' && paren_depth == 0 && bracket_depth == 0 {
      parts.push(current.trim().to_owned())
      current = ""
      continue
    }
    current += c.to_string()
    if c == '(' {
      paren_depth += 1
    } else if c == ')' {
      if paren_depth > 0 {
        paren_depth -= 1
      }
    } else if c == '[' {
      bracket_depth += 1
    } else if c == ']' {
      if bracket_depth > 0 {
        bracket_depth -= 1
      }
    }
  }
  let tail = current.trim().to_owned()
  if tail != "" || source.trim() != "" {
    parts.push(tail)
  }
  parts
}

///|
fn async_cb_plain_parts(type_name : String) -> (Array[String], String)? {
  if !type_name.has_prefix("(") {
    return None
  }
  let close = match async_cb_find_matching_paren(type_name, 0) {
    Some(index) => index
    None => return None
  }
  let after = type_name[close + 1:].to_owned().trim().to_owned()
  if !after.has_prefix("->") {
    return None
  }
  let ret = after[2:].to_owned().trim().to_owned()
  if !ret.has_prefix("Promise[") || !ret.has_suffix("]") {
    return None
  }
  let payload = ret["Promise[".length():ret.length() - 1]
    .to_owned()
    .trim()
    .to_owned()
  if payload == "" {
    return None
  }
  let params : Array[String] = []
  let params_src = type_name[1:close].to_owned()
  if params_src.trim() != "" {
    for item in async_cb_split_top_level_commas(params_src) {
      if item != "" {
        params.push(item)
      }
    }
  }
  Some((params, payload))
}

///|
/// Detect a rendered callback type that lowers to a MoonBit async fn.
/// Returns `None` for everything that must stay on the raw
/// promise-returning form (non-promise callbacks, named callback
/// aliases, union-typed handler slots).
pub fn moonbit_async_callback_lowering(
  type_name : String,
) -> AsyncCallbackLowering? {
  // Optional form: `((A, B) -> Promise[T])?` — the whole type is one
  // parenthesized group followed by `?`.
  if type_name.has_suffix(")?") && type_name.has_prefix("(") {
    match async_cb_find_matching_paren(type_name, 0) {
      Some(close) if close == type_name.length() - 2 => {
        let inner = type_name[1:close].to_owned().trim().to_owned()
        match async_cb_plain_parts(inner) {
          Some((params, payload)) => {
            let params_src = params.join(", ")
            return Some({
              lowered_type: "(async (\{params_src}) -> \{payload} raise)?",
              arity: params.length(),
              is_optional: true,
            })
          }
          None => return None
        }
      }
      _ => ()
    }
  }
  match async_cb_plain_parts(type_name) {
    Some((params, payload)) => {
      let params_src = params.join(", ")
      Some({
        lowered_type: "async (\{params_src}) -> \{payload} raise",
        arity: params.length(),
        is_optional: false,
      })
    }
    None => None
  }
}

///|
/// The expression converting a lowered public argument back into the
/// raw promise-returning callback the extern / JS side expects. Emitted
/// code lives inside the generated bridge package, where the injected
/// `Promise::from_async` is in scope unqualified.
pub fn moonbit_async_callback_glue_expr(
  arg_name : String,
  lowering : AsyncCallbackLowering,
) -> String {
  let cb_params : Array[String] = []
  for i in 0..<lowering.arity {
    cb_params.push("__ts_mbt_cb_a\{i}")
  }
  let cb_params_src = cb_params.join(", ")
  if lowering.is_optional {
    "\{arg_name}.map(fn(__ts_mbt_cb_f) { fn(\{cb_params_src}) { Promise::from_async(async fn() raise { __ts_mbt_cb_f(\{cb_params_src}) }) } })"
  } else {
    "fn(\{cb_params_src}) { Promise::from_async(async fn() raise { \{arg_name}(\{cb_params_src}) }) }"
  }
}
