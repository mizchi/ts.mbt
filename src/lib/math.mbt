///|
pub fn math_trunc(n : Double) -> Double {
  if n.is_nan() || n.is_inf() {
    n
  } else if n >= 0.0 {
    n.floor()
  } else {
    n.ceil()
  }
}

///|
pub fn math_sign(x : Double) -> Double {
  if x.is_nan() {
    x
  } else if x > 0.0 {
    1.0
  } else if x < 0.0 {
    -1.0
  } else {
    x // preserves +0 and -0
  }
}

///|
pub fn math_cbrt(x : Double) -> Double {
  if x < 0.0 {
    -@math.pow(-x, 1.0 / 3.0)
  } else {
    @math.pow(x, 1.0 / 3.0)
  }
}

///|
pub fn math_log10(x : Double) -> Double {
  @math.ln(x) / @math.ln(10.0)
}

///|
pub fn math_log2(x : Double) -> Double {
  @math.ln(x) / @math.ln(2.0)
}

///|
pub fn math_sinh(x : Double) -> Double {
  (@math.exp(x) - @math.exp(-x)) / 2.0
}

///|
pub fn math_cosh(x : Double) -> Double {
  (@math.exp(x) + @math.exp(-x)) / 2.0
}

///|
pub fn math_tanh(x : Double) -> Double {
  let ex = @math.exp(x)
  let enx = @math.exp(-x)
  (ex - enx) / (ex + enx)
}

///|
pub fn math_asinh(x : Double) -> Double {
  @math.ln(x + (x * x + 1.0).sqrt())
}

///|
pub fn math_acosh(x : Double) -> Double {
  @math.ln(x + (x * x - 1.0).sqrt())
}

///|
pub fn math_atanh(x : Double) -> Double {
  @math.ln((1.0 + x) / (1.0 - x)) / 2.0
}

///|
pub fn math_expm1(x : Double) -> Double {
  @math.exp(x) - 1.0
}

///|
pub fn math_log1p(x : Double) -> Double {
  @math.ln(1.0 + x)
}

///|
pub fn math_hypot(values : Array[Double]) -> Double {
  if values.length() == 0 {
    return 0.0
  }
  let mut sum = 0.0
  for v in values {
    if v.is_inf() || v.is_neg_inf() {
      return 1.0 / 0.0 // Infinity
    }
    if v.is_nan() {
      return v
    }
    sum += v * v
  }
  sum.sqrt()
}

///|
pub fn math_min(values : Array[Double]) -> Double {
  if values.length() == 0 {
    return 1.0 / 0.0 // Infinity
  }
  let mut min_val = values[0]
  if min_val.is_nan() {
    return min_val
  }
  for i in 1..<values.length() {
    let val = values[i]
    if val.is_nan() {
      return val
    }
    if val < min_val {
      min_val = val
    }
  }
  min_val
}

///|
pub fn math_max(values : Array[Double]) -> Double {
  if values.length() == 0 {
    return -1.0 / 0.0 // -Infinity
  }
  let mut max_val = values[0]
  if max_val.is_nan() {
    return max_val
  }
  for i in 1..<values.length() {
    let val = values[i]
    if val.is_nan() {
      return val
    }
    if val > max_val {
      max_val = val
    }
  }
  max_val
}

///|
pub fn math_clz32(n : Double) -> Int {
  let x = n.to_int().land(0xFFFFFFFF)
  if x == 0 {
    return 32
  }
  let mut count = 0
  let mut val = x
  while val.land(0x80000000) == 0 {
    count = count + 1
    val = val << 1
  }
  count
}

///|
pub fn math_imul(a : Double, b : Double) -> Int {
  let x = a.to_int().land(0xFFFFFFFF)
  let y = b.to_int().land(0xFFFFFFFF)
  x * y
}

///|
pub fn math_fround(x : Double) -> Double {
  // Simple approximation - convert to float32 precision
  let f = Float::from_double(x)
  f.to_double()
}
