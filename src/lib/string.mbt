///|
pub fn is_js_whitespace(unit : UInt16) -> Bool {
  let code = unit.to_int()
  if code == 0x0009 {
    return true
  }
  if code == 0x000a {
    return true
  }
  if code == 0x000b {
    return true
  }
  if code == 0x000c {
    return true
  }
  if code == 0x000d {
    return true
  }
  if code == 0x0020 {
    return true
  }
  if code == 0x00a0 {
    return true
  }
  if code == 0x1680 {
    return true
  }
  if code >= 0x2000 && code <= 0x200a {
    return true
  }
  if code == 0x2028 {
    return true
  }
  if code == 0x2029 {
    return true
  }
  if code == 0x202f {
    return true
  }
  if code == 0x205f {
    return true
  }
  if code == 0x3000 {
    return true
  }
  if code == 0xfeff {
    return true
  }
  false
}

///|
pub fn trim_string(s : String, mode : String) -> String {
  let len = s.length()
  let mut start = 0
  let mut end = len
  if mode == "both" || mode == "start" {
    while start < end && is_js_whitespace(s[start]) {
      start = start + 1
    }
  }
  if mode == "both" || mode == "end" {
    while end > start && is_js_whitespace(s[end - 1]) {
      end = end - 1
    }
  }
  s[start:end].to_string() catch {
    _ => ""
  }
}

///|
pub fn string_char_at(s : String, idx : Int) -> String {
  if idx >= 0 && idx < s.length() {
    s[idx:idx + 1].to_string() catch { _ => "" }
  } else {
    ""
  }
}

///|
pub fn string_char_code_at(s : String, idx : Int) -> Double {
  if idx >= 0 && idx < s.length() {
    s[idx].to_int().to_double()
  } else {
    0.0 / 0.0 // NaN
  }
}

///|
pub fn string_code_point_at(s : String, idx : Int) -> Double? {
  if idx < 0 || idx >= s.length() {
    None
  } else {
    let cu1 = s[idx]
    if cu1.is_leading_surrogate() && idx + 1 < s.length() {
      let cu2 = s[idx + 1]
      if cu2.is_trailing_surrogate() {
        let hi = cu1.to_int() - 0xd800
        let lo = cu2.to_int() - 0xdc00
        let code = hi * 0x400 + lo + 0x10000
        Some(code.to_double())
      } else {
        Some(cu1.to_int().to_double())
      }
    } else {
      Some(cu1.to_int().to_double())
    }
  }
}

///|
pub fn string_index_of(s : String, search : String, start_idx : Int) -> Int {
  let mut start = start_idx
  if start < 0 {
    start = 0
  }
  if search.length() == 0 {
    return start
  }
  let search_len = search.length()
  if start >= s.length() || start + search_len > s.length() {
    return -1
  }
  let end_idx = s.length() - search_len + 1
  let mut i = start
  while i < end_idx {
    if (s[i:i + search_len].to_string() catch { _ => "" }) == search {
      return i
    }
    i = i + 1
  }
  -1
}

///|
pub fn string_last_index_of(s : String, search : String, pos : Int) -> Int {
  let mut p = pos
  if p > s.length() {
    p = s.length()
  }
  if p < 0 {
    p = 0
  }
  if search.length() == 0 {
    return p
  }
  let search_len = search.length()
  let mut i = p - search_len
  if i < 0 {
    i = 0
  }
  while i >= 0 {
    if (s[i:i + search_len].to_string() catch { _ => "" }) == search {
      return i
    }
    if i == 0 {
      break
    }
    i = i - 1
  }
  -1
}

///|
pub fn string_includes(s : String, search : String, start_idx : Int) -> Bool {
  string_index_of(s, search, start_idx) != -1
}

///|
pub fn string_starts_with(s : String, search : String, pos : Int) -> Bool {
  let mut p = pos
  if p < 0 {
    p = 0
  }
  let search_len = search.length()
  if search_len == 0 {
    true
  } else if p + search_len > s.length() {
    false
  } else {
    (s[p:p + search_len].to_string() catch { _ => "" }) == search
  }
}

///|
pub fn string_ends_with(s : String, search : String, end_pos : Int) -> Bool {
  let mut ep = end_pos
  if ep > s.length() {
    ep = s.length()
  }
  if ep < 0 {
    ep = 0
  }
  let search_len = search.length()
  if search_len == 0 {
    true
  } else if search_len > ep {
    false
  } else {
    let start = ep - search_len
    (s[start:ep].to_string() catch { _ => "" }) == search
  }
}

///|
pub fn string_at(s : String, idx : Int) -> String? {
  let mut i = idx
  if i < 0 {
    i = s.length() + i
  }
  if i < 0 || i >= s.length() {
    None
  } else {
    Some(s[i:i + 1].to_string() catch { _ => "" })
  }
}

///|
pub fn string_slice(s : String, start : Int, end : Int) -> String {
  let len = s.length()
  let mut st = start
  let mut en = end
  if st < 0 {
    st = len + st
    if st < 0 {
      st = 0
    }
  }
  if en < 0 {
    en = len + en
    if en < 0 {
      en = 0
    }
  }
  if st > len {
    st = len
  }
  if en > len {
    en = len
  }
  if st >= en {
    ""
  } else {
    s[st:en].to_string() catch { _ => "" }
  }
}

///|
pub fn string_substring(s : String, start : Int, end : Int) -> String {
  let len = s.length()
  let mut st = start
  let mut en = end
  if st < 0 {
    st = 0
  }
  if en < 0 {
    en = 0
  }
  if st > len {
    st = len
  }
  if en > len {
    en = len
  }
  if st > en {
    let tmp = st
    st = en
    en = tmp
  }
  s[st:en].to_string() catch { _ => "" }
}

///|
pub fn string_pad_start(s : String, target_len : Int, pad_str : String) -> String {
  let len = s.length()
  if target_len <= len {
    return s
  }
  let pad = if pad_str.length() == 0 { " " } else { pad_str }
  let fill_len = target_len - len
  let sb = StringBuilder::new()
  let mut filled = 0
  while filled < fill_len {
    let remaining = fill_len - filled
    if remaining >= pad.length() {
      sb.write_string(pad)
      filled = filled + pad.length()
    } else {
      sb.write_string(pad[0:remaining].to_string() catch { _ => "" })
      filled = fill_len
    }
  }
  sb.write_string(s)
  sb.to_string()
}

///|
pub fn string_pad_end(s : String, target_len : Int, pad_str : String) -> String {
  let len = s.length()
  if target_len <= len {
    return s
  }
  let pad = if pad_str.length() == 0 { " " } else { pad_str }
  let fill_len = target_len - len
  let sb = StringBuilder::new()
  sb.write_string(s)
  let mut filled = 0
  while filled < fill_len {
    let remaining = fill_len - filled
    if remaining >= pad.length() {
      sb.write_string(pad)
      filled = filled + pad.length()
    } else {
      sb.write_string(pad[0:remaining].to_string() catch { _ => "" })
      filled = fill_len
    }
  }
  sb.to_string()
}

///|
pub fn string_repeat(s : String, count : Int) -> String {
  if count <= 0 {
    return ""
  }
  let sb = StringBuilder::new()
  for _ in 0..<count {
    sb.write_string(s)
  }
  sb.to_string()
}

///|
pub fn string_to_upper_case(s : String) -> String {
  let sb = StringBuilder::new()
  let len = s.length()
  for i in 0..<len {
    let code = s[i].to_int()
    if code >= 0x61 && code <= 0x7a {
      sb.write_char((code - 32).to_uint16().unsafe_to_char())
    } else {
      sb.write_char(s[i].unsafe_to_char())
    }
  }
  sb.to_string()
}

///|
pub fn string_to_lower_case(s : String) -> String {
  let sb = StringBuilder::new()
  let len = s.length()
  for i in 0..<len {
    let code = s[i].to_int()
    if code >= 0x41 && code <= 0x5a {
      sb.write_char((code + 32).to_uint16().unsafe_to_char())
    } else {
      sb.write_char(s[i].unsafe_to_char())
    }
  }
  sb.to_string()
}

///|
pub fn string_normalize_newlines(s : String) -> String {
  let sb = StringBuilder::new()
  let len = s.length()
  let mut i = 0
  while i < len {
    let code = s[i].to_int()
    if code == 0x0d {
      sb.write_char('\n')
      if i + 1 < len && s[i + 1].to_int() == 0x0a {
        i = i + 1
      }
    } else {
      sb.write_char(s[i].unsafe_to_char())
    }
    i = i + 1
  }
  sb.to_string()
}

///|
pub fn string_from_char_code(codes : Array[Int]) -> String {
  let sb = StringBuilder::new()
  for code in codes {
    let c = code.land(0xFFFF)
    sb.write_char(c.to_uint16().unsafe_to_char())
  }
  sb.to_string()
}

///|
pub fn string_from_code_point(codes : Array[Int]) -> String? {
  let sb = StringBuilder::new()
  for code in codes {
    if code < 0 || code > 0x10FFFF {
      return None
    }
    if code <= 0xFFFF {
      sb.write_char(code.to_uint16().unsafe_to_char())
    } else {
      let adjusted = code - 0x10000
      let hi = 0xD800 + (adjusted >> 10)
      let lo = 0xDC00 + (adjusted.land(0x3FF))
      sb.write_char(hi.to_uint16().unsafe_to_char())
      sb.write_char(lo.to_uint16().unsafe_to_char())
    }
  }
  Some(sb.to_string())
}
