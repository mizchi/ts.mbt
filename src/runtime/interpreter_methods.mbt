///|
// / method
pub fn JSInterpreter::call_method(
  self : JSInterpreter,
  obj : JSValue,
  method_name : String,
  args : Array[JSValue],
) -> JSValue {
  match obj {
    String(s) => self.string_method(s, method_name, args)
    Array(arr) => self.array_method(arr, method_name, args)
    Bool(_) | Number(_) => {
      let boxed = self.wrap_primitive(self.global_env, obj)
      let func = self.get_prop_value(boxed, method_name)
      self.call_function(func, boxed, args)
    }
    Function(_) =>
      match method_name {
        "call" | "apply" | "bind" => self.function_method(obj, method_name, args)
        _ => {
          let func = self.get_prop_value(obj, method_name)
          self.call_function(func, obj, args)
        }
      }
    Object(map) => {
      // objectmethodlookup
      let func = self.get_prop_value(Object(map), method_name)
      self.call_function(func, obj, args)
    }
    _ => Undefined
  }
}

///|
fn escape_html_attr(value : String) -> String {
  let sb = StringBuilder::new()
  for ch in value {
    match ch {
      '\"' => sb.write_string("&quot;")
      _ => sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
fn JSInterpreter::compare_sort_items(
  self : JSInterpreter,
  a : (JSValue, Int),
  b : (JSValue, Int),
  compare_fn : JSValue,
  use_compare : Bool,
) -> Int {
  let (av, ai) = a
  let (bv, bi) = b
  let order =
    match (av, bv) {
      (Undefined, Undefined) => 0
      (Undefined, _) => 1
      (_, Undefined) => -1
      _ =>
        if use_compare {
          let res = self.call_function(compare_fn, Undefined, [av, bv])
          let n = res.to_number()
          if n.is_nan() {
            0
          } else if n < 0.0 {
            -1
          } else if n > 0.0 {
            1
          } else {
            0
          }
        } else {
          let a_str = av.to_js_string()
          let b_str = bv.to_js_string()
          a_str.compare(b_str)
        }
    }
  if order == 0 {
    if ai < bi {
      -1
    } else if ai > bi {
      1
    } else {
      0
    }
  } else {
    order
  }
}

///|
fn JSInterpreter::quicksort_values(
  self : JSInterpreter,
  values : Array[(JSValue, Int)],
  lo : Int,
  hi : Int,
  compare_fn : JSValue,
  use_compare : Bool,
) -> Unit {
  if lo >= hi {
    return
  }
  let pivot = values[(lo + hi) / 2]
  let mut i = lo
  let mut j = hi
  while i <= j {
    while i <= hi &&
      self.compare_sort_items(values[i], pivot, compare_fn, use_compare) < 0 {
      i += 1
    }
    while j >= lo &&
      self.compare_sort_items(values[j], pivot, compare_fn, use_compare) > 0 {
      j -= 1
    }
    if i <= j {
      let tmp = values[i]
      values[i] = values[j]
      values[j] = tmp
      i += 1
      j -= 1
    }
  }
  if lo < j {
    self.quicksort_values(values, lo, j, compare_fn, use_compare)
  }
  if i < hi {
    self.quicksort_values(values, i, hi, compare_fn, use_compare)
  }
}

///|
// / functionmethod (call/apply/bind)
fn JSInterpreter::function_method(
  self : JSInterpreter,
  func : JSValue,
  method_name : String,
  args : Array[JSValue],
) -> JSValue {
  match method_name {
    "call" => {
      let this_arg = if args.length() > 0 { args[0] } else { Undefined }
      let call_args : Array[JSValue] = []
      for i in 1..<args.length() {
        call_args.push(args[i])
      }
      self.call_function(func, this_arg, call_args)
    }
    "apply" => {
      let this_arg = if args.length() > 0 { args[0] } else { Undefined }
      let call_args : Array[JSValue] = []
      if args.length() > 1 {
        match args[1] {
          Array(arr) => {
            for item in arr.items {
              call_args.push(item)
            }
          }
          _ => ()
        }
      }
      self.call_function(func, this_arg, call_args)
    }
    "bind" => {
      let this_arg = if args.length() > 0 { args[0] } else { Undefined }
      let bound_args : Array[JSValue] = []
      for i in 1..<args.length() {
        bound_args.push(args[i])
      }
      let bound = JSValue::Function({
        id: fresh_function_id(),
        params: [],
        body: Bound(func, this_arg, bound_args),
        env: self.global_env,
        is_arrow: false,
        is_strict: false,
        is_generator: false,
        props: [],
        object_proto: Some(self.function_proto),
      })
      let len = self.calc_bound_length(func, bound_args.length())
      self.set_function_length(bound, len)
      let target_name_val = self.get_prop_value(func, "name")
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      let target_name = match target_name_val {
        String(s) => s
        _ => ""
      }
      self.set_function_name(bound, "bound " + target_name)
      bound
    }
    _ => Undefined
  }
}

///|
// / stringmethod
fn JSInterpreter::string_method(
  self : JSInterpreter,
  s : String,
  method_name : String,
  args : Array[JSValue],
) -> JSValue {
  match method_name {
    "length" => Number(s.length().to_double())
    "valueOf" => String(s)
    "toString" => String(s)
    "charAt" => {
      let idx = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      if idx >= 0 && idx < s.length() {
        String(try { s[idx:idx + 1].to_string() } catch { _ => "" })
      } else {
        String("")
      }
    }
    "charCodeAt" => {
      let idx = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      if idx >= 0 && idx < s.length() {
        Number(s[idx].to_int().to_double())
      } else {
        Number(0.0 / 0.0)
      }
    }
    "codePointAt" => {
      let idx = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      if idx < 0 || idx >= s.length() {
        Undefined
      } else {
        let cu1 = s[idx]
        if cu1.is_leading_surrogate() && idx + 1 < s.length() {
          let cu2 = s[idx + 1]
          if cu2.is_trailing_surrogate() {
            let hi = cu1.to_int() - 0xd800
            let lo = cu2.to_int() - 0xdc00
            let code = hi * 0x400 + lo + 0x10000
            Number(code.to_double())
          } else {
            Number(cu1.to_int().to_double())
          }
        } else {
          Number(cu1.to_int().to_double())
        }
      }
    }
    "indexOf" => {
      let search_str = if args.length() > 0 {
        self.to_string_value(args[0])
      } else {
        ""
      }
      let mut start_idx = if args.length() > 1 {
        self.to_number_value(args[1]).to_int()
      } else {
        0
      }
      if start_idx < 0 {
        start_idx = 0
      }
      if search_str.length() == 0 {
        return Number(start_idx.to_double())
      }
      let search_len = search_str.length()
      let mut idx = -1
      if start_idx < s.length() && start_idx + search_len <= s.length() {
        let end_idx = s.length() - search_len + 1
        let mut i = start_idx
        while i < end_idx && idx == -1 {
          if (try { s[i:i + search_len].to_string() } catch { _ => "" }) == search_str {
            idx = i
          }
          i = i + 1
        }
      }
      Number(idx.to_double())
    }
    "lastIndexOf" => {
      let search_str = if args.length() > 0 {
        self.to_string_value(args[0])
      } else {
        ""
      }
      let mut pos = if args.length() > 1 {
        self.to_number_value(args[1]).to_int()
      } else {
        s.length()
      }
      if pos > s.length() {
        pos = s.length()
      }
      if pos < 0 {
        pos = 0
      }
      if search_str.length() == 0 {
        return Number(pos.to_double())
      }
      let search_len = search_str.length()
      let mut idx = -1
      let mut i = pos - search_len
      if i < 0 {
        i = 0
      }
      while i >= 0 {
        if (try { s[i:i + search_len].to_string() } catch { _ => "" }) == search_str {
          idx = i
          break
        }
        if i == 0 {
          break
        }
        i = i - 1
      }
      Number(idx.to_double())
    }
    "includes" => {
      if args.length() > 0 && is_regexp(args[0]) {
        return self.set_error_kind("TypeError", "String.prototype.includes does not accept a RegExp")
      }
      let search_str = if args.length() > 0 {
        self.to_string_value(args[0])
      } else {
        ""
      }
      let mut start_idx = if args.length() > 1 {
        self.to_number_value(args[1]).to_int()
      } else {
        0
      }
      if start_idx < 0 {
        start_idx = 0
      }
      if search_str.length() == 0 {
        Bool(true)
      } else if start_idx + search_str.length() > s.length() {
        Bool(false)
      } else {
        let search_len = search_str.length()
        let end_idx = s.length() - search_len + 1
        let mut i = start_idx
        let mut found = false
        while i < end_idx && not(found) {
          if (try { s[i:i + search_len].to_string() } catch { _ => "" }) == search_str {
            found = true
          }
          i = i + 1
        }
        Bool(found)
      }
    }
    "startsWith" => {
      if args.length() > 0 && is_regexp(args[0]) {
        return self.set_error_kind("TypeError", "String.prototype.startsWith does not accept a RegExp")
      }
      let search_str = if args.length() > 0 {
        self.to_string_value(args[0])
      } else {
        ""
      }
      let mut pos = if args.length() > 1 {
        self.to_number_value(args[1]).to_int()
      } else {
        0
      }
      if pos < 0 {
        pos = 0
      }
      let search_len = search_str.length()
      if search_len == 0 {
        Bool(true)
      } else if pos + search_len > s.length() {
        Bool(false)
      } else {
        Bool(
          (try { s[pos:pos + search_len].to_string() } catch { _ => "" }) == search_str,
        )
      }
    }
    "endsWith" => {
      if args.length() > 0 && is_regexp(args[0]) {
        return self.set_error_kind("TypeError", "String.prototype.endsWith does not accept a RegExp")
      }
      let search_str = if args.length() > 0 {
        self.to_string_value(args[0])
      } else {
        ""
      }
      let mut end_pos = if args.length() > 1 {
        self.to_number_value(args[1]).to_int()
      } else {
        s.length()
      }
      if end_pos > s.length() {
        end_pos = s.length()
      }
      if end_pos < 0 {
        end_pos = 0
      }
      let search_len = search_str.length()
      if search_len == 0 {
        Bool(true)
      } else if search_len > end_pos {
        Bool(false)
      } else {
        let start = end_pos - search_len
        Bool(
          (try { s[start:end_pos].to_string() } catch { _ => "" }) == search_str,
        )
      }
    }
    "at" => {
      let mut idx = if args.length() > 0 {
        self.to_number_value(args[0]).to_int()
      } else {
        0
      }
      if idx < 0 {
        idx = s.length() + idx
      }
      if idx < 0 || idx >= s.length() {
        Undefined
      } else {
        String(try { s[idx:idx + 1].to_string() } catch { _ => "" })
      }
    }
    "split" => {
      let sep_val = if args.length() > 0 { args[0] } else { Undefined }
      let mut sep_string : String? = None
      if not(is_regexp(sep_val)) {
        match sep_val {
          Undefined => ()
          _ => sep_string = Some(self.to_string_value(sep_val))
        }
      }
      let limit = if args.length() > 1 {
        let n = self.to_number_value(args[1])
        if n.is_nan() || n <= 0.0 {
          0
        } else {
          let two32 = 4294967296.0
          let mut m = n % two32
          if m < 0.0 {
            m = m + two32
          }
          let lim = m.floor()
          if lim > 2147483647.0 {
            2147483647
          } else {
            lim.to_int()
          }
        }
      } else {
        -1
      }
      if limit == 0 {
        return js_new_array()
      }
      if is_regexp(sep_val) {
        let pattern = regexp_source(sep_val)
        let flags = regexp_flags(sep_val)
        let result = regexp_split_simple(pattern, flags, s, limit)
        return js_array_from(result)
      }
      match sep_val {
        Undefined => {
          return js_array_from([String(s)])
        }
        _ => ()
      }
      let sep = match sep_string {
        Some(value) => value
        None => ""
      }
      let result : Array[JSValue] = []
      if sep.length() == 0 {
        if s.length() == 0 {
          return js_new_array()
        } else {
          for i in 0..<s.length() {
            if limit >= 0 && result.length() >= limit {
              break
            }
            result.push(String(try { s[i:i + 1].to_string() } catch { _ => "" }))
          }
        }
        return js_array_from(result)
      }
      let mut start = 0
      let sep_len = sep.length()
      while start <= s.length() {
        if limit >= 0 && result.length() >= limit {
          break
        }
        let mut found = false
        let mut pos = start
        if start + sep_len <= s.length() {
          let end_idx = s.length() - sep_len + 1
          while pos < end_idx && not(found) {
            if (try { s[pos:pos + sep_len].to_string() } catch { _ => "" }) == sep {
              found = true
            } else {
              pos = pos + 1
            }
          }
        }
        if found {
          result.push(String(try { s[start:pos].to_string() } catch { _ => "" }))
          start = pos + sep_len
        } else {
          result.push(String(try { s[start:s.length()].to_string() } catch { _ => "" }))
          break
        }
      }
      js_array_from(result)
    }
    "replace" => {
      if args.length() > 0 && is_regexp(args[0]) {
        let pattern = regexp_source(args[0])
        let flags = regexp_flags(args[0])
        let to = if args.length() > 1 { args[1].to_js_string() } else { "" }
        String(regexp_replace_simple(
          pattern,
          flags,
          s,
          to,
          regexp_has_global(flags),
        ))
      } else {
        let from = if args.length() > 0 { args[0].to_js_string() } else { "" }
        let to = if args.length() > 1 { args[1].to_js_string() } else { "" }
        String(s.replace(old=from, new=to))
      }
    }
    "replaceAll" => {
      let from = if args.length() > 0 { args[0].to_js_string() } else { "" }
      let to = if args.length() > 1 { args[1].to_js_string() } else { "" }
      String(s.replace_all(old=from, new=to))
    }
    "match" => {
      let pat = if args.length() > 0 { args[0] } else { Undefined }
      if is_regexp(pat) {
        let pattern = regexp_source(pat)
        let flags = regexp_flags(pat)
        regexp_match_simple(pattern, flags, s, regexp_has_global(flags))
      } else {
        let pattern = pat.to_js_string()
        regexp_match_simple(pattern, "", s, false)
      }
    }
    "search" => {
      let pat = if args.length() > 0 { args[0] } else { Undefined }
      if is_regexp(pat) {
        let pattern = regexp_source(pat)
        let flags = regexp_flags(pat)
        Number(regexp_search_simple(pattern, flags, s).to_double())
      } else {
        let pattern = pat.to_js_string()
        Number(regexp_search_simple(pattern, "", s).to_double())
      }
    }
    "trim" => String(trim_js_string(s, "both"))
    "trimStart" => String(trim_js_string(s, "start"))
    "trimEnd" => String(trim_js_string(s, "end"))
    "slice" => {
      let len = s.length()
      let start_num = if args.length() > 0 {
        self.to_number_value(args[0])
      } else {
        0.0
      }
      match self.peek_error() {
        Some(_) => return self.error_or_undefined()
        None => ()
      }
      let mut start =
        if start_num.is_nan() {
          0
        } else if start_num.is_inf() {
          if start_num < 0.0 { 0 } else { len }
        } else {
          start_num.to_int()
        }
      let end_num = if args.length() > 1 {
        self.to_number_value(args[1])
      } else {
        len.to_double()
      }
      let mut end = if end_num.is_nan() { 0 } else { end_num.to_int() }
      if start < 0 {
        start = len + start
      }
      if end < 0 {
        end = len + end
      }
      if start < 0 {
        start = 0
      }
      if end < 0 {
        end = 0
      }
      if start > len {
        start = len
      }
      if end > len {
        end = len
      }
      if end < start {
        end = start
      }
      String(try { s[start:end].to_string() } catch { _ => "" })
    }
    "substr" => {
      let len = s.length()
      let start_num = if args.length() > 0 {
        self.to_number_value(args[0])
      } else {
        0.0
      }
      let mut start = if start_num.is_nan() { 0 } else { start_num.to_int() }
      if start < 0 {
        start = len + start
      }
      if start < 0 {
        start = 0
      }
      if start > len {
        start = len
      }
      let length_num = if args.length() > 1 {
        match args[1] {
          Undefined => (len - start).to_double()
          _ => self.to_number_value(args[1])
        }
      } else {
        (len - start).to_double()
      }
      match self.peek_error() {
        Some(_) => return self.error_or_undefined()
        None => ()
      }
      let mut count =
        if length_num.is_nan() {
          0
        } else if length_num.is_inf() {
          if length_num < 0.0 { 0 } else { len }
        } else {
          length_num.to_int()
        }
      if count < 0 {
        count = 0
      }
      let mut end = start + count
      if end > len {
        end = len
      }
      String(try { s[start:end].to_string() } catch { _ => "" })
    }
    "substring" => {
      let mut start = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      let mut end = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        s.length()
      }
      if start < 0 {
        start = 0
      }
      if end < 0 {
        end = 0
      }
      if start > end {
        let tmp = start
        start = end
        end = tmp
      }
      if start > s.length() {
        start = s.length()
      }
      if end > s.length() {
        end = s.length()
      }
      String(try { s[start:end].to_string() } catch { _ => "" })
    }
    "toUpperCase" => String(s.to_upper())
    "toLowerCase" => String(s.to_lower())
    "toLocaleUpperCase" => String(s.to_upper())
    "toLocaleLowerCase" => String(s.to_lower())
    "big" => String("<big>" + s + "</big>")
    "small" => String("<small>" + s + "</small>")
    "bold" => String("<b>" + s + "</b>")
    "italics" => String("<i>" + s + "</i>")
    "strike" => String("<strike>" + s + "</strike>")
    "sub" => String("<sub>" + s + "</sub>")
    "sup" => String("<sup>" + s + "</sup>")
    "fixed" => String("<tt>" + s + "</tt>")
    "blink" => String("<blink>" + s + "</blink>")
    "fontcolor" => {
      let color =
        if args.length() > 0 { escape_html_attr(self.to_string_value(args[0])) } else { "" }
      String("<font color=\"" + color + "\">" + s + "</font>")
    }
    "fontsize" => {
      let size =
        if args.length() > 0 { escape_html_attr(self.to_string_value(args[0])) } else { "" }
      String("<font size=\"" + size + "\">" + s + "</font>")
    }
    "link" => {
      let url =
        if args.length() > 0 { escape_html_attr(self.to_string_value(args[0])) } else { "" }
      String("<a href=\"" + url + "\">" + s + "</a>")
    }
    "repeat" => {
      let count = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      if count <= 0 {
        String("")
      } else {
        let mut out = ""
        for _ in 0..<count {
          out = out + s
        }
        String(out)
      }
    }
    "padStart" => {
      let target_len = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      let pad = if args.length() > 1 { args[1].to_js_string() } else { " " }
      if target_len <= s.length() {
        String(s)
      } else {
        let needed = target_len - s.length()
        let mut pad_str = ""
        if pad.length() == 0 {
          pad_str = ""
        } else {
          while pad_str.length() < needed {
            pad_str = pad_str + pad
          }
          if pad_str.length() > needed {
            pad_str = (try { pad_str[:needed].to_string() } catch { _ => pad_str })
          }
        }
        String(pad_str + s)
      }
    }
    "padEnd" => {
      let target_len = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      let pad = if args.length() > 1 { args[1].to_js_string() } else { " " }
      if target_len <= s.length() {
        String(s)
      } else {
        let needed = target_len - s.length()
        let mut pad_str = ""
        if pad.length() == 0 {
          pad_str = ""
        } else {
          while pad_str.length() < needed {
            pad_str = pad_str + pad
          }
          if pad_str.length() > needed {
            pad_str = (try { pad_str[:needed].to_string() } catch { _ => pad_str })
          }
        }
        String(s + pad_str)
      }
    }
    "concat" => {
      let mut result = s
      for arg in args {
        result = result + arg.to_js_string()
      }
      String(result)
    }
    _ => Undefined
  }
}

///|
// / JS trim check
fn is_js_trim_whitespace(unit : UInt16) -> Bool {
  let code = unit.to_int()
  if code == 0x0009 { return true }
  if code == 0x000a { return true }
  if code == 0x000b { return true }
  if code == 0x000c { return true }
  if code == 0x000d { return true }
  if code == 0x0020 { return true }
  if code == 0x00a0 { return true }
  if code == 0x1680 { return true }
  if code >= 0x2000 && code <= 0x200a { return true }
  if code == 0x2028 { return true }
  if code == 0x2029 { return true }
  if code == 0x202f { return true }
  if code == 0x205f { return true }
  if code == 0x3000 { return true }
  if code == 0xfeff { return true }
  false
}

///|
// / JS trim implementation
fn trim_js_string(s : String, mode : String) -> String {
  let len = s.length()
  let mut start = 0
  let mut end = len
  if mode == "both" || mode == "start" {
    while start < end && is_js_trim_whitespace(s[start]) {
      start = start + 1
    }
  }
  if mode == "both" || mode == "end" {
    while end > start && is_js_trim_whitespace(s[end - 1]) {
      end = end - 1
    }
  }
  try { s[start:end].to_string() } catch { _ => "" }
}

///|
// / SameValue check
fn JSInterpreter::same_value(
  _self : JSInterpreter,
  left : JSValue,
  right : JSValue,
) -> Bool {
  match (left, right) {
    (Number(l), Number(r)) => {
      if l.is_nan() && r.is_nan() {
        true
      } else if l == 0.0 && r == 0.0 {
        (1.0 / l) == (1.0 / r)
      } else {
        l == r
      }
    }
    _ =>
      match js_strict_eq(left, right) {
        Bool(true) => true
        _ => false
      }
  }
}

///|
// / SameValueZero check
fn JSInterpreter::same_value_zero(
  _self : JSInterpreter,
  left : JSValue,
  right : JSValue,
) -> Bool {
  match js_strict_eq(left, right) {
    Bool(true) => true
    _ => {
      let left_nan = match left {
        Number(n) => n.is_nan()
        _ => false
      }
      let right_nan = match right {
        Number(n) => n.is_nan()
        _ => false
      }
      left_nan && right_nan
    }
  }
}

///|
// / array
fn JSInterpreter::flatten_array_items(
  self : JSInterpreter,
  items : Array[JSValue],
  depth : Int,
  out : Array[JSValue],
) -> Unit {
  if depth <= 0 {
    for item in items {
      out.push(item)
    }
  } else {
    for item in items {
      match item {
        Array(arr) => self.flatten_array_items(arr.items, depth - 1, out)
        _ => out.push(item)
      }
    }
  }
}

///|
// / arraymethod
fn JSInterpreter::array_method(
  self : JSInterpreter,
  arr : JSArray,
  method_name : String,
  args : Array[JSValue],
) -> JSValue {
  let len = arr.length
  let arr_val = JSValue::Array(arr)
  match method_name {
    "length" => JSValue::Number(arr.length.to_double())
    "push" => {
      for arg in args {
        arr.items.push(arg)
        arr.present.push(true)
      }
      arr.length = arr.items.length()
      JSValue::Number(arr.length.to_double())
    }
    "pop" =>
      if arr.items.length() > 0 {
        let last_idx = arr.items.length() - 1
        let result =
          if arr.present[last_idx] {
            arr.items[last_idx]
          } else {
            Undefined
          }
        let _ = arr.items.pop()
        let _ = arr.present.pop()
        arr.length = arr.items.length()
        result
      } else {
        Undefined
      }
    "shift" =>
      if arr.items.length() > 0 {
        let first =
          if arr.present[0] {
            arr.items[0]
          } else {
            Undefined
          }
        let new_arr : Array[JSValue] = []
        let new_present : Array[Bool] = []
        for i in 1..<arr.items.length() {
          new_arr.push(arr.items[i])
          new_present.push(arr.present[i])
        }
        arr.items.clear()
        arr.present.clear()
        for item in new_arr {
          arr.items.push(item)
        }
        for item in new_present {
          arr.present.push(item)
        }
        arr.length = arr.items.length()
        first
      } else {
        Undefined
      }
    "unshift" => {
      let new_arr : Array[JSValue] = []
      let new_present : Array[Bool] = []
      for arg in args {
        new_arr.push(arg)
        new_present.push(true)
      }
      for i, item in arr.items {
        new_arr.push(item)
        new_present.push(arr.present[i])
      }
      arr.items.clear()
      arr.present.clear()
      for item in new_arr {
        arr.items.push(item)
      }
      for item in new_present {
        arr.present.push(item)
      }
      arr.length = arr.items.length()
      JSValue::Number(arr.length.to_double())
    }
    "join" => {
      let sep = if args.length() > 0 { args[0].to_js_string() } else { "," }
      let parts : Array[String] = []
      for i in 0..<len {
        let key = i.to_string()
        if js_has_prop(arr_val, key) {
          let value = js_get_prop(arr_val, key)
          parts.push(value.to_js_string())
        } else {
          parts.push("")
        }
      }
      JSValue::String(parts.join(sep))
    }
    "toString" => {
      let parts : Array[String] = []
      for i in 0..<len {
        let key = i.to_string()
        if js_has_prop(arr_val, key) {
          let value = js_get_prop(arr_val, key)
          parts.push(value.to_js_string())
        } else {
          parts.push("")
        }
      }
      JSValue::String(parts.join(","))
    }
    "values" => self.new_array_iterator(arr_val)
    "indexOf" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let mut start_idx = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
      if start_idx < 0 {
        start_idx = len + start_idx
        if start_idx < 0 {
          start_idx = 0
        }
      }
      if start_idx >= len {
        return JSValue::Number(-1.0)
      }
      for i in start_idx..<len {
        let key = i.to_string()
        if not(js_has_prop(arr_val, key)) {
          continue
        }
        let value = self.get_prop_value(arr_val, key)
        match js_strict_eq(value, target) {
          JSValue::Bool(true) => return JSValue::Number(i.to_double())
          _ => ()
        }
      }
      JSValue::Number(-1.0)
    }
    "lastIndexOf" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let mut from_idx = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        len - 1
      }
      if from_idx < 0 {
        from_idx = len + from_idx
      }
      if from_idx >= len {
        from_idx = len - 1
      }
      if from_idx < 0 {
        return JSValue::Number(-1.0)
      }
      let mut i = from_idx
      while i >= 0 {
        let key = i.to_string()
        if js_has_prop(arr_val, key) {
          let value = self.get_prop_value(arr_val, key)
          match js_strict_eq(value, target) {
            JSValue::Bool(true) => return JSValue::Number(i.to_double())
            _ => ()
          }
        }
        if i == 0 {
          break
        }
        i = i - 1
      }
      JSValue::Number(-1.0)
    }
    "includes" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let mut start_idx = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
      if start_idx < 0 {
        start_idx = len + start_idx
        if start_idx < 0 {
          start_idx = 0
        }
      }
      for i in start_idx..<len {
        let value = self.get_prop_value(arr_val, i.to_string())
        if self.same_value_zero(value, target) {
          return Bool(true)
        }
      }
      Bool(false)
    }
    "map" =>
      if args.length() == 0 {
        self.set_error_kind("TypeError", "Array.prototype.map requires a callback")
      } else {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError",
            "Array.prototype.map requires a callback",
          )
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let map_len = arr.length
        let out = js_new_array()
        match out {
          Array(out_arr) => {
            let mut i = 0
            while i < map_len {
              let key = i.to_string()
              if js_has_prop(arr_val, key) {
                let value = self.get_prop_value(arr_val, key)
                let args_array = [
                  value,
                  JSValue::Number(i.to_double()),
                  arr_val,
                ]
                let mapped = self.call_function(callback, this_arg, args_array)
                out_arr.items.push(mapped)
                out_arr.present.push(true)
              } else {
                out_arr.items.push(Undefined)
                out_arr.present.push(false)
              }
              i += 1
            }
            out_arr.length = map_len
          }
          _ => ()
        }
        out
      }
    "filter" =>
      if args.length() == 0 {
        self.set_error_kind("TypeError", "Array.prototype.filter requires a callback")
      } else {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError",
            "Array.prototype.filter requires a callback",
          )
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let result : Array[JSValue] = []
        let mut i = 0
        while i < len {
          let key = i.to_string()
          if js_has_prop(arr_val, key) {
            let item = self.get_prop_value(arr_val, key)
            let args_array = [
              item,
              JSValue::Number(i.to_double()),
              arr_val,
            ]
            let filtered = self.call_function(
              callback,
              this_arg,
              args_array,
            )
            if filtered.to_boolean() {
              result.push(item)
            }
          }
          i += 1
        }
        js_array_from(result)
      }
    "reduce" =>
      if args.length() == 0 {
        self.set_error_kind("TypeError", "Array.prototype.reduce requires a callback")
      } else {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError",
            "Array.prototype.reduce requires a callback",
          )
        }
        let has_init = args.length() > 1
        let mut accumulator = JSValue::Undefined
        let mut i = 0
        if has_init {
          accumulator = args[1]
        } else {
          let mut found = false
          while i < len {
            let key = i.to_string()
            if js_has_prop(arr_val, key) {
              accumulator = self.get_prop_value(arr_val, key)
              found = true
              i += 1
              break
            }
            i += 1
          }
          if not(found) {
            return self.set_error_kind(
              "TypeError",
              "Reduce of empty array with no initial value",
            )
          }
        }
        while i < len {
          let key = i.to_string()
          if js_has_prop(arr_val, key) {
            let value = self.get_prop_value(arr_val, key)
            let args_array = [
              accumulator,
              value,
              JSValue::Number(i.to_double()),
              arr_val,
            ]
            accumulator = self.call_function(
              callback,
              Undefined,
              args_array,
            )
          }
          i += 1
        }
        accumulator
      }
    "reduceRight" =>
      if args.length() == 0 {
        self.set_error_kind("TypeError", "Array.prototype.reduceRight requires a callback")
      } else {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError",
            "Array.prototype.reduceRight requires a callback",
          )
        }
        let has_init = args.length() > 1
        let mut accumulator = JSValue::Undefined
        let mut i = if len > 0 { len - 1 } else { -1 }
        if has_init {
          accumulator = args[1]
        } else {
          let mut found = false
          while i >= 0 {
            let key = i.to_string()
            if js_has_prop(arr_val, key) {
              accumulator = self.get_prop_value(arr_val, key)
              found = true
              i = i - 1
              break
            }
            if i == 0 {
              break
            }
            i = i - 1
          }
          if not(found) {
            return self.set_error_kind(
              "TypeError",
              "Reduce of empty array with no initial value",
            )
          }
        }
        while i >= 0 {
          let key = i.to_string()
          if js_has_prop(arr_val, key) {
            let value = self.get_prop_value(arr_val, key)
            let args_array = [
              accumulator,
              value,
              JSValue::Number(i.to_double()),
              arr_val,
            ]
            accumulator = self.call_function(
              callback,
              Undefined,
              args_array,
            )
          }
          if i == 0 {
            break
          }
          i = i - 1
        }
        accumulator
      }
    "forEach" =>
      if args.length() == 0 {
        self.set_error_kind("TypeError", "Array.prototype.forEach requires a callback")
      } else {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError",
            "Array.prototype.forEach requires a callback",
          )
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let mut i = 0
        while i < len {
          let key = i.to_string()
          if js_has_prop(arr_val, key) {
            let value = self.get_prop_value(arr_val, key)
            let args_array = [
              value,
              JSValue::Number(i.to_double()),
              arr_val,
            ]
            let _ = self.call_function(
              callback,
              this_arg,
              args_array,
            )
          }
          i += 1
        }
        Undefined
      }
    "every" =>
      if args.length() == 0 {
        self.set_error_kind("TypeError", "Array.prototype.every requires a callback")
      } else {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError",
            "Array.prototype.every requires a callback",
          )
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let mut i = 0
        while i < len {
          let key = i.to_string()
          if js_has_prop(arr_val, key) {
            let value = self.get_prop_value(arr_val, key)
            let args_array = [
              value,
              JSValue::Number(i.to_double()),
              arr_val,
            ]
            let ok = self.call_function(
              callback,
              this_arg,
              args_array,
            )
            if not(ok.to_boolean()) {
              return Bool(false)
            }
          }
          i += 1
        }
        Bool(true)
      }
    "some" =>
      if args.length() == 0 {
        self.set_error_kind("TypeError", "Array.prototype.some requires a callback")
      } else {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError",
            "Array.prototype.some requires a callback",
          )
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let mut i = 0
        while i < len {
          let key = i.to_string()
          if js_has_prop(arr_val, key) {
            let value = self.get_prop_value(arr_val, key)
            let args_array = [
              value,
              JSValue::Number(i.to_double()),
              arr_val,
            ]
            let ok = self.call_function(
              callback,
              this_arg,
              args_array,
            )
            if ok.to_boolean() {
              return Bool(true)
            }
          }
          i += 1
        }
        Bool(false)
      }
    "find" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let mut i = 0
            while i < len {
              let key = i.to_string()
              if js_has_prop(arr_val, key) {
                let item = js_get_prop(arr_val, key)
                let args_array = [
                  item,
                  JSValue::Number(i.to_double()),
                  arr_val,
                ]
                let found = self.call_function(
                  JSValue::Function(closure),
                  this_arg,
                  args_array,
                )
                match found {
                  Bool(true) => return item
                  _ => ()
                }
              }
              i += 1
            }
            Undefined
          }
          _ => Undefined
        }
      } else {
        Undefined
      }
    "findIndex" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let mut i = 0
            while i < len {
              let key = i.to_string()
              if js_has_prop(arr_val, key) {
                let item = js_get_prop(arr_val, key)
                let args_array = [
                  item,
                  JSValue::Number(i.to_double()),
                  arr_val,
                ]
                let found = self.call_function(
                  JSValue::Function(closure),
                  this_arg,
                  args_array,
                )
                match found {
                  Bool(true) => return Number(i.to_double())
                  _ => ()
                }
              }
              i += 1
            }
            Number(-1.0)
          }
          _ => Number(-1.0)
        }
      } else {
        Number(-1.0)
      }
    "findLast" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let mut i = len - 1
            while i >= 0 {
              let key = i.to_string()
              if js_has_prop(arr_val, key) {
                let item = js_get_prop(arr_val, key)
                let args_array = [
                  item,
                  JSValue::Number(i.to_double()),
                  arr_val,
                ]
                let found = self.call_function(
                  JSValue::Function(closure),
                  this_arg,
                  args_array,
                )
                match found {
                  Bool(true) => return item
                  _ => ()
                }
              }
              if i == 0 {
                break
              }
              i = i - 1
            }
            Undefined
          }
          _ => Undefined
        }
      } else {
        Undefined
      }
    "findLastIndex" =>
      if args.length() > 0 {
        match args[0] {
          JSValue::Function(closure) => {
            let this_arg = if args.length() > 1 { args[1] } else { Undefined }
            let mut i = len - 1
            while i >= 0 {
              let key = i.to_string()
              if js_has_prop(arr_val, key) {
                let item = js_get_prop(arr_val, key)
                let args_array = [
                  item,
                  JSValue::Number(i.to_double()),
                  arr_val,
                ]
                let found = self.call_function(
                  JSValue::Function(closure),
                  this_arg,
                  args_array,
                )
                match found {
                  Bool(true) => return Number(i.to_double())
                  _ => ()
                }
              }
              if i == 0 {
                break
              }
              i = i - 1
            }
            Number(-1.0)
          }
          _ => Number(-1.0)
        }
      } else {
        Number(-1.0)
      }
    "slice" => {
      let mut start = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      let mut end = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        len
      }
      if start < 0 {
        start = len + start
        if start < 0 {
          start = 0
        }
      }
      if end < 0 {
        end = len + end
        if end < 0 {
          end = 0
        }
      }
      if start > len {
        start = len
      }
      if end > len {
        end = len
      }
      if end < start {
        end = start
      }
      let out = js_new_array()
      match out {
        Array(out_arr) => {
          for i in start..<end {
            let key = i.to_string()
            if js_has_prop(arr_val, key) {
              let value = js_get_prop(arr_val, key)
              out_arr.items.push(value)
              out_arr.present.push(true)
            } else {
              out_arr.items.push(Undefined)
              out_arr.present.push(false)
            }
          }
          out_arr.length = end - start
        }
        _ => ()
      }
      out
    }
    "concat" => {
      let result : Array[JSValue] = []
      let present : Array[Bool] = []
      for i, item in arr.items {
        result.push(item)
        present.push(arr.present[i])
      }
      for arg in args {
        match arg {
          Array(other_arr) =>
            for i, item in other_arr.items {
              result.push(item)
              present.push(other_arr.present[i])
            }
          _ => {
            result.push(arg)
            present.push(true)
          }
        }
      }
      let out = js_new_array()
      match out {
        Array(out_arr) => {
          for item in result {
            out_arr.items.push(item)
          }
          for flag in present {
            out_arr.present.push(flag)
          }
          out_arr.length = out_arr.items.length()
        }
        _ => ()
      }
      out
    }
    "splice" => {
      let mut start = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      if start < 0 {
        start = len + start
        if start < 0 {
          start = 0
        }
      }
      if start > len {
        start = len
      }
      let mut delete_count = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        len - start
      }
      if delete_count < 0 {
        delete_count = 0
      }
      if delete_count > len - start {
        delete_count = len - start
      }
      let removed = js_new_array()
      match removed {
        Array(removed_arr) => {
          for i in 0..<delete_count {
            let idx = start + i
            let key = idx.to_string()
            if js_has_prop(arr_val, key) {
              let value = js_get_prop(arr_val, key)
              removed_arr.items.push(value)
              removed_arr.present.push(true)
            } else {
              removed_arr.items.push(Undefined)
              removed_arr.present.push(false)
            }
          }
          removed_arr.length = delete_count
        }
        _ => ()
      }
      let insert_items : Array[JSValue] = []
      if args.length() > 2 {
        for i in 2..<args.length() {
          insert_items.push(args[i])
        }
      }
      let new_items : Array[JSValue] = []
      let new_present : Array[Bool] = []
      for i in 0..<start {
        let key = i.to_string()
        if js_has_prop(arr_val, key) {
          let value = js_get_prop(arr_val, key)
          new_items.push(value)
          new_present.push(true)
        } else {
          new_items.push(Undefined)
          new_present.push(false)
        }
      }
      for item in insert_items {
        new_items.push(item)
        new_present.push(true)
      }
      for i in (start + delete_count)..<len {
        let key = i.to_string()
        if js_has_prop(arr_val, key) {
          let value = js_get_prop(arr_val, key)
          new_items.push(value)
          new_present.push(true)
        } else {
          new_items.push(Undefined)
          new_present.push(false)
        }
      }
      arr.items.clear()
      arr.present.clear()
      for item in new_items {
        arr.items.push(item)
      }
      for flag in new_present {
        arr.present.push(flag)
      }
      arr.length = arr.items.length()
      removed
    }
    "toSpliced" => {
      let mut start = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      if start < 0 {
        start = len + start
        if start < 0 {
          start = 0
        }
      }
      if start > len {
        start = len
      }
      let mut delete_count = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        len - start
      }
      if delete_count < 0 {
        delete_count = 0
      }
      if delete_count > len - start {
        delete_count = len - start
      }
      let insert_items : Array[JSValue] = []
      if args.length() > 2 {
        for i in 2..<args.length() {
          insert_items.push(args[i])
        }
      }
      let out = js_new_array()
      match out {
        Array(out_arr) => {
          for i in 0..<start {
            let key = i.to_string()
            if js_has_prop(arr_val, key) {
              let value = js_get_prop(arr_val, key)
              out_arr.items.push(value)
              out_arr.present.push(true)
            } else {
              out_arr.items.push(Undefined)
              out_arr.present.push(false)
            }
          }
          for item in insert_items {
            out_arr.items.push(item)
            out_arr.present.push(true)
          }
          for i in (start + delete_count)..<len {
            let key = i.to_string()
            if js_has_prop(arr_val, key) {
              let value = js_get_prop(arr_val, key)
              out_arr.items.push(value)
              out_arr.present.push(true)
            } else {
              out_arr.items.push(Undefined)
              out_arr.present.push(false)
            }
          }
          out_arr.length = out_arr.items.length()
        }
        _ => ()
      }
      out
    }
    "sort" => {
      let compare_fn = if args.length() > 0 { args[0] } else { Undefined }
      let use_compare =
        if compare_fn is Undefined {
          false
        } else if self.is_callable(compare_fn) {
          true
        } else {
          return self.set_error_kind("TypeError", "Array.prototype.sort requires a callable")
        }
      let values : Array[(JSValue, Int)] = []
      let mut holes = 0
      let mut i = 0
      while i < len {
        if i < arr.items.length() && arr.present[i] {
          values.push((arr.items[i], i))
        } else {
          holes += 1
        }
        i += 1
      }
      if values.length() > 1 {
        self.quicksort_values(values, 0, values.length() - 1, compare_fn, use_compare)
      }
      arr.items.clear()
      arr.present.clear()
      for item in values {
        let (val, _) = item
        arr.items.push(val)
        arr.present.push(true)
      }
      for _ in 0..<holes {
        arr.items.push(Undefined)
        arr.present.push(false)
      }
      arr.length = len
      JSValue::Array(arr)
    }
    "toSorted" => {
      let compare_fn = if args.length() > 0 { args[0] } else { Undefined }
      let new_items : Array[JSValue] = arr.items.copy()
      let new_present : Array[Bool] = []
      for flag in arr.present {
        new_present.push(flag)
      }
      let new_arr : JSArray = {
        id: fresh_array_id(),
        items: new_items,
        present: new_present,
        props: [],
        length: new_items.length(),
        prototype: arr.prototype,
      }
      let _ = self.array_method(new_arr, "sort", [compare_fn])
      JSValue::Array(new_arr)
    }
    "toReversed" => {
      let out = js_new_array()
      match out {
        Array(out_arr) =>
          if len > 0 {
            let mut i = len - 1
            while i >= 0 {
              if i < arr.items.length() && arr.present[i] {
                out_arr.items.push(arr.items[i])
                out_arr.present.push(true)
              } else {
                out_arr.items.push(Undefined)
                out_arr.present.push(false)
              }
              if i == 0 {
                break
              }
              i = i - 1
            }
            out_arr.length = len
          }
        _ => ()
      }
      out
    }
    "with" =>
      if args.length() >= 2 {
        let mut idx = args[0].to_number().to_int()
        if idx < 0 {
          idx = len + idx
        }
        if idx < 0 || idx >= len {
          self.set_error_kind("RangeError", "Invalid array index")
        } else {
          let out = js_new_array()
          match out {
            Array(out_arr) => {
              for i, item in arr.items {
                out_arr.items.push(item)
                out_arr.present.push(arr.present[i])
              }
              if idx >= out_arr.items.length() {
                while out_arr.items.length() <= idx {
                  out_arr.items.push(Undefined)
                  out_arr.present.push(false)
                }
              }
              out_arr.items[idx] = args[1]
              out_arr.present[idx] = true
              out_arr.length = len
            }
            _ => ()
          }
          out
        }
      } else {
        let out = js_new_array()
        match out {
          Array(out_arr) => {
            for i, item in arr.items {
              out_arr.items.push(item)
              out_arr.present.push(arr.present[i])
            }
            out_arr.length = arr.items.length()
          }
          _ => ()
        }
        out
      }
    "flat" => {
      let depth = if args.length() > 0 { args[0].to_number().to_int() } else { 1 }
      let result : Array[JSValue] = []
      if depth <= 0 {
        for item in arr.items {
          result.push(item)
        }
      } else {
        self.flatten_array_items(arr.items, depth, result)
      }
      js_array_from(result)
    }
    "flatMap" =>
      if args.length() > 0 {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError",
            "Array.prototype.flatMap requires a callback",
          )
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let mapped : Array[JSValue] = []
        let arr_val = JSValue::Array(arr)
        let mut i = 0
        while i < len {
          let key = i.to_string()
          if js_has_prop(arr_val, key) {
            let item = self.get_prop_value(arr_val, key)
            let args_array = [
              item,
              JSValue::Number(i.to_double()),
              arr_val,
            ]
            let value = self.call_function(
              callback,
              this_arg,
              args_array,
            )
            mapped.push(value)
          }
          i += 1
        }
        let result : Array[JSValue] = []
        self.flatten_array_items(mapped, 1, result)
        js_array_from(result)
      } else {
        js_new_array()
      }
    "fill" => {
      let value = if args.length() > 0 { args[0] } else { Undefined }
      let mut start = if args.length() > 1 {
        self.to_number_value(args[1]).to_int()
      } else {
        0
      }
      let mut end = if args.length() > 2 {
        self.to_number_value(args[2]).to_int()
      } else {
        len
      }
      if start < 0 {
        start = len + start
        if start < 0 {
          start = 0
        }
      }
      if end < 0 {
        end = len + end
        if end < 0 {
          end = 0
        }
      }
      if start > len {
        start = len
      }
      if end > len {
        end = len
      }
      for i in start..<end {
        if i >= arr.items.length() {
          while arr.items.length() <= i {
            arr.items.push(Undefined)
            arr.present.push(false)
          }
        }
        arr.items[i] = value
        arr.present[i] = true
      }
      arr.length = arr.items.length()
      JSValue::Array(arr)
    }
    "copyWithin" => {
      let mut target = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      let mut start = if args.length() > 1 { args[1].to_number().to_int() } else { 0 }
      let mut end = if args.length() > 2 { args[2].to_number().to_int() } else { len }
      if target < 0 {
        target = len + target
      }
      if start < 0 {
        start = len + start
      }
      if end < 0 {
        end = len + end
      }
      if target < 0 {
        target = 0
      }
      if start < 0 {
        start = 0
      }
      if end < 0 {
        end = 0
      }
      if target > len {
        target = len
      }
      if start > len {
        start = len
      }
      if end > len {
        end = len
      }
      let count = if end - start < len - target { end - start } else { len - target }
      if count > 0 {
        let temp : Array[JSValue] = []
        let temp_present : Array[Bool] = []
        for i in 0..<count {
          let idx = start + i
          if idx < arr.items.length() && arr.present[idx] {
            temp.push(arr.items[idx])
            temp_present.push(true)
          } else {
            temp.push(Undefined)
            temp_present.push(false)
          }
        }
        for i in 0..<count {
          let idx = target + i
          if idx >= arr.items.length() {
            while arr.items.length() <= idx {
              arr.items.push(Undefined)
              arr.present.push(false)
            }
          }
          arr.items[idx] = temp[i]
          arr.present[idx] = temp_present[i]
        }
      }
      JSValue::Array(arr)
    }
    "at" => {
      let mut idx = if args.length() > 0 {
        self.to_number_value(args[0]).to_int()
      } else {
        0
      }
      if idx < 0 {
        idx = len + idx
      }
      if idx < 0 || idx >= len {
        Undefined
      } else {
        js_get_prop(arr_val, idx.to_string())
      }
    }
    _ => Undefined
  }
}
