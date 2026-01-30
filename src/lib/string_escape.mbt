///|
fn hex_digit(value : Int) -> Char {
  let hex = "0123456789ABCDEF"
  let idx = if value < 0 { 0 } else if value > 15 { 15 } else { value }
  let unit = hex[idx]
  unit.unsafe_to_char()
}

///|
fn append_hex2(sb : StringBuilder, value : Int) -> Unit {
  let hi = (value >> 4) & 0xf
  let lo = value & 0xf
  sb.write_char(hex_digit(hi))
  sb.write_char(hex_digit(lo))
}

///|
fn append_hex4(sb : StringBuilder, value : Int) -> Unit {
  let a = (value >> 12) & 0xf
  let b = (value >> 8) & 0xf
  let c = (value >> 4) & 0xf
  let d = value & 0xf
  sb.write_char(hex_digit(a))
  sb.write_char(hex_digit(b))
  sb.write_char(hex_digit(c))
  sb.write_char(hex_digit(d))
}

///|
fn is_escape_passthrough(code : Int) -> Bool {
  if (code >= 0x41 && code <= 0x5a) ||
    (code >= 0x61 && code <= 0x7a) ||
    (code >= 0x30 && code <= 0x39) {
    return true
  }
  match code {
    0x40 | 0x2a | 0x5f | 0x2b | 0x2d | 0x2e | 0x2f => true
    _ => false
  }
}

///|
pub fn escape_string(value : String) -> String {
  let sb = StringBuilder::new()
  let len = value.length()
  let mut i = 0
  while i < len {
    let unit = value[i]
    let code = unit.to_int()
    if is_escape_passthrough(code) {
      sb.write_char(unit.unsafe_to_char())
    } else if code < 256 {
      sb.write_char('%')
      append_hex2(sb, code)
    } else {
      sb.write_string("%u")
      append_hex4(sb, code)
    }
    i += 1
  }
  sb.to_string()
}

///|
fn hex_value(unit : UInt16) -> Int? {
  let code = unit.to_int()
  if code >= 0x30 && code <= 0x39 {
    Some(code - 0x30)
  } else if code >= 0x41 && code <= 0x46 {
    Some(code - 0x37)
  } else if code >= 0x61 && code <= 0x66 {
    Some(code - 0x57)
  } else {
    None
  }
}

///|
pub fn unescape_string(value : String) -> String {
  let sb = StringBuilder::new()
  let len = value.length()
  let percent : UInt16 = '%'
  let u_char : UInt16 = 'u'
  let mut k = 0
  while k < len {
    let unit = value[k]
    if unit == percent {
      if k + 5 < len && value[k + 1] == u_char {
        match
          (
            hex_value(value[k + 2]),
            hex_value(value[k + 3]),
            hex_value(value[k + 4]),
            hex_value(value[k + 5]),
          ) {
          (Some(a), Some(b), Some(c), Some(d)) => {
            let code = (a << 12) | (b << 8) | (c << 4) | d
            let ch = code.to_uint16().unsafe_to_char()
            sb.write_char(ch)
            k += 6
            continue
          }
          _ => ()
        }
      }
      if k + 2 < len {
        match (hex_value(value[k + 1]), hex_value(value[k + 2])) {
          (Some(a), Some(b)) => {
            let code = (a << 4) | b
            let ch = code.to_uint16().unsafe_to_char()
            sb.write_char(ch)
            k += 3
            continue
          }
          _ => ()
        }
      }
      sb.write_char(percent.unsafe_to_char())
      k += 1
    } else {
      sb.write_char(unit.unsafe_to_char())
      k += 1
    }
  }
  sb.to_string()
}
