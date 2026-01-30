///|
fn time_clip(t : Double) -> Double {
  if t.is_nan() || t.is_inf() {
    return js_nan
  }
  let abs = if t < 0.0 { -t } else { t }
  if abs > 8.64e15 {
    js_nan
  } else {
    t.trunc()
  }
}

///|
fn JSInterpreter::date_time_value(
  self : JSInterpreter,
  this_arg : JSValue,
) -> Double? {
  match this_arg {
    Object(_) | Array(_) | Function(_) => ()
    _ => {
      let _ = self.set_error_kind("TypeError", "Not a Date object")
      return None
    }
  }
  match js_get_prop(this_arg, "__class") {
    String("Date") => ()
    _ => {
      let _ = self.set_error_kind("TypeError", "Not a Date object")
      return None
    }
  }
  match js_get_prop(this_arg, "__date_value") {
    Number(n) => Some(n)
    _ => Some(js_nan)
  }
}
