///|
fn JSInterpreter::call_math_native(
  self : JSInterpreter,
  name : String,
  args : Array[JSValue],
) -> JSValue? {
  let _ = self
  match name {
    "Math.floor" =>
      Some(
        if args.length() > 0 {
          Number(args[0].to_number().floor())
        } else {
          Number(js_nan)
        },
      )
    "Math.ceil" =>
      Some(
        if args.length() > 0 {
          Number(args[0].to_number().ceil())
        } else {
          Number(js_nan)
        },
      )
    "Math.abs" =>
      Some(
        if args.length() > 0 {
          Number(args[0].to_number().abs())
        } else {
          Number(js_nan)
        },
      )
    "Math.sqrt" =>
      Some(
        if args.length() > 0 {
          Number(args[0].to_number().sqrt())
        } else {
          Number(js_nan)
        },
      )
    "Math.cos" =>
      Some(
        if args.length() > 0 {
          Number(@math.cos(args[0].to_number()))
        } else {
          Number(js_nan)
        },
      )
    "Math.sin" =>
      Some(
        if args.length() > 0 {
          Number(@math.sin(args[0].to_number()))
        } else {
          Number(js_nan)
        },
      )
    "Math.tan" =>
      Some(
        if args.length() > 0 {
          Number(@math.tan(args[0].to_number()))
        } else {
          Number(js_nan)
        },
      )
    "Math.exp" =>
      Some(
        if args.length() > 0 {
          Number(@math.exp(args[0].to_number()))
        } else {
          Number(js_nan)
        },
      )
    "Math.log" =>
      Some(
        if args.length() > 0 {
          Number(@math.ln(args[0].to_number()))
        } else {
          Number(js_nan)
        },
      )
    "Math.trunc" =>
      Some(
        if args.length() > 0 {
          Number(@lib.math_trunc(args[0].to_number()))
        } else {
          Number(js_nan)
        },
      )
    "Math.min" =>
      Some(
        if args.length() == 0 {
          Number(1.0 / 0.0)
        } else if args.length() == 1 {
          Number(args[0].to_number())
        } else {
          let mut min_val = args[0].to_number()
          if min_val.is_nan() {
            Number(min_val)
          } else {
            for i in 1..<args.length() {
              let val = args[i].to_number()
              if val.is_nan() {
                min_val = val
                break
              }
              if val < min_val {
                min_val = val
              }
            }
            Number(min_val)
          }
        },
      )
    "Math.max" =>
      Some(
        if args.length() == 0 {
          Number(-1.0 / 0.0)
        } else if args.length() == 1 {
          Number(args[0].to_number())
        } else {
          let mut max_val = args[0].to_number()
          if max_val.is_nan() {
            Number(max_val)
          } else {
            for i in 1..<args.length() {
              let val = args[i].to_number()
              if val.is_nan() {
                max_val = val
                break
              }
              if val > max_val {
                max_val = val
              }
            }
            Number(max_val)
          }
        },
      )
    "Math.round" =>
      Some(
        if args.length() > 0 {
          Number(args[0].to_number().round())
        } else {
          Number(js_nan)
        },
      )
    "Math.random" => Some(Number(0.5)) // TODO: proper random implementation
    "Math.pow" => {
      let base = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      let exp = if args.length() > 1 { args[1].to_number() } else { 0.0 / 0.0 }
      Some(Number(@math.pow(base, exp)))
    }
    "Math.sign" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_sign(x)))
    }
    "Math.log10" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_log10(x)))
    }
    "Math.log2" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_log2(x)))
    }
    "Math.cbrt" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_cbrt(x)))
    }
    "Math.hypot" => {
      let values : Array[Double] = []
      for arg in args {
        values.push(arg.to_number())
      }
      Some(Number(@lib.math_hypot(values)))
    }
    "Math.atan2" => {
      let y = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      let x = if args.length() > 1 { args[1].to_number() } else { 0.0 / 0.0 }
      Some(Number(@math.atan2(y, x)))
    }
    "Math.asin" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@math.asin(x)))
    }
    "Math.acos" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@math.acos(x)))
    }
    "Math.atan" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@math.atan(x)))
    }
    "Math.sinh" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_sinh(x)))
    }
    "Math.cosh" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_cosh(x)))
    }
    "Math.tanh" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_tanh(x)))
    }
    "Math.asinh" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_asinh(x)))
    }
    "Math.acosh" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_acosh(x)))
    }
    "Math.atanh" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_atanh(x)))
    }
    "Math.expm1" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_expm1(x)))
    }
    "Math.log1p" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_log1p(x)))
    }
    "Math.fround" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_fround(x)))
    }
    "Math.clz32" => {
      let x = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_clz32(x).to_double()))
    }
    "Math.imul" => {
      let a = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      let b = if args.length() > 1 { args[1].to_number() } else { 0.0 / 0.0 }
      Some(Number(@lib.math_imul(a, b).to_double()))
    }
    _ => None
  }
}
