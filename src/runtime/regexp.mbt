///|
/// RegExp helpers (minimal)

///|
fn is_regexp(value : JSValue) -> Bool {
  match value {
    Object(_) | Function(_) =>
      match js_get_prop(value, "__class") {
        String("RegExp") => true
        _ => false
      }
    _ => false
  }
}

///|
fn regexp_source(value : JSValue) -> String {
  match js_get_prop(value, "source") {
    String(s) => s
    _ => ""
  }
}

///|
fn regexp_flags(value : JSValue) -> String {
  match js_get_prop(value, "flags") {
    String(s) => normalize_regexp_flags(s)
    _ => ""
  }
}

///|
fn normalize_regexp_flags(flags : String) -> String {
  let mut out = ""
  if flags.contains("g") { out = out + "g" }
  if flags.contains("i") { out = out + "i" }
  if flags.contains("m") { out = out + "m" }
  if flags.contains("s") { out = out + "s" }
  if flags.contains("u") { out = out + "u" }
  if flags.contains("y") { out = out + "y" }
  out
}

///|
fn regexp_has_global(flags : String) -> Bool {
  flags.contains("g")
}

///|
fn sanitize_utf16(input : String) -> String {
  let len = input.length()
  let buf = StringBuilder::new(size_hint=len)
  let mut i = 0
  while i < len {
    let c1 = input.unsafe_get(i)
    if c1.is_leading_surrogate() {
      if i + 1 < len {
        let c2 = input.unsafe_get(i + 1)
        if c2.is_trailing_surrogate() {
          buf.write_char(c1.to_int().unsafe_to_char())
          buf.write_char(c2.to_int().unsafe_to_char())
          i += 2
          continue
        }
      }
      buf.write_char('\ufffd')
      i += 1
      continue
    }
    if c1.is_trailing_surrogate() {
      buf.write_char('\ufffd')
      i += 1
      continue
    }
    buf.write_char(c1.to_int().unsafe_to_char())
    i += 1
  }
  buf.to_string()
}

///|
fn regexp_compile(pattern : String, flags : String) -> @regexp.Regexp? {
  let safe_pattern = sanitize_utf16(pattern)
  try {
    Some(@regexp.compile(safe_pattern[:], flags=flags[:]))
  } catch {
    _ => None
  }
}

///|
fn regexp_exec_with_re(
  re : @regexp.Regexp,
  input : String,
  last_index : Int,
) -> (@regexp.MatchResult, Int, Int)? {
  let safe_input = sanitize_utf16(input)
  if last_index < 0 || last_index > safe_input.length() {
    return None
  }
  let view = if last_index == 0 {
    safe_input[:]
  } else {
    let tail =
      String::unsafe_substring(
        safe_input,
        start=last_index,
        end=safe_input.length(),
      )
    tail[:]
  }
  match re.match_(view) {
    None => None
    Some(result) =>
      match result.get(0) {
        None => None
        Some(matched) => {
          let start = last_index + result.before().length()
          let end = start + matched.length()
          Some((result, start, end))
        }
      }
  }
}

///|
fn regexp_first_match(
  pattern : String,
  flags : String,
  input : String,
  last_index : Int,
) -> (Int, Int)? {
  match regexp_compile(pattern, flags) {
    None => None
    Some(re) =>
      match regexp_exec_with_re(re, input, last_index) {
        None => None
        Some((_result, start, end)) => Some((start, end))
      }
  }
}

///|
fn regexp_exec_groups(
  pattern : String,
  flags : String,
  input : String,
  last_index : Int,
) -> (Int, Int, Array[JSValue])? {
  match regexp_compile(pattern, flags) {
    None => None
    Some(re) =>
      match regexp_exec_with_re(re, input, last_index) {
        None => None
        Some((result, start, end)) => {
          let groups : Array[JSValue] = []
          let items = result.results()
          for item in items {
            match item {
              None => groups.push(Undefined)
              Some(view) => groups.push(String(view.to_string()))
            }
          }
          Some((start, end, groups))
        }
      }
  }
}

///|
fn regexp_split_simple(
  pattern : String,
  flags : String,
  input : String,
  limit : Int,
) -> Array[JSValue] {
  let result : Array[JSValue] = []
  if limit == 0 {
    return result
  }
  if pattern.length() == 0 {
    if input.length() == 0 {
      result.push(String(""))
      return result
    }
    for i in 0..<input.length() {
      if limit >= 0 && result.length() >= limit {
        break
      }
      result.push(String(try { input[i:i + 1].to_string() } catch { _ => "" }))
    }
    return result
  }
  match regexp_compile(pattern, flags) {
    None => {
      result.push(String(input))
      result
    }
    Some(re) => {
      let mut last_index = 0
      while last_index <= input.length() {
        if limit >= 0 && result.length() >= limit {
          break
        }
        match regexp_exec_with_re(re, input, last_index) {
          None => {
            result.push(String(try { input[last_index:input.length()].to_string() } catch { _ => "" }))
            break
          }
          Some((_result, start, end)) => {
            result.push(String(try { input[last_index:start].to_string() } catch { _ => "" }))
            let next = if end == last_index { end + 1 } else { end }
            last_index = next
            if last_index > input.length() {
              if limit < 0 || result.length() < limit {
                result.push(String(""))
              }
              break
            }
          }
        }
      }
      result
    }
  }
}

///|
fn regexp_search_simple(pattern : String, flags : String, input : String) -> Int {
  match regexp_first_match(pattern, flags, input, 0) {
    Some((start, _)) => start
    None => -1
  }
}

///|
fn regexp_match_simple(
  pattern : String,
  flags : String,
  input : String,
  global : Bool,
) -> JSValue {
  let matches : Array[JSValue] = []
  match regexp_compile(pattern, flags) {
    None => Null
    Some(re) => {
      let mut last_index = 0
      if not(global) {
        match regexp_exec_with_re(re, input, 0) {
          None => return Null
          Some((_result, start, end)) => {
            matches.push(String(try { input[start:end].to_string() } catch { _ => "" }))
            return js_array_from(matches)
          }
        }
      }
      while last_index <= input.length() {
        match regexp_exec_with_re(re, input, last_index) {
          None => break
          Some((_result, start, end)) => {
            matches.push(String(try { input[start:end].to_string() } catch { _ => "" }))
            let next = if end == last_index { end + 1 } else { end }
            last_index = next
          }
        }
      }
      if matches.length() == 0 {
        Null
      } else {
        js_array_from(matches)
      }
    }
  }
}

///|
fn regexp_replace_simple(
  pattern : String,
  flags : String,
  input : String,
  replace_with : String,
  global : Bool,
) -> String {
  match regexp_compile(pattern, flags) {
    None => input
    Some(re) => {
      let mut out = ""
      let mut last_index = 0
      if not(global) {
        match regexp_exec_with_re(re, input, 0) {
          None => return input
          Some((_result, start, end)) => {
            out = out + (try { input[0:start].to_string() } catch { _ => "" })
            out = out + replace_with
            out = out + (try { input[end:input.length()].to_string() } catch { _ => "" })
            return out
          }
        }
      }
      while last_index <= input.length() {
        match regexp_exec_with_re(re, input, last_index) {
          None => {
            out = out + (try { input[last_index:input.length()].to_string() } catch { _ => "" })
            break
          }
          Some((_result, start, end)) => {
            out = out + (try { input[last_index:start].to_string() } catch { _ => "" })
            out = out + replace_with
            let next = if end == last_index { end + 1 } else { end }
            last_index = next
          }
        }
      }
      out
    }
  }
}
