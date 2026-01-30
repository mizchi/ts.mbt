///|
// /
fn JSInterpreter::install_builtins(self : JSInterpreter) -> Unit {
  let global_obj = self.new_object()

  // Object.prototype - all properties should be non-enumerable
  let has_own = self.make_native("Object.hasOwnProperty")
  self.set_function_length(has_own, 1.0)
  let _ = js_define_data_prop(self.object_proto, "hasOwnProperty", has_own, true, false, true)
  let to_string_fn = self.make_native("Object.prototype.toString")
  self.set_function_length(to_string_fn, 0.0)
  let _ = js_define_data_prop(self.object_proto, "toString", to_string_fn, true, false, true)
  let is_proto_fn = self.make_native("Object.prototype.isPrototypeOf")
  self.set_function_length(is_proto_fn, 1.0)
  let _ = js_define_data_prop(self.object_proto, "isPrototypeOf", is_proto_fn, true, false, true)
  let value_of_fn = self.make_native("Object.prototype.valueOf")
  self.set_function_length(value_of_fn, 0.0)
  let _ = js_define_data_prop(self.object_proto, "valueOf", value_of_fn, true, false, true)
  let prop_enum_fn = self.make_native("Object.prototype.propertyIsEnumerable")
  self.set_function_length(prop_enum_fn, 1.0)
  let _ = js_define_data_prop(self.object_proto, "propertyIsEnumerable", prop_enum_fn, true, false, true)

  // Object
  let object_ctor = self.make_native("Object")
  let _ = js_define_data_prop(object_ctor, "prototype", self.object_proto, true, false, true)
  let _ = js_set_prop(object_ctor, "name", JSValue::String("Object"))
  let _ = js_define_data_prop(self.object_proto, "constructor", object_ctor, true, false, true)
  let get_own = self.make_native("Object.getOwnPropertyNames")
  self.set_function_length(get_own, 1.0)
  let _ = js_set_prop(object_ctor, "getOwnPropertyNames", get_own)
  let obj_create = self.make_native("Object.create")
  self.set_function_length(obj_create, 2.0)
  let _ = js_set_prop(object_ctor, "create", obj_create)
  let obj_get_proto = self.make_native("Object.getPrototypeOf")
  self.set_function_length(obj_get_proto, 1.0)
  let _ = js_set_prop(object_ctor, "getPrototypeOf", obj_get_proto)
  let obj_get_desc = self.make_native("Object.getOwnPropertyDescriptor")
  self.set_function_length(obj_get_desc, 2.0)
  let _ = js_set_prop(object_ctor, "getOwnPropertyDescriptor", obj_get_desc)
  let obj_define_prop = self.make_native("Object.defineProperty")
  self.set_function_length(obj_define_prop, 3.0)
  let _ = js_set_prop(object_ctor, "defineProperty", obj_define_prop)
  let obj_set_proto = self.make_native("Object.setPrototypeOf")
  self.set_function_length(obj_set_proto, 2.0)
  let _ = js_define_data_prop(object_ctor, "setPrototypeOf", obj_set_proto, true, false, true)
  let obj_is_ext = self.make_native("Object.isExtensible")
  self.set_function_length(obj_is_ext, 1.0)
  let _ = js_set_prop(object_ctor, "isExtensible", obj_is_ext)
  let obj_is = self.make_native("Object.is")
  self.set_function_length(obj_is, 2.0)
  let _ = js_set_prop(object_ctor, "is", obj_is)
  let obj_keys = self.make_native("Object.keys")
  self.set_function_length(obj_keys, 1.0)
  let _ = js_set_prop(object_ctor, "keys", obj_keys)
  let obj_values = self.make_native("Object.values")
  self.set_function_length(obj_values, 1.0)
  let _ = js_set_prop(object_ctor, "values", obj_values)
  let obj_entries = self.make_native("Object.entries")
  self.set_function_length(obj_entries, 1.0)
  let _ = js_set_prop(object_ctor, "entries", obj_entries)
  let obj_assign = self.make_native("Object.assign")
  self.set_function_length(obj_assign, 2.0)
  let _ = js_set_prop(object_ctor, "assign", obj_assign)
  let obj_from_entries = self.make_native("Object.fromEntries")
  self.set_function_length(obj_from_entries, 1.0)
  let _ = js_set_prop(object_ctor, "fromEntries", obj_from_entries)
  self.global_env.define_var("Object", object_ctor)
  let _ = js_set_prop(global_obj, "Object", object_ctor)

  // console
  let console = self.new_object()
  let _ = js_set_prop(console, "log", self.make_native("console.log"))
  self.global_env.define_var("console", console)
  let _ = js_set_prop(global_obj, "console", console)

  // Math
  let math = self.new_object()
  let _ = js_set_prop(math, "__class", String("Math"))
  let _ = js_set_prop(math, "floor", self.make_native("Math.floor"))
  let _ = js_set_prop(math, "ceil", self.make_native("Math.ceil"))
  let _ = js_set_prop(math, "abs", self.make_native("Math.abs"))
  let _ = js_set_prop(math, "sqrt", self.make_native("Math.sqrt"))
  let _ = js_set_prop(math, "min", self.make_native("Math.min"))
  let _ = js_set_prop(math, "max", self.make_native("Math.max"))
  let _ = js_set_prop(math, "round", self.make_native("Math.round"))
  let _ = js_set_prop(math, "random", self.make_native("Math.random"))
  let _ = js_set_prop(math, "cos", self.make_native("Math.cos"))
  let _ = js_set_prop(math, "sin", self.make_native("Math.sin"))
  let _ = js_set_prop(math, "tan", self.make_native("Math.tan"))
  let _ = js_set_prop(math, "exp", self.make_native("Math.exp"))
  let _ = js_set_prop(math, "log", self.make_native("Math.log"))
  let _ = js_set_prop(math, "trunc", self.make_native("Math.trunc"))
  let _ = js_define_data_prop(math, "PI", Number(@math.PI), false, false, false)
  let _ = js_define_data_prop(math, "E", Number(@math.exp(1.0)), false, false, false)
  let _ = js_define_data_prop(math, "LN2", Number(@math.ln(2.0)), false, false, false)
  self.global_env.define_var("Math", math)
  let _ = js_set_prop(global_obj, "Math", math)

  // JSON
  let json_obj = self.new_object()
  let _ = js_set_prop(json_obj, "__class", String("JSON"))
  let json_parse = self.make_native("JSON.parse")
  self.set_function_length(json_parse, 2.0)
  let _ = js_set_prop(json_obj, "parse", json_parse)
  let json_stringify = self.make_native("JSON.stringify")
  self.set_function_length(json_stringify, 3.0)
  let _ = js_set_prop(json_obj, "stringify", json_stringify)
  self.global_env.define_var("JSON", json_obj)
  let _ = js_set_prop(global_obj, "JSON", json_obj)

  // Function
  let call_fn = self.make_native("Function.call")
  self.set_function_length(call_fn, 1.0)
  let _ = js_set_prop(self.function_proto, "call", call_fn)
  let apply_fn = self.make_native("Function.apply")
  self.set_function_length(apply_fn, 2.0)
  let _ = js_set_prop(self.function_proto, "apply", apply_fn)
  let bind_fn = self.make_native("Function.bind")
  self.set_function_length(bind_fn, 1.0)
  let _ = js_set_prop(self.function_proto, "bind", bind_fn)
  let has_instance = self.make_native("Function.prototype[@@hasInstance]")
  self.set_function_length(has_instance, 1.0)
  let _ = js_set_prop(self.function_proto, "@@hasInstance", has_instance)
  self.set_function_length(self.function_proto, 0.0)
  self.set_function_name(self.function_proto, "")
  let function_ctor = self.make_native("Function")
  self.set_function_length(function_ctor, 1.0)
  self.set_function_name(function_ctor, "Function")
  let _ = js_define_data_prop(function_ctor, "prototype", self.function_proto, true, false, true)
  let _ = js_set_prop(self.function_proto, "constructor", function_ctor)
  self.global_env.define_var("Function", function_ctor)
  let _ = js_set_prop(global_obj, "Function", function_ctor)

  // Boolean / Number / String
  let boolean_proto = self.new_object()
  let boolean_ctor = self.make_native("Boolean")
  self.set_function_length(boolean_ctor, 1.0)
  self.set_function_name(boolean_ctor, "Boolean")
  let _ = js_define_data_prop(boolean_ctor, "prototype", boolean_proto, true, false, true)
  let _ = js_set_prop(boolean_proto, "constructor", boolean_ctor)
  let _ = js_set_prop(boolean_proto, "value", Bool(false))
  let bool_value_of = self.make_native("Boolean.prototype.valueOf")
  self.set_function_length(bool_value_of, 0.0)
  let _ = js_set_prop(boolean_proto, "valueOf", bool_value_of)
  let bool_to_string = self.make_native("Boolean.prototype.toString")
  self.set_function_length(bool_to_string, 0.0)
  let _ = js_set_prop(boolean_proto, "toString", bool_to_string)
  self.global_env.define_var("Boolean", boolean_ctor)
  let _ = js_set_prop(global_obj, "Boolean", boolean_ctor)

  let number_proto = self.new_object()
  let number_ctor = self.make_native("Number")
  self.set_function_length(number_ctor, 1.0)
  self.set_function_name(number_ctor, "Number")
  let _ = js_define_data_prop(number_ctor, "prototype", number_proto, true, false, true)
  let _ = js_set_prop(number_proto, "constructor", number_ctor)
  let _ = js_set_prop(number_proto, "value", Number(0.0))
  let num_value_of = self.make_native("Number.prototype.valueOf")
  self.set_function_length(num_value_of, 0.0)
  let _ = js_set_prop(number_proto, "valueOf", num_value_of)
  let num_to_string = self.make_native("Number.prototype.toString")
  self.set_function_length(num_to_string, 0.0)
  let _ = js_set_prop(number_proto, "toString", num_to_string)
  let num_is_nan = self.make_native("Number.isNaN")
  self.set_function_length(num_is_nan, 1.0)
  let _ = js_set_prop(number_ctor, "isNaN", num_is_nan)
  let _ = js_define_data_prop(number_ctor, "NaN", Number(js_nan), false, false, false)
  let _ =
    js_define_data_prop(
      number_ctor,
      "POSITIVE_INFINITY",
      Number(1.0 / 0.0),
      false,
      false,
      false,
    )
  let _ =
    js_define_data_prop(
      number_ctor,
      "NEGATIVE_INFINITY",
      Number(-1.0 / 0.0),
      false,
      false,
      false,
    )
  let max_safe = JSValue::Number(9007199254740991.0)
  let _ = js_define_data_prop(number_ctor, "MAX_SAFE_INTEGER", max_safe, false, false, false)
  self.global_env.define_var("Number", number_ctor)
  let _ = js_set_prop(global_obj, "Number", number_ctor)

  let string_proto = self.new_object()
  let string_ctor = self.make_native("String")
  self.set_function_length(string_ctor, 1.0)
  self.set_function_name(string_ctor, "String")
  let _ = js_define_data_prop(string_ctor, "prototype", string_proto, true, false, true)
  let _ = js_set_prop(string_proto, "constructor", string_ctor)
  let _ = js_set_prop(string_proto, "value", String(""))
  let str_value_of = self.make_native("String.prototype.valueOf")
  self.set_function_length(str_value_of, 0.0)
  let _ = js_set_prop(string_proto, "valueOf", str_value_of)
  let str_to_string = self.make_native("String.prototype.toString")
  self.set_function_length(str_to_string, 0.0)
  let _ = js_set_prop(string_proto, "toString", str_to_string)
  let str_char_at = self.make_native("String.prototype.charAt")
  self.set_function_length(str_char_at, 1.0)
  let _ = js_set_prop(string_proto, "charAt", str_char_at)
  let str_char_code_at = self.make_native("String.prototype.charCodeAt")
  self.set_function_length(str_char_code_at, 1.0)
  let _ = js_set_prop(string_proto, "charCodeAt", str_char_code_at)
  let str_code_point_at = self.make_native("String.prototype.codePointAt")
  self.set_function_length(str_code_point_at, 1.0)
  let _ = js_set_prop(string_proto, "codePointAt", str_code_point_at)
  let str_index_of = self.make_native("String.prototype.indexOf")
  self.set_function_length(str_index_of, 1.0)
  let _ = js_set_prop(string_proto, "indexOf", str_index_of)
  let str_last_index_of = self.make_native("String.prototype.lastIndexOf")
  self.set_function_length(str_last_index_of, 1.0)
  let _ = js_set_prop(string_proto, "lastIndexOf", str_last_index_of)
  let str_includes = self.make_native("String.prototype.includes")
  self.set_function_length(str_includes, 1.0)
  let _ = js_set_prop(string_proto, "includes", str_includes)
  let str_starts_with = self.make_native("String.prototype.startsWith")
  self.set_function_length(str_starts_with, 1.0)
  let _ = js_set_prop(string_proto, "startsWith", str_starts_with)
  let str_ends_with = self.make_native("String.prototype.endsWith")
  self.set_function_length(str_ends_with, 1.0)
  let _ = js_set_prop(string_proto, "endsWith", str_ends_with)
  let str_at = self.make_native("String.prototype.at")
  self.set_function_length(str_at, 1.0)
  let _ = js_set_prop(string_proto, "at", str_at)
  let str_split = self.make_native("String.prototype.split")
  self.set_function_length(str_split, 2.0)
  let _ = js_set_prop(string_proto, "split", str_split)
  let str_replace = self.make_native("String.prototype.replace")
  self.set_function_length(str_replace, 2.0)
  let _ = js_set_prop(string_proto, "replace", str_replace)
  let str_replace_all = self.make_native("String.prototype.replaceAll")
  self.set_function_length(str_replace_all, 2.0)
  let _ = js_set_prop(string_proto, "replaceAll", str_replace_all)
  let str_trim = self.make_native("String.prototype.trim")
  self.set_function_length(str_trim, 0.0)
  let _ = js_set_prop(string_proto, "trim", str_trim)
  let str_trim_start = self.make_native("String.prototype.trimStart")
  self.set_function_length(str_trim_start, 0.0)
  let _ = js_set_prop(string_proto, "trimStart", str_trim_start)
  let str_trim_end = self.make_native("String.prototype.trimEnd")
  self.set_function_length(str_trim_end, 0.0)
  let _ = js_set_prop(string_proto, "trimEnd", str_trim_end)
  let str_slice = self.make_native("String.prototype.slice")
  self.set_function_length(str_slice, 2.0)
  let _ = js_set_prop(string_proto, "slice", str_slice)
  let str_substr = self.make_native("String.prototype.substr")
  self.set_function_length(str_substr, 2.0)
  let _ = js_set_prop(string_proto, "substr", str_substr)
  let str_substring = self.make_native("String.prototype.substring")
  self.set_function_length(str_substring, 2.0)
  let _ = js_set_prop(string_proto, "substring", str_substring)
  let str_concat = self.make_native("String.prototype.concat")
  self.set_function_length(str_concat, 1.0)
  let _ = js_set_prop(string_proto, "concat", str_concat)
  let str_to_upper = self.make_native("String.prototype.toUpperCase")
  self.set_function_length(str_to_upper, 0.0)
  let _ = js_set_prop(string_proto, "toUpperCase", str_to_upper)
  let str_to_lower = self.make_native("String.prototype.toLowerCase")
  self.set_function_length(str_to_lower, 0.0)
  let _ = js_set_prop(string_proto, "toLowerCase", str_to_lower)
  let str_to_locale_upper = self.make_native("String.prototype.toLocaleUpperCase")
  self.set_function_length(str_to_locale_upper, 0.0)
  let _ = js_set_prop(string_proto, "toLocaleUpperCase", str_to_locale_upper)
  let str_to_locale_lower = self.make_native("String.prototype.toLocaleLowerCase")
  self.set_function_length(str_to_locale_lower, 0.0)
  let _ = js_set_prop(string_proto, "toLocaleLowerCase", str_to_locale_lower)
  let str_repeat = self.make_native("String.prototype.repeat")
  self.set_function_length(str_repeat, 1.0)
  let _ = js_set_prop(string_proto, "repeat", str_repeat)
  let str_big = self.make_native("String.prototype.big")
  self.set_function_length(str_big, 0.0)
  let _ = js_set_prop(string_proto, "big", str_big)
  let str_small = self.make_native("String.prototype.small")
  self.set_function_length(str_small, 0.0)
  let _ = js_set_prop(string_proto, "small", str_small)
  let str_bold = self.make_native("String.prototype.bold")
  self.set_function_length(str_bold, 0.0)
  let _ = js_set_prop(string_proto, "bold", str_bold)
  let str_italics = self.make_native("String.prototype.italics")
  self.set_function_length(str_italics, 0.0)
  let _ = js_set_prop(string_proto, "italics", str_italics)
  let str_strike = self.make_native("String.prototype.strike")
  self.set_function_length(str_strike, 0.0)
  let _ = js_set_prop(string_proto, "strike", str_strike)
  let str_sub = self.make_native("String.prototype.sub")
  self.set_function_length(str_sub, 0.0)
  let _ = js_set_prop(string_proto, "sub", str_sub)
  let str_sup = self.make_native("String.prototype.sup")
  self.set_function_length(str_sup, 0.0)
  let _ = js_set_prop(string_proto, "sup", str_sup)
  let str_fixed = self.make_native("String.prototype.fixed")
  self.set_function_length(str_fixed, 0.0)
  let _ = js_set_prop(string_proto, "fixed", str_fixed)
  let str_blink = self.make_native("String.prototype.blink")
  self.set_function_length(str_blink, 0.0)
  let _ = js_set_prop(string_proto, "blink", str_blink)
  let str_fontcolor = self.make_native("String.prototype.fontcolor")
  self.set_function_length(str_fontcolor, 1.0)
  let _ = js_set_prop(string_proto, "fontcolor", str_fontcolor)
  let str_fontsize = self.make_native("String.prototype.fontsize")
  self.set_function_length(str_fontsize, 1.0)
  let _ = js_set_prop(string_proto, "fontsize", str_fontsize)
  let str_link = self.make_native("String.prototype.link")
  self.set_function_length(str_link, 1.0)
  let _ = js_set_prop(string_proto, "link", str_link)
  let str_pad_start = self.make_native("String.prototype.padStart")
  self.set_function_length(str_pad_start, 1.0)
  let _ = js_set_prop(string_proto, "padStart", str_pad_start)
  let str_pad_end = self.make_native("String.prototype.padEnd")
  self.set_function_length(str_pad_end, 1.0)
  let _ = js_set_prop(string_proto, "padEnd", str_pad_end)
  let str_from_char_code = self.make_native("String.fromCharCode")
  self.set_function_length(str_from_char_code, 1.0)
  let _ = js_set_prop(string_ctor, "fromCharCode", str_from_char_code)
  let str_from_code_point = self.make_native("String.fromCodePoint")
  self.set_function_length(str_from_code_point, 1.0)
  let _ = js_set_prop(string_ctor, "fromCodePoint", str_from_code_point)
  let str_iterator = self.make_native("String.prototype[@@iterator]")
  self.set_function_length(str_iterator, 0.0)
  let _ = js_set_prop(string_proto, "@@iterator", str_iterator)
  self.global_env.define_var("String", string_ctor)
  let _ = js_set_prop(global_obj, "String", string_ctor)

  // RegExp (minimal)
  let regexp_proto = self.new_object()
  let regexp_ctor = self.make_native("RegExp")
  self.set_function_length(regexp_ctor, 2.0)
  self.set_function_name(regexp_ctor, "RegExp")
  let _ = js_define_data_prop(regexp_ctor, "prototype", regexp_proto, true, false, true)
  let _ = js_set_prop(regexp_proto, "constructor", regexp_ctor)
  let re_exec = self.make_native("RegExp.prototype.exec")
  self.set_function_length(re_exec, 1.0)
  let _ = js_set_prop(regexp_proto, "exec", re_exec)
  let re_test = self.make_native("RegExp.prototype.test")
  self.set_function_length(re_test, 1.0)
  let _ = js_set_prop(regexp_proto, "test", re_test)
  let re_compile = self.make_native("RegExp.prototype.compile")
  self.set_function_length(re_compile, 2.0)
  let _ = js_set_prop(regexp_proto, "compile", re_compile)
  self.global_env.define_var("RegExp", regexp_ctor)
  let _ = js_set_prop(global_obj, "RegExp", regexp_ctor)

  // Array
  let array_proto = self.new_object()
  let array_ctor = self.make_native("Array")
  self.set_function_length(array_ctor, 1.0)
  self.set_function_name(array_ctor, "Array")
  let _ = js_define_data_prop(array_ctor, "prototype", array_proto, true, false, true)
  let _ = js_set_prop(array_proto, "constructor", array_ctor)
  js_set_default_array_proto(array_proto)
  let array_to_string = self.make_native("Array.prototype.toString")
  self.set_function_length(array_to_string, 0.0)
  let _ = js_set_prop(array_proto, "toString", array_to_string)
  let array_push = self.make_native("Array.prototype.push")
  self.set_function_length(array_push, 1.0)
  let _ = js_set_prop(array_proto, "push", array_push)
  let array_pop = self.make_native("Array.prototype.pop")
  self.set_function_length(array_pop, 0.0)
  let _ = js_set_prop(array_proto, "pop", array_pop)
  let array_shift = self.make_native("Array.prototype.shift")
  self.set_function_length(array_shift, 0.0)
  let _ = js_set_prop(array_proto, "shift", array_shift)
  let array_unshift = self.make_native("Array.prototype.unshift")
  self.set_function_length(array_unshift, 1.0)
  let _ = js_set_prop(array_proto, "unshift", array_unshift)
  let array_join = self.make_native("Array.prototype.join")
  self.set_function_length(array_join, 1.0)
  let _ = js_set_prop(array_proto, "join", array_join)
  let array_index_of = self.make_native("Array.prototype.indexOf")
  self.set_function_length(array_index_of, 1.0)
  let _ = js_set_prop(array_proto, "indexOf", array_index_of)
  let array_last_index_of = self.make_native("Array.prototype.lastIndexOf")
  self.set_function_length(array_last_index_of, 1.0)
  let _ = js_set_prop(array_proto, "lastIndexOf", array_last_index_of)
  let array_includes = self.make_native("Array.prototype.includes")
  self.set_function_length(array_includes, 1.0)
  let _ = js_set_prop(array_proto, "includes", array_includes)
  let array_map = self.make_native("Array.prototype.map")
  self.set_function_length(array_map, 1.0)
  let _ = js_set_prop(array_proto, "map", array_map)
  let array_filter = self.make_native("Array.prototype.filter")
  self.set_function_length(array_filter, 1.0)
  let _ = js_set_prop(array_proto, "filter", array_filter)
  let array_reduce = self.make_native("Array.prototype.reduce")
  self.set_function_length(array_reduce, 1.0)
  let _ = js_set_prop(array_proto, "reduce", array_reduce)
  let array_reduce_right = self.make_native("Array.prototype.reduceRight")
  self.set_function_length(array_reduce_right, 1.0)
  let _ = js_set_prop(array_proto, "reduceRight", array_reduce_right)
  let array_for_each = self.make_native("Array.prototype.forEach")
  self.set_function_length(array_for_each, 1.0)
  let _ = js_set_prop(array_proto, "forEach", array_for_each)
  let array_find = self.make_native("Array.prototype.find")
  self.set_function_length(array_find, 1.0)
  let _ = js_set_prop(array_proto, "find", array_find)
  let array_find_index = self.make_native("Array.prototype.findIndex")
  self.set_function_length(array_find_index, 1.0)
  let _ = js_set_prop(array_proto, "findIndex", array_find_index)
  let array_find_last = self.make_native("Array.prototype.findLast")
  self.set_function_length(array_find_last, 1.0)
  let _ = js_set_prop(array_proto, "findLast", array_find_last)
  let array_find_last_index = self.make_native("Array.prototype.findLastIndex")
  self.set_function_length(array_find_last_index, 1.0)
  let _ = js_set_prop(array_proto, "findLastIndex", array_find_last_index)
  let array_every = self.make_native("Array.prototype.every")
  self.set_function_length(array_every, 1.0)
  let _ = js_set_prop(array_proto, "every", array_every)
  let array_some = self.make_native("Array.prototype.some")
  self.set_function_length(array_some, 1.0)
  let _ = js_set_prop(array_proto, "some", array_some)
  let array_concat = self.make_native("Array.prototype.concat")
  self.set_function_length(array_concat, 1.0)
  let _ = js_set_prop(array_proto, "concat", array_concat)
  let array_slice = self.make_native("Array.prototype.slice")
  self.set_function_length(array_slice, 2.0)
  let _ = js_set_prop(array_proto, "slice", array_slice)
  let array_splice = self.make_native("Array.prototype.splice")
  self.set_function_length(array_splice, 2.0)
  let _ = js_set_prop(array_proto, "splice", array_splice)
  let array_sort = self.make_native("Array.prototype.sort")
  self.set_function_length(array_sort, 1.0)
  let _ = js_set_prop(array_proto, "sort", array_sort)
  let array_to_sorted = self.make_native("Array.prototype.toSorted")
  self.set_function_length(array_to_sorted, 1.0)
  let _ = js_set_prop(array_proto, "toSorted", array_to_sorted)
  let array_to_reversed = self.make_native("Array.prototype.toReversed")
  self.set_function_length(array_to_reversed, 0.0)
  let _ = js_set_prop(array_proto, "toReversed", array_to_reversed)
  let array_to_spliced = self.make_native("Array.prototype.toSpliced")
  self.set_function_length(array_to_spliced, 2.0)
  let _ = js_set_prop(array_proto, "toSpliced", array_to_spliced)
  let array_with = self.make_native("Array.prototype.with")
  self.set_function_length(array_with, 2.0)
  let _ = js_set_prop(array_proto, "with", array_with)
  let array_flat = self.make_native("Array.prototype.flat")
  self.set_function_length(array_flat, 0.0)
  let _ = js_set_prop(array_proto, "flat", array_flat)
  let array_flat_map = self.make_native("Array.prototype.flatMap")
  self.set_function_length(array_flat_map, 1.0)
  let _ = js_set_prop(array_proto, "flatMap", array_flat_map)
  let array_fill = self.make_native("Array.prototype.fill")
  self.set_function_length(array_fill, 1.0)
  let _ = js_set_prop(array_proto, "fill", array_fill)
  let array_copy_within = self.make_native("Array.prototype.copyWithin")
  self.set_function_length(array_copy_within, 2.0)
  let _ = js_set_prop(array_proto, "copyWithin", array_copy_within)
  let array_at = self.make_native("Array.prototype.at")
  self.set_function_length(array_at, 1.0)
  let _ = js_set_prop(array_proto, "at", array_at)
  let array_iterator = self.make_native("Array.prototype[@@iterator]")
  self.set_function_length(array_iterator, 0.0)
  let _ = js_set_prop(array_proto, "@@iterator", array_iterator)
  let is_array_fn = self.make_native("Array.isArray")
  self.set_function_length(is_array_fn, 1.0)
  let _ = js_set_prop(array_ctor, "isArray", is_array_fn)
  self.global_env.define_var("Array", array_ctor)
  let _ = js_set_prop(global_obj, "Array", array_ctor)

  // Date
  let date_proto = self.new_object()
  let date_ctor = self.make_native("Date")
  self.set_function_length(date_ctor, 7.0)
  self.set_function_name(date_ctor, "Date")
  let _ = js_define_data_prop(date_ctor, "prototype", date_proto, true, false, true)
  let _ = js_set_prop(date_proto, "constructor", date_ctor)
  let date_get_year = self.make_native("Date.prototype.getYear")
  self.set_function_length(date_get_year, 0.0)
  let _ = js_set_prop(date_proto, "getYear", date_get_year)
  let date_set_year = self.make_native("Date.prototype.setYear")
  self.set_function_length(date_set_year, 1.0)
  let _ = js_set_prop(date_proto, "setYear", date_set_year)
  let date_get_full_year = self.make_native("Date.prototype.getFullYear")
  self.set_function_length(date_get_full_year, 0.0)
  let _ = js_set_prop(date_proto, "getFullYear", date_get_full_year)
  let date_get_time = self.make_native("Date.prototype.getTime")
  self.set_function_length(date_get_time, 0.0)
  let _ = js_set_prop(date_proto, "getTime", date_get_time)
  let date_set_time = self.make_native("Date.prototype.setTime")
  self.set_function_length(date_set_time, 1.0)
  let _ = js_set_prop(date_proto, "setTime", date_set_time)
  let date_value_of = self.make_native("Date.prototype.valueOf")
  self.set_function_length(date_value_of, 0.0)
  let _ = js_set_prop(date_proto, "valueOf", date_value_of)
  self.global_env.define_var("Date", date_ctor)
  let _ = js_set_prop(global_obj, "Date", date_ctor)

  // Errors (minimal)
  let error_ctor = self.make_native("Error")
  self.set_function_name(error_ctor, "Error")
  let _ = js_define_data_prop(error_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("Error", error_ctor)
  let _ = js_set_prop(global_obj, "Error", error_ctor)
  let syntax_ctor = self.make_native("SyntaxError")
  self.set_function_name(syntax_ctor, "SyntaxError")
  let _ = js_define_data_prop(syntax_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("SyntaxError", syntax_ctor)
  let _ = js_set_prop(global_obj, "SyntaxError", syntax_ctor)
  let type_ctor = self.make_native("TypeError")
  self.set_function_name(type_ctor, "TypeError")
  let _ = js_define_data_prop(type_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("TypeError", type_ctor)
  let _ = js_set_prop(global_obj, "TypeError", type_ctor)
  let ref_ctor = self.make_native("ReferenceError")
  self.set_function_name(ref_ctor, "ReferenceError")
  let _ = js_define_data_prop(ref_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("ReferenceError", ref_ctor)
  let _ = js_set_prop(global_obj, "ReferenceError", ref_ctor)
  let range_ctor = self.make_native("RangeError")
  self.set_function_name(range_ctor, "RangeError")
  let _ = js_define_data_prop(range_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("RangeError", range_ctor)
  let _ = js_set_prop(global_obj, "RangeError", range_ctor)
  let aggregate_ctor = self.make_native("AggregateError")
  self.set_function_name(aggregate_ctor, "AggregateError")
  let _ = js_define_data_prop(aggregate_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("AggregateError", aggregate_ctor)
  let _ = js_set_prop(global_obj, "AggregateError", aggregate_ctor)
  let uri_ctor = self.make_native("URIError")
  self.set_function_name(uri_ctor, "URIError")
  let _ = js_define_data_prop(uri_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("URIError", uri_ctor)
  let _ = js_set_prop(global_obj, "URIError", uri_ctor)
  let eval_error_ctor = self.make_native("EvalError")
  self.set_function_name(eval_error_ctor, "EvalError")
  let _ = js_define_data_prop(eval_error_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("EvalError", eval_error_ctor)
  let _ = js_set_prop(global_obj, "EvalError", eval_error_ctor)

  // Promise (minimal)
  let promise_proto = self.new_object()
  let promise_ctor = self.make_native("Promise")
  self.set_function_length(promise_ctor, 1.0)
  self.set_function_name(promise_ctor, "Promise")
  let _ = js_define_data_prop(promise_ctor, "prototype", promise_proto, true, false, true)
  let _ = js_set_prop(promise_ctor, "__default_proto__", promise_proto)
  let _ = js_set_prop(promise_proto, "constructor", promise_ctor)
  let promise_then = self.make_native("Promise.prototype.then")
  self.set_function_length(promise_then, 2.0)
  self.set_function_name(promise_then, "then")
  let _ = js_set_prop(promise_proto, "then", promise_then)
  let _ = js_set_prop(promise_ctor, "then", promise_then)
  let promise_catch = self.make_native("Promise.prototype.catch")
  self.set_function_length(promise_catch, 1.0)
  self.set_function_name(promise_catch, "catch")
  let _ = js_set_prop(promise_proto, "catch", promise_catch)
  let promise_finally = self.make_native("Promise.prototype.finally")
  self.set_function_length(promise_finally, 1.0)
  self.set_function_name(promise_finally, "finally")
  let _ = js_set_prop(promise_proto, "finally", promise_finally)
  let promise_resolve = self.make_native("Promise.resolve")
  self.set_function_length(promise_resolve, 1.0)
  self.set_function_name(promise_resolve, "resolve")
  let _ = js_set_prop(promise_ctor, "resolve", promise_resolve)
  let promise_reject = self.make_native("Promise.reject")
  self.set_function_length(promise_reject, 1.0)
  self.set_function_name(promise_reject, "reject")
  let _ = js_set_prop(promise_ctor, "reject", promise_reject)
  let promise_all = self.make_native("Promise.all")
  self.set_function_length(promise_all, 1.0)
  self.set_function_name(promise_all, "all")
  let _ = js_set_prop(promise_ctor, "all", promise_all)
  let promise_race = self.make_native("Promise.race")
  self.set_function_length(promise_race, 1.0)
  self.set_function_name(promise_race, "race")
  let _ = js_set_prop(promise_ctor, "race", promise_race)
  let promise_all_settled = self.make_native("Promise.allSettled")
  self.set_function_length(promise_all_settled, 1.0)
  self.set_function_name(promise_all_settled, "allSettled")
  let _ = js_set_prop(promise_ctor, "allSettled", promise_all_settled)
  let promise_any = self.make_native("Promise.any")
  self.set_function_length(promise_any, 1.0)
  self.set_function_name(promise_any, "any")
  let _ = js_set_prop(promise_ctor, "any", promise_any)
  let promise_with_resolvers = self.make_native("Promise.withResolvers")
  self.set_function_length(promise_with_resolvers, 0.0)
  self.set_function_name(promise_with_resolvers, "withResolvers")
  let _ = js_set_prop(promise_ctor, "withResolvers", promise_with_resolvers)
  let promise_try = self.make_native("Promise.try")
  self.set_function_length(promise_try, 1.0)
  self.set_function_name(promise_try, "try")
  let _ = js_set_prop(promise_ctor, "try", promise_try)
  let promise_species_get = self.make_native("Promise[@@species]")
  self.set_function_length(promise_species_get, 0.0)
  self.set_function_name(promise_species_get, "get [Symbol.species]")
  let _ = js_define_accessor_prop(
    promise_ctor,
    "@@species",
    Some(promise_species_get),
    None,
    false,
    true,
  )
  self.global_env.define_var("Promise", promise_ctor)
  let _ = js_set_prop(global_obj, "Promise", promise_ctor)

  // Iterator helpers (minimal)
  let iterator_proto = self.new_object()
  let iterator_ctor = self.make_native("Iterator")
  self.set_function_length(iterator_ctor, 0.0)
  self.set_function_name(iterator_ctor, "Iterator")
  let _ = js_define_data_prop(iterator_ctor, "prototype", iterator_proto, false, false, false)
  let _ = js_set_prop(iterator_proto, "constructor", iterator_ctor)

  let iterator_iter = self.make_native("Iterator.prototype[@@iterator]")
  self.set_function_length(iterator_iter, 0.0)
  let _ = js_define_data_prop(iterator_proto, "@@iterator", iterator_iter, true, false, true)

  let iterator_from = self.make_native("Iterator.from")
  self.set_function_length(iterator_from, 1.0)
  self.set_function_name(iterator_from, "from")
  let _ = js_define_data_prop(iterator_ctor, "from", iterator_from, true, false, true)

  let iter_map = self.make_native("Iterator.prototype.map")
  self.set_function_length(iter_map, 1.0)
  self.set_function_name(iter_map, "map")
  let _ = js_define_data_prop(iterator_proto, "map", iter_map, true, false, true)

  let iter_filter = self.make_native("Iterator.prototype.filter")
  self.set_function_length(iter_filter, 1.0)
  self.set_function_name(iter_filter, "filter")
  let _ = js_define_data_prop(iterator_proto, "filter", iter_filter, true, false, true)

  let iter_take = self.make_native("Iterator.prototype.take")
  self.set_function_length(iter_take, 1.0)
  self.set_function_name(iter_take, "take")
  let _ = js_define_data_prop(iterator_proto, "take", iter_take, true, false, true)

  let iter_drop = self.make_native("Iterator.prototype.drop")
  self.set_function_length(iter_drop, 1.0)
  self.set_function_name(iter_drop, "drop")
  let _ = js_define_data_prop(iterator_proto, "drop", iter_drop, true, false, true)

  let iter_flat_map = self.make_native("Iterator.prototype.flatMap")
  self.set_function_length(iter_flat_map, 1.0)
  self.set_function_name(iter_flat_map, "flatMap")
  let _ = js_define_data_prop(iterator_proto, "flatMap", iter_flat_map, true, false, true)

  let iter_for_each = self.make_native("Iterator.prototype.forEach")
  self.set_function_length(iter_for_each, 1.0)
  self.set_function_name(iter_for_each, "forEach")
  let _ = js_define_data_prop(iterator_proto, "forEach", iter_for_each, true, false, true)

  let iter_to_array = self.make_native("Iterator.prototype.toArray")
  self.set_function_length(iter_to_array, 0.0)
  self.set_function_name(iter_to_array, "toArray")
  let _ = js_define_data_prop(iterator_proto, "toArray", iter_to_array, true, false, true)

  let iter_reduce = self.make_native("Iterator.prototype.reduce")
  self.set_function_length(iter_reduce, 1.0)
  self.set_function_name(iter_reduce, "reduce")
  let _ = js_define_data_prop(iterator_proto, "reduce", iter_reduce, true, false, true)

  let iter_every = self.make_native("Iterator.prototype.every")
  self.set_function_length(iter_every, 1.0)
  self.set_function_name(iter_every, "every")
  let _ = js_define_data_prop(iterator_proto, "every", iter_every, true, false, true)

  let iter_some = self.make_native("Iterator.prototype.some")
  self.set_function_length(iter_some, 1.0)
  self.set_function_name(iter_some, "some")
  let _ = js_define_data_prop(iterator_proto, "some", iter_some, true, false, true)

  let iter_find = self.make_native("Iterator.prototype.find")
  self.set_function_length(iter_find, 1.0)
  self.set_function_name(iter_find, "find")
  let _ = js_define_data_prop(iterator_proto, "find", iter_find, true, false, true)

  let helper_proto = self.new_object()
  let helper_next = self.make_native("IteratorHelper.prototype.next")
  self.set_function_length(helper_next, 0.0)
  self.set_function_name(helper_next, "next")
  let _ = js_define_data_prop(helper_proto, "next", helper_next, true, false, true)
  let helper_return = self.make_native("IteratorHelper.prototype.return")
  self.set_function_length(helper_return, 0.0)
  self.set_function_name(helper_return, "return")
  let _ = js_define_data_prop(helper_proto, "return", helper_return, true, false, true)
  let helper_throw = self.make_native("IteratorHelper.prototype.throw")
  self.set_function_length(helper_throw, 0.0)
  self.set_function_name(helper_throw, "throw")
  let _ = js_define_data_prop(helper_proto, "throw", helper_throw, true, false, true)
  let _ = js_set_prop(helper_proto, "__proto__", iterator_proto)
  let _ = js_set_prop(iterator_ctor, "__helper_proto", helper_proto)

  self.global_env.define_var("Iterator", iterator_ctor)
  let _ = js_define_data_prop(global_obj, "Iterator", iterator_ctor, true, false, true)

  let test262_ctor = self.make_native("Test262Error")
  self.set_function_name(test262_ctor, "Test262Error")
  let _ = js_define_data_prop(test262_ctor, "prototype", self.new_object(), true, false, true)
  let test262_thrower = self.make_native("Test262Error.thrower")
  self.set_function_length(test262_thrower, 0.0)
  let _ = js_set_prop(test262_ctor, "thrower", test262_thrower)
  self.global_env.define_var("Test262Error", test262_ctor)
  let _ = js_set_prop(global_obj, "Test262Error", test262_ctor)

  // assert (callable object)
  let assert_obj = self.new_object()
  let _ = js_set_prop(assert_obj, "$call", self.make_native("assert"))
  let _ = js_set_prop(
    assert_obj,
    "sameValue",
    self.make_native("assert.sameValue"),
  )
  let _ = js_set_prop(
    assert_obj,
    "notSameValue",
    self.make_native("assert.notSameValue"),
  )
  let _ = js_set_prop(
    assert_obj,
    "compareArray",
    self.make_native("assert.compareArray"),
  )
  let _ = js_set_prop(
    assert_obj,
    "throws",
    self.make_native("assert.throws"),
  )
  self.global_env.define_var("assert", assert_obj)
  let _ = js_set_prop(global_obj, "assert", assert_obj)

  // print
  let print_fn = self.make_native("print")
  self.global_env.define_var("print", print_fn)
  let _ = js_set_prop(global_obj, "print", print_fn)
  let escape_fn = self.make_native("escape")
  self.set_function_length(escape_fn, 1.0)
  self.global_env.define_var("escape", escape_fn)
  let _ = js_set_prop(global_obj, "escape", escape_fn)
  let unescape_fn = self.make_native("unescape")
  self.set_function_length(unescape_fn, 1.0)
  self.global_env.define_var("unescape", unescape_fn)
  let _ = js_set_prop(global_obj, "unescape", unescape_fn)

  // eval
  let eval_fn = self.make_native("eval")
  self.set_function_length(eval_fn, 1.0)
  self.global_env.define_var("eval", eval_fn)
  let _ = js_set_prop(global_obj, "eval", eval_fn)

  // queueMicrotask
  let queue_microtask_fn = self.make_native("queueMicrotask")
  self.set_function_length(queue_microtask_fn, 1.0)
  self.global_env.define_var("queueMicrotask", queue_microtask_fn)
  let _ = js_set_prop(global_obj, "queueMicrotask", queue_microtask_fn)

  // $DONOTEVALUATE
  let donotevaluate_fn = self.make_native("$DONOTEVALUATE")
  self.global_env.define_var("$DONOTEVALUATE", donotevaluate_fn)
  let _ = js_set_prop(global_obj, "$DONOTEVALUATE", donotevaluate_fn)

  // $ERROR / $DONE
  let error_fn = self.make_native("$ERROR")
  self.global_env.define_var("$ERROR", error_fn)
  let _ = js_set_prop(global_obj, "$ERROR", error_fn)
  let done_fn = self.make_native("$DONE")
  self.global_env.define_var("$DONE", done_fn)
  let _ = js_set_prop(global_obj, "$DONE", done_fn)

  // $262
  let t262 = self.new_object()
  let _ = js_set_prop(t262, "global", global_obj)
  let _ = js_set_prop(t262, "evalScript", self.make_native("$262.evalScript"))
  let _ = js_set_prop(t262, "createRealm", self.make_native("$262.createRealm"))
  let html_dda = self.new_object()
  let _ = js_set_prop(html_dda, "__class", String("IsHTMLDDA"))
  let _ = js_set_prop(html_dda, "$call", self.make_native("IsHTMLDDA"))
  let _ = js_set_prop(t262, "IsHTMLDDA", html_dda)
  self.global_env.define_var("$262", t262)
  let _ = js_set_prop(global_obj, "$262", t262)

  // globalThis / global
  self.global_env.define_var("globalThis", global_obj)
  self.global_env.define_var("global", global_obj)
  self.global_env.define_var("this", global_obj)
  self.global_env.define_var("undefined", Undefined)
  let _ = js_set_prop(global_obj, "undefined", Undefined)
  let nan = JSValue::Number(0.0 / 0.0)
  let inf = JSValue::Number(1.0 / 0.0)
  self.global_env.define_var("NaN", nan)
  self.global_env.define_var("Infinity", inf)
  let _ = js_set_prop(global_obj, "NaN", nan)
  let _ = js_set_prop(global_obj, "Infinity", inf)

  // Global functions: isNaN, isFinite, parseInt, parseFloat
  let is_nan_fn = self.make_native("isNaN")
  self.set_function_length(is_nan_fn, 1.0)
  self.global_env.define_var("isNaN", is_nan_fn)
  let _ = js_set_prop(global_obj, "isNaN", is_nan_fn)

  let is_finite_fn = self.make_native("isFinite")
  self.set_function_length(is_finite_fn, 1.0)
  self.global_env.define_var("isFinite", is_finite_fn)
  let _ = js_set_prop(global_obj, "isFinite", is_finite_fn)

  let parse_int_fn = self.make_native("parseInt")
  self.set_function_length(parse_int_fn, 2.0)
  self.global_env.define_var("parseInt", parse_int_fn)
  let _ = js_set_prop(global_obj, "parseInt", parse_int_fn)

  let parse_float_fn = self.make_native("parseFloat")
  self.set_function_length(parse_float_fn, 1.0)
  self.global_env.define_var("parseFloat", parse_float_fn)
  let _ = js_set_prop(global_obj, "parseFloat", parse_float_fn)

  // Symbol
  let symbol_fn = self.make_native("Symbol")
  self.set_function_length(symbol_fn, 0.0)
  let string_ctor = self.global_env.get("String")
  let string_proto = js_get_prop(string_ctor, "prototype")
  let _ = js_define_data_prop(symbol_fn, "prototype", string_proto, true, false, true)
  let _ = js_set_prop(symbol_fn, "hasInstance", String("@@hasInstance"))
  let _ = js_set_prop(symbol_fn, "iterator", String("@@iterator"))
  let _ = js_set_prop(symbol_fn, "species", String("@@species"))
  self.global_env.define_var("Symbol", symbol_fn)
  let _ = js_set_prop(global_obj, "Symbol", symbol_fn)

  // Proxy (minimal)
  let proxy_ctor = self.make_native("Proxy")
  self.set_function_length(proxy_ctor, 2.0)
  self.set_function_name(proxy_ctor, "Proxy")
  let _ = js_define_data_prop(proxy_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("Proxy", proxy_ctor)
  let _ = js_set_prop(global_obj, "Proxy", proxy_ctor)

  // Reflect
  let reflect = self.new_object()
  let _ = js_set_prop(reflect, "construct", self.make_native("Reflect.construct"))
  let reflect_get = self.make_native("Reflect.get")
  self.set_function_length(reflect_get, 2.0)
  self.set_function_name(reflect_get, "get")
  let _ = js_set_prop(reflect, "get", reflect_get)
  let reflect_set = self.make_native("Reflect.set")
  self.set_function_length(reflect_set, 3.0)
  self.set_function_name(reflect_set, "set")
  let _ = js_set_prop(reflect, "set", reflect_set)
  let reflect_has = self.make_native("Reflect.has")
  self.set_function_length(reflect_has, 2.0)
  self.set_function_name(reflect_has, "has")
  let _ = js_set_prop(reflect, "has", reflect_has)
  let reflect_define = self.make_native("Reflect.defineProperty")
  self.set_function_length(reflect_define, 3.0)
  self.set_function_name(reflect_define, "defineProperty")
  let _ = js_set_prop(reflect, "defineProperty", reflect_define)
  let reflect_get_proto = self.make_native("Reflect.getPrototypeOf")
  self.set_function_length(reflect_get_proto, 1.0)
  self.set_function_name(reflect_get_proto, "getPrototypeOf")
  let _ = js_set_prop(reflect, "getPrototypeOf", reflect_get_proto)
  let reflect_get_desc = self.make_native("Reflect.getOwnPropertyDescriptor")
  self.set_function_length(reflect_get_desc, 2.0)
  self.set_function_name(reflect_get_desc, "getOwnPropertyDescriptor")
  let _ = js_set_prop(reflect, "getOwnPropertyDescriptor", reflect_get_desc)
  self.global_env.define_var("Reflect", reflect)
  let _ = js_set_prop(global_obj, "Reflect", reflect)

  // Map (stub)
  let map_ctor = self.make_native("Map")
  self.set_function_length(map_ctor, 0.0)
  self.set_function_name(map_ctor, "Map")
  let _ = js_define_data_prop(map_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("Map", map_ctor)
  let _ = js_set_prop(global_obj, "Map", map_ctor)

  // Set (stub)
  let set_ctor = self.make_native("Set")
  self.set_function_length(set_ctor, 0.0)
  self.set_function_name(set_ctor, "Set")
  let _ = js_define_data_prop(set_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("Set", set_ctor)
  let _ = js_set_prop(global_obj, "Set", set_ctor)

  // WeakMap (stub)
  let weakmap_ctor = self.make_native("WeakMap")
  self.set_function_length(weakmap_ctor, 0.0)
  self.set_function_name(weakmap_ctor, "WeakMap")
  let _ = js_define_data_prop(weakmap_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("WeakMap", weakmap_ctor)
  let _ = js_set_prop(global_obj, "WeakMap", weakmap_ctor)

  // WeakSet (stub)
  let weakset_ctor = self.make_native("WeakSet")
  self.set_function_length(weakset_ctor, 0.0)
  self.set_function_name(weakset_ctor, "WeakSet")
  let _ = js_define_data_prop(weakset_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("WeakSet", weakset_ctor)
  let _ = js_set_prop(global_obj, "WeakSet", weakset_ctor)

  // ArrayBuffer (stub)
  let arraybuffer_ctor = self.make_native("ArrayBuffer")
  self.set_function_length(arraybuffer_ctor, 1.0)
  self.set_function_name(arraybuffer_ctor, "ArrayBuffer")
  let _ = js_define_data_prop(arraybuffer_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("ArrayBuffer", arraybuffer_ctor)
  let _ = js_set_prop(global_obj, "ArrayBuffer", arraybuffer_ctor)

  // DataView (stub)
  let dataview_ctor = self.make_native("DataView")
  self.set_function_length(dataview_ctor, 1.0)
  self.set_function_name(dataview_ctor, "DataView")
  let _ = js_define_data_prop(dataview_ctor, "prototype", self.new_object(), true, false, true)
  self.global_env.define_var("DataView", dataview_ctor)
  let _ = js_set_prop(global_obj, "DataView", dataview_ctor)

  // TypedArrays (stubs)
  let typed_arrays = [
    "Int8Array", "Uint8Array", "Uint8ClampedArray", "Int16Array", "Uint16Array",
    "Int32Array", "Uint32Array", "Float32Array", "Float64Array", "BigInt64Array", "BigUint64Array",
  ]
  for name in typed_arrays {
    let ctor = self.make_native(name)
    self.set_function_length(ctor, 3.0)
    self.set_function_name(ctor, name)
    let _ = js_define_data_prop(ctor, "prototype", self.new_object(), true, false, true)
    self.global_env.define_var(name, ctor)
    let _ = js_set_prop(global_obj, name, ctor)
  }
}

///|
fn JSInterpreter::array_like_string_value(
  _self : JSInterpreter,
  receiver : JSValue,
) -> String? {
  match receiver {
    String(s) => Some(s)
    Object(_) | Function(_) =>
      match js_get_prop(receiver, "value") {
        String(s) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
fn JSInterpreter::array_like_method(
  self : JSInterpreter,
  receiver : JSValue,
  method_name : String,
  args : Array[JSValue],
) -> JSValue {
  let str_value = self.array_like_string_value(receiver)
  let len = self.array_like_length(receiver)
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  match method_name {
    "join" => {
      let sep = if args.length() > 0 { args[0].to_js_string() } else { "," }
      let parts : Array[String] = []
      for i in 0..<len {
        let key = i.to_string()
        let has_prop = js_has_prop(receiver, key)
        let use_string =
          match str_value {
            Some(s) => not(has_prop) && i >= 0 && i < s.length()
            None => false
          }
        if has_prop {
          let value = self.get_prop_value(receiver, key)
          parts.push(value.to_js_string())
        } else if use_string {
          match str_value {
            Some(s) =>
              parts.push(try { s[i:i + 1].to_string() } catch { _ => "" })
            None => parts.push("")
          }
        } else {
          parts.push("")
        }
      }
      String(parts.join(sep))
    }
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
        return Number(-1.0)
      }
      for i in start_idx..<len {
        let key = i.to_string()
        let has_prop = js_has_prop(receiver, key)
        let use_string =
          match str_value {
            Some(s) => not(has_prop) && i >= 0 && i < s.length()
            None => false
          }
        if not(has_prop) && not(use_string) {
          continue
        }
        let value =
          if has_prop {
            self.get_prop_value(receiver, key)
          } else {
            match str_value {
              Some(s) =>
                String(try { s[i:i + 1].to_string() } catch { _ => "" })
              None => Undefined
            }
          }
        match js_strict_eq(value, target) {
          Bool(true) => return Number(i.to_double())
          _ => ()
        }
      }
      Number(-1.0)
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
        return Number(-1.0)
      }
      let mut i = from_idx
      while i >= 0 {
        let key = i.to_string()
        let has_prop = js_has_prop(receiver, key)
        let use_string =
          match str_value {
            Some(s) => not(has_prop) && i >= 0 && i < s.length()
            None => false
          }
        if has_prop || use_string {
          let value =
            if has_prop {
              self.get_prop_value(receiver, key)
            } else {
              match str_value {
                Some(s) =>
                  String(try { s[i:i + 1].to_string() } catch { _ => "" })
                None => Undefined
              }
            }
          match js_strict_eq(value, target) {
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
        let key = i.to_string()
        let value =
          if js_has_prop(receiver, key) {
            self.get_prop_value(receiver, key)
          } else {
            match str_value {
              Some(s) if i >= 0 && i < s.length() =>
                String(try { s[i:i + 1].to_string() } catch { _ => "" })
              _ => Undefined
            }
          }
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
        let map_len = len
        let out = js_new_array()
        match out {
          Array(out_arr) => {
            let mut i = 0
            while i < map_len {
              let key = i.to_string()
              let has_prop = js_has_prop(receiver, key)
              let use_string =
                match str_value {
                  Some(s) => not(has_prop) && i >= 0 && i < s.length()
                  None => false
                }
              if has_prop || use_string {
                let value =
                  if has_prop {
                    self.get_prop_value(receiver, key)
                  } else {
                    match str_value {
                      Some(s) =>
                        String(try { s[i:i + 1].to_string() } catch { _ => "" })
                      None => Undefined
                    }
                  }
                let args_array = [
                  value,
                  Number(i.to_double()),
                  receiver,
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
          let has_prop = js_has_prop(receiver, key)
          let use_string =
            match str_value {
              Some(s) => not(has_prop) && i >= 0 && i < s.length()
              None => false
            }
          if has_prop || use_string {
            let item =
              if has_prop {
                self.get_prop_value(receiver, key)
              } else {
                match str_value {
                  Some(s) =>
                    String(try { s[i:i + 1].to_string() } catch { _ => "" })
                  None => Undefined
                }
              }
            let args_array = [
              item,
              Number(i.to_double()),
              receiver,
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
            let has_prop = js_has_prop(receiver, key)
            let use_string =
              match str_value {
                Some(s) => not(has_prop) && i >= 0 && i < s.length()
                None => false
              }
            if has_prop || use_string {
              accumulator =
                if has_prop {
                  self.get_prop_value(receiver, key)
                } else {
                  match str_value {
                    Some(s) =>
                      String(try { s[i:i + 1].to_string() } catch { _ => "" })
                    None => Undefined
                  }
                }
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
          let has_prop = js_has_prop(receiver, key)
          let use_string =
            match str_value {
              Some(s) => not(has_prop) && i >= 0 && i < s.length()
              None => false
            }
          if has_prop || use_string {
            let value =
              if has_prop {
                self.get_prop_value(receiver, key)
              } else {
                match str_value {
                  Some(s) =>
                    String(try { s[i:i + 1].to_string() } catch { _ => "" })
                  None => Undefined
                }
              }
            let args_array = [
              accumulator,
              value,
              Number(i.to_double()),
              receiver,
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
            let has_prop = js_has_prop(receiver, key)
            let use_string =
              match str_value {
                Some(s) => not(has_prop) && i >= 0 && i < s.length()
                None => false
              }
            if has_prop || use_string {
              accumulator =
                if has_prop {
                  self.get_prop_value(receiver, key)
                } else {
                  match str_value {
                    Some(s) =>
                      String(try { s[i:i + 1].to_string() } catch { _ => "" })
                    None => Undefined
                  }
                }
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
          let has_prop = js_has_prop(receiver, key)
          let use_string =
            match str_value {
              Some(s) => not(has_prop) && i >= 0 && i < s.length()
              None => false
            }
          if has_prop || use_string {
            let value =
              if has_prop {
                self.get_prop_value(receiver, key)
              } else {
                match str_value {
                  Some(s) =>
                    String(try { s[i:i + 1].to_string() } catch { _ => "" })
                  None => Undefined
                }
              }
            let args_array = [
              accumulator,
              value,
              Number(i.to_double()),
              receiver,
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
          let has_prop = js_has_prop(receiver, key)
          let use_string =
            match str_value {
              Some(s) => not(has_prop) && i >= 0 && i < s.length()
              None => false
            }
          if has_prop || use_string {
            let value =
              if has_prop {
                self.get_prop_value(receiver, key)
              } else {
                match str_value {
                  Some(s) =>
                    String(try { s[i:i + 1].to_string() } catch { _ => "" })
                  None => Undefined
                }
              }
            let args_array = [
              value,
              Number(i.to_double()),
              receiver,
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
          let has_prop = js_has_prop(receiver, key)
          let use_string =
            match str_value {
              Some(s) => not(has_prop) && i >= 0 && i < s.length()
              None => false
            }
          if has_prop || use_string {
            let value =
              if has_prop {
                self.get_prop_value(receiver, key)
              } else {
                match str_value {
                  Some(s) =>
                    String(try { s[i:i + 1].to_string() } catch { _ => "" })
                  None => Undefined
                }
              }
            let args_array = [
              value,
              Number(i.to_double()),
              receiver,
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
          let has_prop = js_has_prop(receiver, key)
          let use_string =
            match str_value {
              Some(s) => not(has_prop) && i >= 0 && i < s.length()
              None => false
            }
          if has_prop || use_string {
            let value =
              if has_prop {
                self.get_prop_value(receiver, key)
              } else {
                match str_value {
                  Some(s) =>
                    String(try { s[i:i + 1].to_string() } catch { _ => "" })
                  None => Undefined
                }
              }
            let args_array = [
              value,
              Number(i.to_double()),
              receiver,
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
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return Undefined
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let mut i = 0
        while i < len {
          let key = i.to_string()
          let has_prop = js_has_prop(receiver, key)
          let use_string =
            match str_value {
              Some(s) => not(has_prop) && i >= 0 && i < s.length()
              None => false
            }
          if has_prop || use_string {
            let item =
              if has_prop {
                self.get_prop_value(receiver, key)
              } else {
                match str_value {
                  Some(s) =>
                    String(try { s[i:i + 1].to_string() } catch { _ => "" })
                  None => Undefined
                }
              }
            let args_array = [
              item,
              Number(i.to_double()),
              receiver,
            ]
            let found = self.call_function(
              callback,
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
      } else {
        Undefined
      }
    "findIndex" =>
      if args.length() > 0 {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return Number(-1.0)
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let mut i = 0
        while i < len {
          let key = i.to_string()
          let has_prop = js_has_prop(receiver, key)
          let use_string =
            match str_value {
              Some(s) => not(has_prop) && i >= 0 && i < s.length()
              None => false
            }
          if has_prop || use_string {
            let item =
              if has_prop {
                self.get_prop_value(receiver, key)
              } else {
                match str_value {
                  Some(s) =>
                    String(try { s[i:i + 1].to_string() } catch { _ => "" })
                  None => Undefined
                }
              }
            let args_array = [
              item,
              Number(i.to_double()),
              receiver,
            ]
            let found = self.call_function(
              callback,
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
      } else {
        Number(-1.0)
      }
    "findLast" =>
      if args.length() > 0 {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return Undefined
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let mut i = len - 1
        while i >= 0 {
          let key = i.to_string()
          let has_prop = js_has_prop(receiver, key)
          let use_string =
            match str_value {
              Some(s) => not(has_prop) && i >= 0 && i < s.length()
              None => false
            }
          if has_prop || use_string {
            let item =
              if has_prop {
                self.get_prop_value(receiver, key)
              } else {
                match str_value {
                  Some(s) =>
                    String(try { s[i:i + 1].to_string() } catch { _ => "" })
                  None => Undefined
                }
              }
            let args_array = [
              item,
              Number(i.to_double()),
              receiver,
            ]
            let found = self.call_function(
              callback,
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
      } else {
        Undefined
      }
    "findLastIndex" =>
      if args.length() > 0 {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return Number(-1.0)
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let mut i = len - 1
        while i >= 0 {
          let key = i.to_string()
          let has_prop = js_has_prop(receiver, key)
          let use_string =
            match str_value {
              Some(s) => not(has_prop) && i >= 0 && i < s.length()
              None => false
            }
          if has_prop || use_string {
            let item =
              if has_prop {
                self.get_prop_value(receiver, key)
              } else {
                match str_value {
                  Some(s) =>
                    String(try { s[i:i + 1].to_string() } catch { _ => "" })
                  None => Undefined
                }
              }
            let args_array = [
              item,
              Number(i.to_double()),
              receiver,
            ]
            let found = self.call_function(
              callback,
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
      } else {
        Number(-1.0)
      }
    "push" => {
      let mut n = len
      for arg in args {
        self.set_prop_value(receiver, n.to_string(), arg)
        n += 1
      }
      self.set_prop_value(receiver, "length", Number(n.to_double()))
      Number(n.to_double())
    }
    "pop" =>
      if len <= 0 {
        self.set_prop_value(receiver, "length", Number(0.0))
        Undefined
      } else {
        let idx = len - 1
        let key = idx.to_string()
        let value = self.get_prop_value(receiver, key)
        let _ = js_delete_prop(receiver, key)
        self.set_prop_value(receiver, "length", Number(idx.to_double()))
        value
      }
    "shift" =>
      if len <= 0 {
        self.set_prop_value(receiver, "length", Number(0.0))
        Undefined
      } else {
        let first_key = "0"
        let first = self.get_prop_value(receiver, first_key)
        let mut k = 1
        while k < len {
          let from_key = k.to_string()
          let to_key = (k - 1).to_string()
          if js_has_prop(receiver, from_key) {
            let value = self.get_prop_value(receiver, from_key)
            self.set_prop_value(receiver, to_key, value)
          } else {
            let _ = js_delete_prop(receiver, to_key)
          }
          k += 1
        }
        let last_key = (len - 1).to_string()
        let _ = js_delete_prop(receiver, last_key)
        self.set_prop_value(receiver, "length", Number((len - 1).to_double()))
        first
      }
    "unshift" => {
      let insert_count = args.length()
      if insert_count == 0 {
        return Number(len.to_double())
      }
      let mut k = len - 1
      while k >= 0 {
        let from_key = k.to_string()
        let to_key = (k + insert_count).to_string()
        if js_has_prop(receiver, from_key) {
          let value = self.get_prop_value(receiver, from_key)
          self.set_prop_value(receiver, to_key, value)
        } else {
          let _ = js_delete_prop(receiver, to_key)
        }
        if k == 0 {
          break
        }
        k = k - 1
      }
      for i in 0..<insert_count {
        self.set_prop_value(receiver, i.to_string(), args[i])
      }
      let new_len = len + insert_count
      self.set_prop_value(receiver, "length", Number(new_len.to_double()))
      Number(new_len.to_double())
    }
    "slice" => {
      let mut start = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      let mut end = if args.length() > 1 { args[1].to_number().to_int() } else { len }
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
            let has_prop = js_has_prop(receiver, key)
            let use_string =
              match str_value {
                Some(s) => not(has_prop) && i >= 0 && i < s.length()
                None => false
              }
            if has_prop || use_string {
              let value =
                if has_prop {
                  self.get_prop_value(receiver, key)
                } else {
                  match str_value {
                    Some(s) =>
                      String(try { s[i:i + 1].to_string() } catch { _ => "" })
                    None => Undefined
                  }
                }
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
      result.push(receiver)
      present.push(true)
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
    "fill" => {
      let value = if args.length() > 0 { args[0] } else { Undefined }
      let mut start = if args.length() > 1 { args[1].to_number().to_int() } else { 0 }
      let mut end = if args.length() > 2 { args[2].to_number().to_int() } else { len }
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
        self.set_prop_value(receiver, i.to_string(), value)
      }
      self.set_prop_value(receiver, "length", Number(len.to_double()))
      receiver
    }
    "flat" => {
      let depth = if args.length() > 0 { args[0].to_number().to_int() } else { 1 }
      if len <= 0 {
        return js_new_array()
      }
      let items : Array[JSValue] = []
      for i in 0..<len {
        let key = i.to_string()
        let has_prop = js_has_prop(receiver, key)
        let use_string =
          match str_value {
            Some(s) => not(has_prop) && i >= 0 && i < s.length()
            None => false
          }
        if has_prop || use_string {
          let value =
            if has_prop {
              self.get_prop_value(receiver, key)
            } else {
              match str_value {
                Some(s) =>
                  String(try { s[i:i + 1].to_string() } catch { _ => "" })
                None => Undefined
              }
            }
          items.push(value)
        }
      }
      let result : Array[JSValue] = []
      if depth <= 0 {
        for item in items {
          result.push(item)
        }
      } else {
        self.flatten_array_items(items, depth, result)
      }
      js_array_from(result)
    }
    "at" => {
      let mut idx = if args.length() > 0 { args[0].to_number().to_int() } else { 0 }
      if idx < 0 {
        idx = len + idx
      }
      if idx < 0 || idx >= len {
        Undefined
      } else {
        let key = idx.to_string()
        if js_has_prop(receiver, key) {
          self.get_prop_value(receiver, key)
        } else {
          match str_value {
            Some(s) if idx >= 0 && idx < s.length() =>
              String(try { s[idx:idx + 1].to_string() } catch { _ => "" })
            _ => Undefined
          }
        }
      }
    }
    _ => Undefined
  }
}

///|
fn JSInterpreter::eval_script_source(self : JSInterpreter, source : String) -> JSValue {
  self.eval_script_source_with_strict(source, false)
}

///|
fn JSInterpreter::eval_script_source_with_strict(self : JSInterpreter, source : String, inherit_strict : Bool) -> JSValue {
  let block = try {
    @parser.parse_block_from_source_strict(source, inherit_strict)
  } catch {
    @parser.ParseError::ParseError(msg) => {
      let _ = self.set_error_kind("SyntaxError", msg)
      return Undefined
    }
  }
  self.hoist_block(block, self.global_env)
  // Use exec_block_for_eval to properly track completion values
  let result =
    match self.exec_block_for_eval(block, self.global_env) {
      // For break/continue signals, use the completion value with UpdateEmpty
      (Some(BreakSignal(_)), completion) | (Some(ContinueSignal(_)), completion) =>
        match completion {
          Empty => JSValue::Undefined
          _ => completion
        }
      // For other signals (errors, return), return the value
      (Some(val), _) => val
      // Normal completion
      (None, completion) =>
        // Convert Empty to Undefined for final result
        match completion {
          Empty => JSValue::Undefined
          _ => completion
        }
    }
  self.drain_microtasks()
  result
}

///|
///|
fn JSInterpreter::new_array_iterator(self : JSInterpreter, receiver : JSValue) -> JSValue {
  let iter = self.new_object()
  let iterator_ctor = self.global_env.get("Iterator")
  let iterator_proto = js_get_prop(iterator_ctor, "prototype")
  match iterator_proto {
    Object(_) | Function(_) | Array(_) => {
      let _ = js_set_prop(iter, "__proto__", iterator_proto)
    }
    _ => ()
  }
  let _ = js_set_prop(iter, "__iter_target", receiver)
  let _ = js_set_prop(iter, "__iter_index", Number(0.0))
  let next_fn = self.make_native("ArrayIterator.prototype.next")
  self.set_function_length(next_fn, 0.0)
  let _ = js_set_prop(iter, "next", next_fn)
  let iter_fn = self.make_native("Iterator.prototype[@@iterator]")
  self.set_function_length(iter_fn, 0.0)
  let _ = js_set_prop(iter, "@@iterator", iter_fn)
  iter
}

///|
fn JSInterpreter::new_string_iterator(self : JSInterpreter, value : String) -> JSValue {
  let iter = self.new_object()
  let iterator_ctor = self.global_env.get("Iterator")
  let iterator_proto = js_get_prop(iterator_ctor, "prototype")
  match iterator_proto {
    Object(_) | Function(_) | Array(_) => {
      let _ = js_set_prop(iter, "__proto__", iterator_proto)
    }
    _ => ()
  }
  let _ = js_set_prop(iter, "__iter_string", JSValue::String(value))
  let _ = js_set_prop(iter, "__iter_index", Number(0.0))
  let next_fn = self.make_native("StringIterator.prototype.next")
  self.set_function_length(next_fn, 0.0)
  let _ = js_set_prop(iter, "next", next_fn)
  let iter_fn = self.make_native("Iterator.prototype[@@iterator]")
  self.set_function_length(iter_fn, 0.0)
  let _ = js_set_prop(iter, "@@iterator", iter_fn)
  iter
}

///|
fn JSInterpreter::own_property_keys(_self : JSInterpreter, obj : JSValue) -> Array[String] {
  let keys : Array[String] = []
  match obj {
    Function(closure) =>
      for prop in closure.props {
        keys.push(prop.key)
      }
    Object(map) =>
      for prop in map.props {
        keys.push(prop.key)
      }
    Array(arr) => {
      let mut i = 0
      while i < arr.items.length() {
        if arr.present[i] {
          keys.push(i.to_string())
        }
        i += 1
      }
      for prop in arr.props {
        keys.push(prop.key)
      }
      keys.push("length")
    }
    String(s) => {
      let mut i = 0
      while i < s.length() {
        keys.push(i.to_string())
        i += 1
      }
      keys.push("length")
    }
    _ => ()
  }
  keys
}

///|
fn JSInterpreter::lookup_own_prop(
  _self : JSInterpreter,
  obj : JSValue,
  key : String,
) -> JSProp? {
  match obj {
    Function(closure) => {
      for prop in closure.props {
        if prop.key == key {
          return Some(prop)
        }
      }
      None
    }
    Object(map) => {
      for prop in map.props {
        if prop.key == key {
          return Some(prop)
        }
      }
      None
    }
    Array(arr) =>
      if key == "length" {
        Some({
          key,
          value: Number(arr.length.to_double()),
          writable: true,
          enumerable: false,
          configurable: false,
          get: None,
          set: None,
        })
      } else {
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        if idx >= 0 && idx < arr.items.length() && arr.present[idx] {
          Some({
            key,
            value: arr.items[idx],
            writable: true,
            enumerable: true,
            configurable: true,
            get: None,
            set: None,
          })
        } else {
          for prop in arr.props {
            if prop.key == key {
              return Some(prop)
            }
          }
          None
        }
      }
    String(s) =>
      if key == "length" {
        Some({
          key,
          value: Number(s.length().to_double()),
          writable: false,
          enumerable: false,
          configurable: false,
          get: None,
          set: None,
        })
      } else {
        let idx = @strconv.parse_int(key) catch { _ => -1 }
        if idx >= 0 && idx < s.length() {
          let ch = JSValue::String(try { s[idx:idx + 1].to_string() } catch { _ => "" })
          Some({
            key,
            value: ch,
            writable: false,
            enumerable: true,
            configurable: false,
            get: None,
            set: None,
          })
        } else {
          None
        }
      }
    _ => None
  }
}

///|
fn JSInterpreter::define_property(
  self : JSInterpreter,
  target : JSValue,
  key : String,
  desc : JSValue,
) -> JSValue {
  if self.is_proxy(target) {
    return self.proxy_define_property(target, key, desc)
  }
  let is_obj = match desc {
    Object(_) | Function(_) => true
    _ => false
  }
  if not(is_obj) {
    return self.set_error_kind(
      "TypeError",
      "Property description must be an object",
    )
  }
  let has_get = self.has_own_prop(desc, "get")
  let has_set = self.has_own_prop(desc, "set")
  let has_value = self.has_own_prop(desc, "value")
  let has_writable = self.has_own_prop(desc, "writable")
  if (has_get || has_set) && (has_value || has_writable) {
    return self.set_error_kind(
      "TypeError",
      "Invalid property descriptor",
    )
  }
  let current = self.lookup_own_prop(target, key)
  let enumerable = if self.has_own_prop(desc, "enumerable") {
    self.get_prop_value(desc, "enumerable").to_boolean()
  } else {
    match current {
      Some(prop) => prop.enumerable
      None => false
    }
  }
  let configurable = if self.has_own_prop(desc, "configurable") {
    self.get_prop_value(desc, "configurable").to_boolean()
  } else {
    match current {
      Some(prop) => prop.configurable
      None => false
    }
  }
  if has_get || has_set {
    let get_val =
      if has_get {
        self.get_prop_value(desc, "get")
      } else {
        match current {
          Some(prop) => match prop.get {
            Some(g) => g
            None => Undefined
          }
          None => Undefined
        }
      }
    let set_val =
      if has_set {
        self.get_prop_value(desc, "set")
      } else {
        match current {
          Some(prop) => match prop.set {
            Some(s) => s
            None => Undefined
          }
          None => Undefined
        }
      }
    if not(get_val.is_undefined()) && not(self.is_callable(get_val)) {
      return self.set_error_kind("TypeError", "Getter must be callable")
    }
    if not(set_val.is_undefined()) && not(self.is_callable(set_val)) {
      return self.set_error_kind("TypeError", "Setter must be callable")
    }
    let getter = match get_val {
      Undefined => None
      _ => Some(get_val)
    }
    let setter = match set_val {
      Undefined => None
      _ => Some(set_val)
    }
    let _ =
      js_define_accessor_prop(
        target,
        key,
        getter,
        setter,
        enumerable,
        configurable,
      )
    target
  } else {
    let value =
      if has_value {
        self.get_prop_value(desc, "value")
      } else {
        match current {
          Some(prop) => prop.value
          None => Undefined
        }
      }
    let writable = if has_writable {
      self.get_prop_value(desc, "writable").to_boolean()
    } else {
      match current {
        Some(prop) => prop.writable
        None => false
      }
    }
    let _ =
      js_define_data_prop(target, key, value, writable, enumerable, configurable)
    target
  }
}

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
fn escape_string_value(value : String) -> String {
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
fn unescape_string_value(value : String) -> String {
  let sb = StringBuilder::new()
  let len = value.length()
  let percent : UInt16 = '%'
  let u_char : UInt16 = 'u'
  let mut k = 0
  while k < len {
    let unit = value[k]
    if unit == percent {
      if k + 5 < len && value[k + 1] == u_char {
        match (
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

///|
fn is_leap_year(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
}

///|
fn days_in_year(year : Int) -> Int {
  if is_leap_year(year) { 366 } else { 365 }
}

///|
fn days_in_month(year : Int, month : Int) -> Int {
  match month {
    0 => 31
    1 => if is_leap_year(year) { 29 } else { 28 }
    2 => 31
    3 => 30
    4 => 31
    5 => 30
    6 => 31
    7 => 31
    8 => 30
    9 => 31
    10 => 30
    11 => 31
    _ => 30
  }
}

///|
fn floor_div(a : Int, b : Int) -> Int {
  if b == 0 {
    0
  } else if a >= 0 {
    a / b
  } else {
    -(((-a + b - 1) / b))
  }
}

///|
fn days_before_year(year : Int) -> Int {
  let mut days = 0
  if year >= 1970 {
    let mut y = 1970
    while y < year {
      days += days_in_year(y)
      y += 1
    }
  } else {
    let mut y = year
    while y < 1970 {
      days -= days_in_year(y)
      y += 1
    }
  }
  days
}

///|
fn days_before_month(year : Int, month : Int) -> Int {
  let mut days = 0
  let mut m = 0
  while m < month {
    days += days_in_month(year, m)
    m += 1
  }
  days
}

///|
fn make_date_time(
  year : Int,
  month : Int,
  date : Int,
  hour : Int,
  minute : Int,
  second : Int,
  ms : Int,
) -> Double {
  let q = floor_div(month, 12)
  let mut y = year + q
  let mut m = month - q * 12
  if m < 0 {
    m += 12
    y -= 1
  }
  let day = days_before_year(y) + days_before_month(y, m) + (date - 1)
  let time_ms =
    (((hour * 60 + minute) * 60 + second) * 1000 + ms)
  day.to_double() * 86400000.0 + time_ms.to_double()
}

///|
fn break_time(t : Double) -> (Int, Int, Int, Int, Int, Int, Int) {
  let day = (t / 86400000.0).floor()
  let mut days = day.to_int()
  let time_ms = t - day * 86400000.0
  let time_ms_int = time_ms.to_int()
  let mut year = 1970
  if days >= 0 {
    while days >= days_in_year(year) {
      days -= days_in_year(year)
      year += 1
    }
  } else {
    year = 1969
    while days < 0 {
      days += days_in_year(year)
      year -= 1
    }
    year += 1
  }
  let mut month = 0
  while days >= days_in_month(year, month) {
    days -= days_in_month(year, month)
    month += 1
  }
  let day = days + 1
  let hour = time_ms_int / 3600000
  let mut rem = time_ms_int - hour * 3600000
  let minute = rem / 60000
  rem = rem - minute * 60000
  let second = rem / 1000
  let milli = rem - second * 1000
  (year, month, day, hour, minute, second, milli)
}

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
fn JSInterpreter::date_time_value(self : JSInterpreter, this_arg : JSValue) -> Double? {
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

///|
fn JSInterpreter::call_native(
  self : JSInterpreter,
  name : String,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  if name.has_prefix("Array.prototype") {
    let mut method_name = (try { name[15:] } catch { _ => "" }).to_string()
    if method_name.has_prefix(".") {
      method_name = (try { method_name[1:] } catch { _ => "" }).to_string()
    }
    if method_name == "[@@iterator]" {
      method_name = "@@iterator"
    }
    let receiver = match this_arg {
      Undefined | Null =>
        return self.set_error_kind(
          "TypeError",
          "Array.prototype." + method_name + " called on null or undefined",
        )
      Bool(_) | Number(_) | String(_) => self.wrap_primitive(self.global_env, this_arg)
      _ => this_arg
    }
    if method_name == "@@iterator" {
      return self.new_array_iterator(receiver)
    }
    match receiver {
      Array(arr) => return self.array_method(arr, method_name, args)
      _ => return self.array_like_method(receiver, method_name, args)
    }
  }
  if name.has_prefix("String.prototype") {
    let mut method_name = (try { name[16:] } catch { _ => "" }).to_string()
    if method_name.has_prefix(".") {
      method_name = (try { method_name[1:] } catch { _ => "" }).to_string()
    }
    if method_name == "[@@iterator]" {
      method_name = "@@iterator"
    }
    match this_arg {
      Undefined | Null =>
        return self.set_error_kind(
          "TypeError",
          "String.prototype." + method_name + " called on null or undefined",
        )
      _ => {
        let s =
          match this_arg {
            String(value) => value
            Object(_) | Array(_) | Function(_) =>
              match js_get_prop(this_arg, "value") {
                String(value) => value
                Number(n) => n.to_string()
                Bool(true) => "true"
                Bool(false) => "false"
                _ => self.to_string_value(this_arg)
              }
            _ => this_arg.to_js_string()
          }
        if method_name == "@@iterator" {
          return self.new_string_iterator(s)
        }
        return self.string_method(s, method_name, args)
      }
    }
  }
  match name {
    "Promise" =>
      self.set_error_kind(
        "TypeError",
        "Promise constructor must be called with new",
      )
    "Promise.resolve" => {
      let value = if args.length() > 0 { args[0] } else { Undefined }
      match this_arg {
        Object(_) | Function(_) => self.promise_static_resolve_with_ctor(this_arg, value)
        _ =>
          self.set_error_kind(
            "TypeError",
            "Promise.resolve called on non-object",
          )
      }
    }
    "Promise.reject" => {
      let reason = if args.length() > 0 { args[0] } else { Undefined }
      match this_arg {
        Object(_) | Function(_) => self.promise_static_reject_with_ctor(this_arg, reason)
        _ =>
          self.set_error_kind(
            "TypeError",
            "Promise.reject called on non-object",
          )
      }
    }
    "Promise.prototype.then" => {
      if not(self.is_promise(this_arg)) {
        return self.set_error_kind(
          "TypeError",
          "Promise.prototype.then called on non-Promise",
        )
      }
      let on_fulfilled = if args.length() > 0 { args[0] } else { Undefined }
      let on_rejected = if args.length() > 1 { args[1] } else { Undefined }
      let ctor = self.promise_species_constructor(this_arg)
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      let (result_promise, _resolve, _reject) = self.promise_new_capability(ctor)
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      self.perform_promise_then(this_arg, on_fulfilled, on_rejected, result_promise)
    }
    "Promise.prototype.catch" => {
      let on_rejected = if args.length() > 0 { args[0] } else { Undefined }
      let target = match this_arg {
        Undefined | Null =>
          return self.set_error_kind(
            "TypeError",
            "Promise.prototype.catch called on null or undefined",
          )
        Bool(_) | Number(_) | String(_) => self.wrap_primitive(self.global_env, this_arg)
        _ => this_arg
      }
      let then_method = self.get_prop_value(target, "then")
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      if not(self.is_callable(then_method)) {
        return self.set_error_kind("TypeError", "Promise.prototype.catch called on non-callable then")
      }
      self.call_function(then_method, this_arg, [Undefined, on_rejected])
    }
    "Promise.prototype.finally" => {
      let on_finally = if args.length() > 0 { args[0] } else { Undefined }
      let target = match this_arg {
        Undefined | Null =>
          return self.set_error_kind(
            "TypeError",
            "Promise.prototype.finally called on null or undefined",
          )
        Bool(_) | Number(_) | String(_) => self.wrap_primitive(self.global_env, this_arg)
        _ => this_arg
      }
      let then_method = self.get_prop_value(target, "then")
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      if not(self.is_callable(then_method)) {
        return self.set_error_kind("TypeError", "Promise.prototype.finally called on non-callable then")
      }
      if not(self.is_callable(on_finally)) {
        return self.call_function(then_method, this_arg, [on_finally, on_finally])
      }
      let ctor = self.promise_species_constructor(this_arg)
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      let fulfill_handler = self.make_bound_native(
        "Promise.__finally_fulfill__",
        [on_finally, ctor],
      )
      let reject_handler = self.make_bound_native(
        "Promise.__finally_reject__",
        [on_finally, ctor],
      )
      self.call_function(then_method, this_arg, [fulfill_handler, reject_handler])
    }
    "Promise.withResolvers" => {
      match this_arg {
        Object(_) | Function(_) => self.promise_with_resolvers(this_arg)
        _ =>
          self.set_error_kind(
            "TypeError",
            "Promise.withResolvers called on non-object",
          )
      }
    }
    "Promise.try" => {
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      let rest_args : Array[JSValue] = []
      if args.length() > 1 {
        let mut i = 1
        while i < args.length() {
          rest_args.push(args[i])
          i = i + 1
        }
      }
      match this_arg {
        Object(_) | Function(_) =>
          if not(self.is_constructor(this_arg)) {
            self.set_error_kind("TypeError", "Promise.try called on non-constructor")
          } else {
            self.promise_try(this_arg, callback, rest_args)
          }
        _ => self.set_error_kind("TypeError", "Promise.try called on non-object")
      }
    }
    "Promise[@@species]" => this_arg
    "Proxy" => {
      let _ = self.set_error_kind("TypeError", "Proxy must be called with new")
      Undefined
    }
    "Promise.__resolve__" => {
      let promise = if args.length() > 0 { args[0] } else { Undefined }
      let value = if args.length() > 1 { args[1] } else { Undefined }
      if self.is_promise(promise) {
        self.promise_resolve_value(promise, value)
      }
      Undefined
    }
    "Promise.__reject__" => {
      let promise = if args.length() > 0 { args[0] } else { Undefined }
      let reason = if args.length() > 1 { args[1] } else { Undefined }
      if self.is_promise(promise) {
        self.promise_reject(promise, reason)
      }
      Undefined
    }
    "Promise.__resolve_once__" => {
      let token = if args.length() > 0 { args[0] } else { Undefined }
      let promise = if args.length() > 1 { args[1] } else { Undefined }
      let value = if args.length() > 2 { args[2] } else { Undefined }
      match token {
        Object(_) | Function(_) | Array(_) =>
          match js_get_prop(token, "__promise_once") {
            Bool(true) => ()
            _ => {
              let _ = js_set_prop(token, "__promise_once", Bool(true))
              if self.is_promise(promise) {
                self.promise_resolve_value(promise, value)
              }
            }
          }
        _ => ()
      }
      Undefined
    }
    "Promise.__reject_once__" => {
      let token = if args.length() > 0 { args[0] } else { Undefined }
      let promise = if args.length() > 1 { args[1] } else { Undefined }
      let reason = if args.length() > 2 { args[2] } else { Undefined }
      match token {
        Object(_) | Function(_) | Array(_) =>
          match js_get_prop(token, "__promise_once") {
            Bool(true) => ()
            _ => {
              let _ = js_set_prop(token, "__promise_once", Bool(true))
              if self.is_promise(promise) {
                self.promise_reject(promise, reason)
              }
            }
          }
        _ => ()
      }
      Undefined
    }
    "Promise.__cap_executor__" => {
      let cap = if args.length() > 0 { args[0] } else { Undefined }
      let resolve = if args.length() > 1 { args[1] } else { Undefined }
      let reject = if args.length() > 2 { args[2] } else { Undefined }
      match cap {
        Object(_) | Function(_) | Array(_) => {
          let cur_resolve = js_get_prop(cap, "resolve")
          let cur_reject = js_get_prop(cap, "reject")
          if not(cur_resolve.is_undefined()) || not(cur_reject.is_undefined()) {
            return self.set_error_kind("TypeError", "Promise capability already initialized")
          }
          let _ = js_set_prop(cap, "resolve", resolve)
          let _ = js_set_prop(cap, "reject", reject)
        }
        _ => ()
      }
      Undefined
    }
    "Promise.__return_value__" => {
      if args.length() > 0 { args[0] } else { Undefined }
    }
    "Promise.__throw_reason__" => {
      let reason = if args.length() > 0 { args[0] } else { Undefined }
      self.last_error = Some(reason)
      reason
    }
    "Promise.__finally_fulfill__" => {
      let on_finally = if args.length() > 0 { args[0] } else { Undefined }
      let ctor = if args.length() > 1 { args[1] } else { self.global_env.get("Promise") }
      let value = if args.length() > 2 { args[2] } else { Undefined }
      if self.is_callable(on_finally) {
        let result = self.call_function(on_finally, Undefined, [])
        match self.peek_error() {
          Some(err) => {
            self.last_error = None
            self.last_error = Some(err)
            return err
          }
          None => {
            let result_promise = self.promise_static_resolve_with_ctor(ctor, result)
            let returner = self.make_bound_native("Promise.__return_value__", [value])
            return self.promise_then(result_promise, returner, Undefined)
          }
        }
      }
      value
    }
    "Promise.__finally_reject__" => {
      let on_finally = if args.length() > 0 { args[0] } else { Undefined }
      let ctor = if args.length() > 1 { args[1] } else { self.global_env.get("Promise") }
      let reason = if args.length() > 2 { args[2] } else { Undefined }
      if self.is_callable(on_finally) {
        let result = self.call_function(on_finally, Undefined, [])
        match self.peek_error() {
          Some(err) => {
            self.last_error = None
            self.last_error = Some(err)
            return err
          }
          None => {
            let result_promise = self.promise_static_resolve_with_ctor(ctor, result)
            let thrower = self.make_bound_native("Promise.__throw_reason__", [reason])
            return self.promise_then(result_promise, thrower, Undefined)
          }
        }
      }
      self.last_error = Some(reason)
      reason
    }
    "Promise.__all_fulfill__" => {
      let state = if args.length() > 0 { args[0] } else { Undefined }
      let index = if args.length() > 1 { args[1].to_number().to_int() } else { 0 }
      let already = if args.length() > 2 { args[2] } else { Undefined }
      let value = if args.length() > 3 { args[3] } else { Undefined }
      match already {
        Object(_) | Function(_) | Array(_) =>
          match js_get_prop(already, "__promise_once") {
            Bool(true) => return Undefined
            _ => {
              let _ = js_set_prop(already, "__promise_once", Bool(true))
            }
          }
        _ => ()
      }
      let remaining = match js_get_prop(state, "__all_remaining") {
        Number(n) => n.to_int()
        _ => 0
      }
      if remaining <= 0 {
        return Undefined
      }
      let results = js_get_prop(state, "__all_results")
      let _ = self.set_prop_value(results, index.to_string(), value)
      let next = remaining - 1
      let _ = js_set_prop(state, "__all_remaining", Number(next.to_double()))
      if next == 0 {
        let resolve = js_get_prop(state, "__all_resolve")
        let _ = self.call_function(resolve, Undefined, [results])
      }
      Undefined
    }
    "Promise.__all_reject__" => {
      let state = if args.length() > 0 { args[0] } else { Undefined }
      let already = if args.length() > 2 { args[2] } else { Undefined }
      let reason = if args.length() > 3 { args[3] } else { Undefined }
      match already {
        Object(_) | Function(_) | Array(_) =>
          match js_get_prop(already, "__promise_once") {
            Bool(true) => return Undefined
            _ => {
              let _ = js_set_prop(already, "__promise_once", Bool(true))
            }
          }
        _ => ()
      }
      let remaining = match js_get_prop(state, "__all_remaining") {
        Number(n) => n.to_int()
        _ => 0
      }
      if remaining <= 0 {
        return Undefined
      }
      let _ = js_set_prop(state, "__all_remaining", Number(0.0))
      let reject = js_get_prop(state, "__all_reject")
      let _ = self.call_function(reject, Undefined, [reason])
      Undefined
    }
    "Promise.__all_settled_fulfill__" => {
      let state = if args.length() > 0 { args[0] } else { Undefined }
      let index = if args.length() > 1 { args[1].to_number().to_int() } else { 0 }
      let already = if args.length() > 2 { args[2] } else { Undefined }
      let value = if args.length() > 3 { args[3] } else { Undefined }
      match already {
        Object(_) | Function(_) | Array(_) =>
          match js_get_prop(already, "__promise_once") {
            Bool(true) => return Undefined
            _ => {
              let _ = js_set_prop(already, "__promise_once", Bool(true))
            }
          }
        _ => ()
      }
      let remaining = match js_get_prop(state, "__all_remaining") {
        Number(n) => n.to_int()
        _ => 0
      }
      if remaining <= 0 {
        return Undefined
      }
      let entry = self.new_object()
      let _ = js_set_prop(entry, "status", String("fulfilled"))
      let _ = js_set_prop(entry, "value", value)
      let results = js_get_prop(state, "__all_results")
      let _ = self.set_prop_value(results, index.to_string(), entry)
      let next = remaining - 1
      let _ = js_set_prop(state, "__all_remaining", Number(next.to_double()))
      if next == 0 {
        let resolve = js_get_prop(state, "__all_resolve")
        let _ = self.call_function(resolve, Undefined, [results])
      }
      Undefined
    }
    "Promise.__all_settled_reject__" => {
      let state = if args.length() > 0 { args[0] } else { Undefined }
      let index = if args.length() > 1 { args[1].to_number().to_int() } else { 0 }
      let already = if args.length() > 2 { args[2] } else { Undefined }
      let reason = if args.length() > 3 { args[3] } else { Undefined }
      match already {
        Object(_) | Function(_) | Array(_) =>
          match js_get_prop(already, "__promise_once") {
            Bool(true) => return Undefined
            _ => {
              let _ = js_set_prop(already, "__promise_once", Bool(true))
            }
          }
        _ => ()
      }
      let remaining = match js_get_prop(state, "__all_remaining") {
        Number(n) => n.to_int()
        _ => 0
      }
      if remaining <= 0 {
        return Undefined
      }
      let entry = self.new_object()
      let _ = js_set_prop(entry, "status", String("rejected"))
      let _ = js_set_prop(entry, "reason", reason)
      let results = js_get_prop(state, "__all_results")
      let _ = self.set_prop_value(results, index.to_string(), entry)
      let next = remaining - 1
      let _ = js_set_prop(state, "__all_remaining", Number(next.to_double()))
      if next == 0 {
        let resolve = js_get_prop(state, "__all_resolve")
        let _ = self.call_function(resolve, Undefined, [results])
      }
      Undefined
    }
    "Promise.__any_reject__" => {
      let state = if args.length() > 0 { args[0] } else { Undefined }
      let index = if args.length() > 1 { args[1].to_number().to_int() } else { 0 }
      let already = if args.length() > 2 { args[2] } else { Undefined }
      let reason = if args.length() > 3 { args[3] } else { Undefined }
      match already {
        Object(_) | Function(_) | Array(_) =>
          match js_get_prop(already, "__promise_once") {
            Bool(true) => return Undefined
            _ => {
              let _ = js_set_prop(already, "__promise_once", Bool(true))
            }
          }
        _ => ()
      }
      let remaining = match js_get_prop(state, "__any_remaining") {
        Number(n) => n.to_int()
        _ => 0
      }
      if remaining <= 0 {
        return Undefined
      }
      let errors = js_get_prop(state, "__any_errors")
      let _ = self.set_prop_value(errors, index.to_string(), reason)
      let next = remaining - 1
      let _ = js_set_prop(state, "__any_remaining", Number(next.to_double()))
      if next == 0 {
        let reject = js_get_prop(state, "__any_reject")
        let err = self.make_aggregate_error(errors)
        let _ = self.call_function(reject, Undefined, [err])
      }
      Undefined
    }
    "Promise.__race_resolve__" => {
      let promise = if args.length() > 0 { args[0] } else { Undefined }
      let value = if args.length() > 1 { args[1] } else { Undefined }
      if self.is_promise(promise) && self.promise_state(promise) == "pending" {
        self.promise_resolve_value(promise, value)
      }
      Undefined
    }
    "Promise.__race_reject__" => {
      let promise = if args.length() > 0 { args[0] } else { Undefined }
      let reason = if args.length() > 1 { args[1] } else { Undefined }
      if self.is_promise(promise) && self.promise_state(promise) == "pending" {
        self.promise_reject(promise, reason)
      }
      Undefined
    }
    "Promise.all" => {
      let iter = if args.length() > 0 { args[0] } else { Undefined }
      match this_arg {
        Object(_) | Function(_) => self.promise_all_with_ctor(this_arg, iter, false)
        _ =>
          self.set_error_kind(
            "TypeError",
            "Promise.all called on non-object",
          )
      }
    }
    "Promise.race" => {
      let iter = if args.length() > 0 { args[0] } else { Undefined }
      match this_arg {
        Object(_) | Function(_) => self.promise_race_with_ctor(this_arg, iter)
        _ =>
          self.set_error_kind(
            "TypeError",
            "Promise.race called on non-object",
          )
      }
    }
    "Promise.allSettled" => {
      let iter = if args.length() > 0 { args[0] } else { Undefined }
      match this_arg {
        Object(_) | Function(_) => self.promise_all_with_ctor(this_arg, iter, true)
        _ =>
          self.set_error_kind(
            "TypeError",
            "Promise.allSettled called on non-object",
          )
      }
    }
    "Promise.any" => {
      let iter = if args.length() > 0 { args[0] } else { Undefined }
      match this_arg {
        Object(_) | Function(_) => self.promise_any_with_ctor(this_arg, iter)
        _ =>
          self.set_error_kind(
            "TypeError",
            "Promise.any called on non-object",
          )
      }
    }
    "queueMicrotask" => {
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if not(self.is_callable(callback)) {
        return self.set_error_kind("TypeError", "queueMicrotask callback is not callable")
      }
      self.microtasks.push({
        handler: callback,
        argument: Undefined,
        promise: None,
        is_reject: false,
      })
      Undefined
    }
    "Object" =>
      if args.length() == 0 {
        self.new_object()
      } else {
        let val = args[0]
        match val {
          Object(_) | Function(_) | Array(_) => val
          _ => {
            let obj = self.new_object()
            let _ = js_set_prop(obj, "value", val)
            obj
          }
        }
      }
    "Object.create" => {
      let proto = if args.length() > 0 { args[0] } else { Undefined }
      match proto {
        Null => js_new_object_with_proto(None)
        Object(_) | Function(_) | Array(_) => js_new_object_with_proto(Some(proto))
        _ => self.new_object()
      }
    }
    "Object.getPrototypeOf" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      if self.is_proxy(target) {
        return self.proxy_get_prototype_of(target)
      }
      match target {
        Object(map) => match map.prototype {
          Some(p) => p
          None => Null
        }
        Function(closure) => match closure.object_proto {
          Some(p) => p
          None => Null
        }
        Array(arr) => match arr.prototype {
          Some(p) => p
          None => Null
        }
        _ => Undefined
      }
    }
    "Object.getOwnPropertyDescriptor" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let raw_key = if args.length() > 1 { args[1].to_js_string() } else { "" }
      let key = self.normalize_prop_key(raw_key)
      if self.is_proxy(target) {
        return self.proxy_get_own_property_descriptor(target, key)
      }
      match target {
        Function(closure) => {
          for prop in closure.props {
            if prop.key == key {
              if prop.get is Some(_) || prop.set is Some(_) {
                return self.make_accessor_descriptor(
                  prop.get,
                  prop.set,
                  prop.enumerable,
                  prop.configurable,
                )
              } else {
                return self.make_data_descriptor(
                  prop.value,
                  prop.writable,
                  prop.enumerable,
                  prop.configurable,
                )
              }
            }
          }
          Undefined
        }
        Object(map) => {
          for prop in map.props {
            if prop.key == key {
              if prop.get is Some(_) || prop.set is Some(_) {
                return self.make_accessor_descriptor(
                  prop.get,
                  prop.set,
                  prop.enumerable,
                  prop.configurable,
                )
              } else {
                return self.make_data_descriptor(
                  prop.value,
                  prop.writable,
                  prop.enumerable,
                  prop.configurable,
                )
              }
            }
          }
          Undefined
        }
        Array(arr) =>
          if key == "length" {
            self.make_data_descriptor(
              Number(arr.length.to_double()),
              true,
              false,
              false,
            )
          } else {
            let idx = @strconv.parse_int(key) catch { _ => -1 }
            if idx >= 0 && idx < arr.items.length() && arr.present[idx] {
              self.make_data_descriptor(arr.items[idx], true, true, true)
            } else {
              for prop in arr.props {
                if prop.key == key {
                  if prop.get is Some(_) || prop.set is Some(_) {
                    return self.make_accessor_descriptor(
                      prop.get,
                      prop.set,
                      prop.enumerable,
                      prop.configurable,
                    )
                  } else {
                    return self.make_data_descriptor(
                      prop.value,
                      prop.writable,
                      prop.enumerable,
                      prop.configurable,
                    )
                  }
                }
              }
              Undefined
            }
          }
        String(s) =>
          if key == "length" {
            self.make_data_descriptor(
              Number(s.length().to_double()),
              false,
              false,
              false,
            )
          } else {
            let idx = @strconv.parse_int(key) catch { _ => -1 }
            if idx >= 0 && idx < s.length() {
              let ch = JSValue::String(try { s[idx:idx + 1].to_string() } catch { _ => "" })
              self.make_data_descriptor(ch, false, true, false)
            } else {
              Undefined
            }
          }
        _ => Undefined
      }
    }
    "Object.defineProperties" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let props = if args.length() > 1 { args[1] } else { Undefined }
      let receiver = match target {
        Undefined | Null =>
          return self.set_error_kind(
            "TypeError",
            "Object.defineProperties called on null or undefined",
          )
        Object(_) | Function(_) | Array(_) => target
        _ =>
          return self.set_error_kind(
            "TypeError",
            "Object.defineProperties called on non-object",
          )
      }
      match props {
        Object(_) | Function(_) | Array(_) => {
          let keys = self.own_property_keys(props)
          for key in keys {
            let desc = self.get_prop_value(props, key)
            match self.peek_error() {
              Some(err) => return err
              None => ()
            }
            let _ = self.define_property(receiver, key, desc)
            match self.peek_error() {
              Some(err) => return err
              None => ()
            }
          }
          receiver
        }
        _ => receiver
      }
    }
    "Object.defineProperty" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let raw_key = if args.length() > 1 { args[1].to_js_string() } else { "" }
      let key = self.normalize_prop_key(raw_key)
      let desc = if args.length() > 2 { args[2] } else { Undefined }
      let receiver = match target {
        Undefined | Null =>
          return self.set_error_kind(
            "TypeError",
            "Object.defineProperty called on null or undefined",
          )
        Object(_) | Function(_) | Array(_) => target
        _ =>
          return self.set_error_kind(
            "TypeError",
            "Object.defineProperty called on non-object",
          )
      }
      let _ = self.define_property(receiver, key, desc)
      match self.peek_error() {
        Some(err) => err
        None => receiver
      }
    }
    "Object.setPrototypeOf" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let proto = if args.length() > 1 { args[1] } else { Undefined }
      match target {
        Object(_) | Function(_) | Array(_) => ()
        _ =>
          return self.set_error_kind(
            "TypeError",
            "Object.setPrototypeOf called on non-object",
          )
      }
      match proto {
        Object(_) | Function(_) | Array(_) | Null => ()
        _ =>
          return self.set_error_kind(
            "TypeError",
            "Object.setPrototypeOf called with invalid prototype",
          )
      }
      let _ = js_set_prop(target, "__proto__", proto)
      target
    }
    "Iterator.prototype[@@iterator]" => this_arg
    "Iterator.from" => self.iterator_from(this_arg, args)
    "Iterator.prototype.map" => self.iterator_map(this_arg, args)
    "Iterator.prototype.filter" => self.iterator_filter(this_arg, args)
    "Iterator.prototype.take" => self.iterator_take(this_arg, args)
    "Iterator.prototype.drop" => self.iterator_drop(this_arg, args)
    "Iterator.prototype.flatMap" => self.iterator_flat_map(this_arg, args)
    "Iterator.prototype.forEach" => self.iterator_for_each(this_arg, args)
    "Iterator.prototype.toArray" => self.iterator_to_array(this_arg, args)
    "Iterator.prototype.reduce" => self.iterator_reduce(this_arg, args)
    "Iterator.prototype.every" => self.iterator_every(this_arg, args)
    "Iterator.prototype.some" => self.iterator_some(this_arg, args)
    "Iterator.prototype.find" => self.iterator_find(this_arg, args)
    "IteratorHelper.prototype.next" => self.iterator_helper_next(this_arg, args)
    "IteratorHelper.prototype.return" => self.iterator_helper_return(this_arg, args)
    "IteratorHelper.prototype.throw" => self.iterator_helper_throw(this_arg, args)
    "ArrayIterator.prototype.next" => {
      let target = js_get_prop(this_arg, "__iter_target")
      let idx_val = js_get_prop(this_arg, "__iter_index")
      let idx = idx_val.to_number().to_int()
      let len = self.array_like_length(target)
      if idx >= len {
        let _ = js_set_prop(this_arg, "__iter_index", Number(len.to_double()))
        self.make_iter_result(Undefined, true)
      } else {
        let value = self.get_prop_value(target, idx.to_string())
        let _ = js_set_prop(this_arg, "__iter_index", Number((idx + 1).to_double()))
        self.make_iter_result(value, false)
      }
    }
    "StringIterator.prototype.next" => {
      let str_val = js_get_prop(this_arg, "__iter_string")
      let s = match str_val {
        String(value) => value
        _ => ""
      }
      let idx_val = js_get_prop(this_arg, "__iter_index")
      let idx = idx_val.to_number().to_int()
      if idx >= s.length() {
        let _ = js_set_prop(this_arg, "__iter_index", Number(s.length().to_double()))
        self.make_iter_result(Undefined, true)
      } else {
        let cu1 = s[idx]
        let (next_idx, chunk) =
          if cu1.is_leading_surrogate() && idx + 1 < s.length() {
            let cu2 = s[idx + 1]
            if cu2.is_trailing_surrogate() {
              let str = try { s[idx:idx + 2].to_string() } catch { _ => "" }
              (idx + 2, str)
            } else {
              let str = try { s[idx:idx + 1].to_string() } catch { _ => "" }
              (idx + 1, str)
            }
          } else {
            let str = try { s[idx:idx + 1].to_string() } catch { _ => "" }
            (idx + 1, str)
          }
        let _ = js_set_prop(this_arg, "__iter_index", Number(next_idx.to_double()))
        self.make_iter_result(JSValue::String(chunk), false)
      }
    }
    "IsHTMLDDA" => Null
    "Object.hasOwnProperty" => {
      let key = if args.length() > 0 { args[0].to_js_string() } else { "" }
      match this_arg {
        Object(map) => {
          for prop in map.props {
            if prop.key == key {
              return Bool(true)
            }
          }
          Bool(false)
        }
        Function(closure) => {
          for prop in closure.props {
            if prop.key == key {
              return Bool(true)
            }
          }
          Bool(false)
        }
        Array(arr) =>
          if key == "length" {
            Bool(true)
          } else {
            let idx = @strconv.parse_int(key) catch { _ => -1 }
            if idx >= 0 && idx < arr.items.length() && arr.present[idx] {
              Bool(true)
            } else {
              let mut found = false
              for prop in arr.props {
                if prop.key == key {
                  found = true
                  break
                }
              }
              Bool(found)
            }
          }
        String(s) =>
          if key == "length" {
            Bool(true)
          } else {
            let idx = @strconv.parse_int(key) catch { _ => -1 }
            Bool(idx >= 0 && idx < s.length())
          }
        _ => Bool(false)
      }
    }
    "Object.prototype.propertyIsEnumerable" => {
      let key = if args.length() > 0 { args[0].to_js_string() } else { "" }
      if self.has_own_prop(this_arg, key) {
        Bool(self.is_enumerable(this_arg, key))
      } else {
        Bool(false)
      }
    }
    "Object.getOwnPropertyNames" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let names : Array[JSValue] = []
      match target {
        Function(closure) =>
          for prop in closure.props {
            names.push(String(prop.key))
          }
        Object(map) =>
          for prop in map.props {
            names.push(String(prop.key))
          }
        Array(arr) => {
          for i in 0..<arr.items.length() {
            if arr.present[i] {
              names.push(String(i.to_string()))
            }
          }
          for prop in arr.props {
            names.push(String(prop.key))
          }
          names.push(String("length"))
        }
        _ => ()
      }
      match target {
        Function(_) => {
          let others : Array[JSValue] = []
          let mut has_length = false
          let mut has_name = false
          for item in names {
            match item {
              String("length") => has_length = true
              String("name") => has_name = true
              _ => others.push(item)
            }
          }
          let reordered : Array[JSValue] = []
          if has_length {
            reordered.push(String("length"))
          }
          if has_name {
            reordered.push(String("name"))
          }
          for item in others {
            reordered.push(item)
          }
          return js_array_from(reordered)
        }
        _ => ()
      }
      js_array_from(names)
    }
    "Object.keys" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let names : Array[JSValue] = []
      match target {
        Function(closure) =>
          for prop in closure.props {
            if prop.enumerable {
              names.push(String(prop.key))
            }
          }
        Object(map) =>
          for prop in map.props {
            if prop.enumerable {
              names.push(String(prop.key))
            }
          }
        Array(arr) => {
          for i in 0..<arr.items.length() {
            if arr.present[i] {
              names.push(String(i.to_string()))
            }
          }
          for prop in arr.props {
            if prop.enumerable {
              names.push(String(prop.key))
            }
          }
        }
        _ => ()
      }
      js_array_from(names)
    }
    "Object.values" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let values : Array[JSValue] = []
      match target {
        Function(closure) =>
          for prop in closure.props {
            if prop.enumerable {
              values.push(prop.value)
            }
          }
        Object(map) =>
          for prop in map.props {
            if prop.enumerable {
              values.push(prop.value)
            }
          }
        Array(arr) => {
          for i in 0..<arr.items.length() {
            if arr.present[i] {
              values.push(arr.items[i])
            }
          }
          for prop in arr.props {
            if prop.enumerable {
              values.push(prop.value)
            }
          }
        }
        _ => ()
      }
      js_array_from(values)
    }
    "Object.entries" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let entries : Array[JSValue] = []
      match target {
        Function(closure) =>
          for prop in closure.props {
            if prop.enumerable {
              entries.push(js_array_from([String(prop.key), prop.value]))
            }
          }
        Object(map) =>
          for prop in map.props {
            if prop.enumerable {
              entries.push(js_array_from([String(prop.key), prop.value]))
            }
          }
        Array(arr) => {
          for i in 0..<arr.items.length() {
            if arr.present[i] {
              entries.push(js_array_from([String(i.to_string()), arr.items[i]]))
            }
          }
          for prop in arr.props {
            if prop.enumerable {
              entries.push(js_array_from([String(prop.key), prop.value]))
            }
          }
        }
        _ => ()
      }
      js_array_from(entries)
    }
    "Object.assign" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      match target {
        Undefined | Null => {
          let err = self.set_error_kind(
            "TypeError",
            "Cannot convert undefined or null to object",
          )
          return err
        }
        _ => ()
      }
      for i in 1..<args.length() {
        let source = args[i]
        match source {
          Undefined | Null => continue
          Object(map) =>
            for prop in map.props {
              if prop.enumerable {
                let _ = js_set_prop(target, prop.key, prop.value)
              }
            }
          Array(arr) => {
            for j in 0..<arr.items.length() {
              if arr.present[j] {
                let _ = js_set_prop(target, j.to_string(), arr.items[j])
              }
            }
            for prop in arr.props {
              if prop.enumerable {
                let _ = js_set_prop(target, prop.key, prop.value)
              }
            }
          }
          Function(closure) =>
            for prop in closure.props {
              if prop.enumerable {
                let _ = js_set_prop(target, prop.key, prop.value)
              }
            }
          _ => ()
        }
      }
      target
    }
    "Object.fromEntries" => {
      let iterable = if args.length() > 0 { args[0] } else { Undefined }
      let obj = js_new_object_with_proto(Some(self.object_proto))
      match iterable {
        Array(arr) => {
          for i in 0..<arr.items.length() {
            if arr.present[i] {
              match arr.items[i] {
                Array(entry) =>
                  if entry.items.length() >= 2 && entry.present[0] && entry.present[1] {
                    let key = entry.items[0].to_js_string()
                    let value = entry.items[1]
                    let _ = js_set_prop(obj, key, value)
                  }
                _ => ()
              }
            }
          }
        }
        _ => ()
      }
      obj
    }
    "Object.isExtensible" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      match target {
        Object(_) | Function(_) | Array(_) => Bool(true)
        _ => Bool(false)
      }
    }
    "Object.is" => {
      let left = if args.length() > 0 { args[0] } else { Undefined }
      let right = if args.length() > 1 { args[1] } else { Undefined }
      Bool(self.same_value(left, right))
    }
    "Object.prototype.toString" => {
      let tag = match this_arg {
        Undefined => "Undefined"
        Null => "Null"
        Bool(_) => "Boolean"
        Number(_) => "Number"
        String(_) => "String"
        Array(_) => "Array"
        Function(_) => "Function"
        Object(_) => {
          let class_tag = js_get_prop(this_arg, "__class")
          match class_tag {
            String(tag_name) => tag_name
            _ => {
              let prim = js_get_prop(this_arg, "value")
              match prim {
                Bool(_) => "Boolean"
                Number(_) => "Number"
                String(_) => "String"
                _ => "Object"
              }
            }
          }
        }
        BreakSignal(_) | ContinueSignal(_) | Empty => "Object"
      }
      String("[object " + tag + "]")
    }
    "Object.prototype.isPrototypeOf" => {
      if args.length() == 0 {
        Bool(false)
      } else {
        let target = args[0]
        let mut cur = self.get_proto(target)
        while cur is Some(p) {
          match js_strict_eq(p, this_arg) {
            Bool(true) => return Bool(true)
            _ => ()
          }
          cur = self.get_proto(p)
        }
        Bool(false)
      }
    }
    "Object.prototype.valueOf" => this_arg
    "Boolean.prototype.valueOf" => js_get_prop(this_arg, "value")
    "Boolean.prototype.toString" => {
      let prim = match this_arg {
        Bool(_) => this_arg
        Object(_) | Function(_) | Array(_) => js_get_prop(this_arg, "value")
        _ => this_arg
      }
      String(prim.to_js_string())
    }
    "Number.prototype.valueOf" => js_get_prop(this_arg, "value")
    "Number.prototype.toString" => {
      let prim = match this_arg {
        Number(_) => this_arg
        Object(_) | Function(_) | Array(_) => js_get_prop(this_arg, "value")
        _ => this_arg
      }
      String(prim.to_js_string())
    }
    "Number.isNaN" =>
      if args.length() > 0 {
        match args[0] {
          Number(n) => Bool(n.is_nan())
          _ => Bool(false)
        }
      } else {
        Bool(false)
      }
    "String.prototype.valueOf" => js_get_prop(this_arg, "value")
    "Error" => {
      let msg = if args.length() > 0 { args[0].to_js_string() } else { "" }
      self.make_error_obj("Error", msg)
    }
    "JSON.parse" => {
      let text = if args.length() > 0 { args[0].to_js_string() } else { "" }
      let trimmed = text.trim().to_string()
      if trimmed == "null" {
        Null
      } else if trimmed == "true" {
        Bool(true)
      } else if trimmed == "false" {
        Bool(false)
      } else if trimmed.length() >= 2 && trimmed.has_prefix("\"") && trimmed.has_suffix("\"") {
        let inner = try { trimmed[1:trimmed.length() - 1].to_string() } catch { _ => "" }
        String(self.json_unescape(inner))
      } else {
        let num = @strconv.parse_double(trimmed) catch {
          _ => return self.set_error_kind("SyntaxError", "Invalid JSON")
        }
        Number(num)
      }
    }
    "JSON.stringify" => {
      if args.length() == 0 {
        Undefined
      } else {
        let value = args[0]
        match self.json_stringify_value(value, 0, false) {
          Some(s) => String(s)
          None => Undefined
        }
      }
    }
    "SyntaxError" => {
      let msg = if args.length() > 0 { args[0].to_js_string() } else { "" }
      self.make_error_obj("SyntaxError", msg)
    }
    "TypeError" => {
      let msg = if args.length() > 0 { args[0].to_js_string() } else { "" }
      self.make_error_obj("TypeError", msg)
    }
    "ReferenceError" => {
      let msg = if args.length() > 0 { args[0].to_js_string() } else { "" }
      self.make_error_obj("ReferenceError", msg)
    }
    "RangeError" => {
      let msg = if args.length() > 0 { args[0].to_js_string() } else { "" }
      self.make_error_obj("RangeError", msg)
    }
    "Test262Error" => {
      let msg = if args.length() > 0 { args[0].to_js_string() } else { "" }
      self.make_error_obj("Test262Error", msg)
    }
    "Function" => {
      let mut params_src = ""
      let mut body_src = ""
      if args.length() > 0 {
        if args.length() > 1 {
          let parts : Array[String] = []
          for i in 0..<(args.length() - 1) {
            parts.push(self.to_string_value(args[i]))
            match self.peek_error() {
              Some(err) => return err
              None => ()
            }
          }
          params_src = parts.join(",")
        }
        body_src = self.to_string_value(args[args.length() - 1])
        match self.peek_error() {
          Some(err) => return err
          None => ()
        }
      }
      let source =
        "function __f__(" + params_src + ") {\n" + body_src + "\n}"
      let func_value = try {
        let parser = @parser.Parser::from_source(source)
        let module_ = parser.parse_module()
        if module_.funcs.length() == 0 {
          JSValue::Undefined
        } else {
          let func = module_.funcs[0]
          let param_names : Array[String] = []
          for param in func.params {
            param_names.push(param.name)
          }
          let closure = JSValue::Function({
            id: fresh_function_id(),
            params: param_names,
            body: Ast(func),
            env: self.global_env,
            is_arrow: false,
            is_strict: self.is_strict_body(func.body, false),
            is_generator: func.is_generator,
            props: [],
            object_proto: Some(self.function_proto),
          })
          self.set_function_length(closure, param_names.length().to_double())
          let proto = self.new_object()
          let _ = js_set_prop(proto, "constructor", closure)
          let _ = js_define_data_prop(closure, "prototype", proto, true, false, true)
          closure
        }
      } catch {
        @parser.ParseError::ParseError(msg) => {
          let _ = self.set_error_kind("SyntaxError", "Function parse error: " + msg)
          JSValue::Undefined
        }
      }
      func_value
    }
    "Function.prototype" => Undefined
    "Function.prototype[@@hasInstance]" => {
      if args.length() == 0 {
        Bool(false)
      } else {
        Bool(self.ordinary_has_instance(this_arg, args[0]))
      }
    }
    "Function.call" => {
      let target = this_arg
      if not(self.is_callable(target)) {
        return self.set_error_kind("TypeError", "Function.prototype.call called on non-callable")
      }
      let call_this = if args.length() > 0 { args[0] } else { Undefined }
      let call_args : Array[JSValue] = []
      for i in 1..<args.length() {
        call_args.push(args[i])
      }
      self.call_function(target, call_this, call_args)
    }
    "Function.apply" => {
      let target = this_arg
      if not(self.is_callable(target)) {
        return self.set_error_kind("TypeError", "Function.prototype.apply called on non-callable")
      }
      let call_this = if args.length() > 0 { args[0] } else { Undefined }
      let call_args : Array[JSValue] = []
      if args.length() > 1 {
        match args[1] {
          Array(arr) =>
            for item in arr.items {
              call_args.push(item)
            }
          _ => ()
        }
      }
      self.call_function(target, call_this, call_args)
    }
    "Function.bind" => {
      let target = this_arg
      if not(self.is_callable(target)) {
        return self.set_error_kind("TypeError", "Function.prototype.bind called on non-callable")
      }
      let bound_this = if args.length() > 0 { args[0] } else { Undefined }
      let bound_args : Array[JSValue] = []
      for i in 1..<args.length() {
        bound_args.push(args[i])
      }
      let bound = JSValue::Function({
        id: fresh_function_id(),
        params: [],
        body: Bound(target, bound_this, bound_args),
        env: self.global_env,
        is_arrow: false,
        is_strict: false,
        is_generator: false,
        props: [],
        object_proto: Some(self.function_proto),
      })
      let len = self.calc_bound_length(target, bound_args.length())
      self.set_function_length(bound, len)
      let target_name_val = self.get_prop_value(target, "name")
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
    "Generator.prototype.next" => {
      match self.get_generator_id(this_arg) {
        Some(gen_id) => {
          let sent = if args.length() > 0 { args[0] } else { Undefined }
          self.generator_next(gen_id, sent)
        }
        None =>
          self.set_error_kind("TypeError", "Generator.prototype.next called on non-generator")
      }
    }
    "Generator.prototype.return" => {
      match self.get_generator_id(this_arg) {
        Some(gen_id) => {
          let sent = if args.length() > 0 { args[0] } else { Undefined }
          self.generator_return(gen_id, sent)
        }
        None =>
          self.set_error_kind("TypeError", "Generator.prototype.return called on non-generator")
      }
    }
    "Generator.prototype.throw" => {
      match self.get_generator_id(this_arg) {
        Some(gen_id) => {
          let sent = if args.length() > 0 { args[0] } else { Undefined }
          self.generator_throw(gen_id, sent)
        }
        None =>
          self.set_error_kind("TypeError", "Generator.prototype.throw called on non-generator")
      }
    }
    "Array" => {
      if args.length() == 0 {
        js_new_array()
      } else if args.length() == 1 {
        match args[0] {
          Number(n) => {
            let len = n.to_int()
            let arr = js_new_array()
            if len > 0 {
              let _ = js_set_prop(arr, "length", Number(n))
            }
            arr
          }
          _ => js_array_from([args[0]])
        }
      } else {
        let items : Array[JSValue] = []
        for item in args {
          items.push(item)
        }
        js_array_from(items)
      }
    }
    "Array.isArray" =>
      if args.length() > 0 {
        match args[0] {
          Array(_) => Bool(true)
          _ => Bool(false)
        }
      } else {
        Bool(false)
      }
    "Date" => {
      match this_arg {
        Object(_) => {
          let _ = js_set_prop(this_arg, "__class", String("Date"))
          let time_val =
            if args.length() == 0 {
              0.0
            } else if args.length() == 1 {
              let t = self.to_number_value(args[0])
              match self.peek_error() {
                Some(err) => return err
                None => time_clip(t)
              }
            } else {
              let y = self.to_number_value(args[0])
              let m = self.to_number_value(args[1])
              let dt =
                if args.length() > 2 {
                  self.to_number_value(args[2])
                } else {
                  1.0
                }
              let h =
                if args.length() > 3 {
                  self.to_number_value(args[3])
                } else {
                  0.0
                }
              let min =
                if args.length() > 4 {
                  self.to_number_value(args[4])
                } else {
                  0.0
                }
              let s =
                if args.length() > 5 {
                  self.to_number_value(args[5])
                } else {
                  0.0
                }
              let ms =
                if args.length() > 6 {
                  self.to_number_value(args[6])
                } else {
                  0.0
                }
              match self.peek_error() {
                Some(err) => return err
                None => {
                  if y.is_nan() ||
                    m.is_nan() ||
                    dt.is_nan() ||
                    h.is_nan() ||
                    min.is_nan() ||
                    s.is_nan() ||
                    ms.is_nan() {
                    js_nan
                  } else {
                    let mut year = y.to_int()
                    if year >= 0 && year <= 99 {
                      year += 1900
                    }
                    let time_val =
                      make_date_time(
                        year,
                        m.to_int(),
                        dt.to_int(),
                        h.to_int(),
                        min.to_int(),
                        s.to_int(),
                        ms.to_int(),
                      )
                    time_clip(time_val)
                  }
                }
              }
            }
          let _ = js_set_prop(this_arg, "__date_value", Number(time_val))
          this_arg
        }
        _ => String("Date")
      }
    }
    "Date.prototype.getTime" =>
      match self.date_time_value(this_arg) {
        Some(t) => Number(t)
        None => self.error_or_undefined()
      }
    "Date.prototype.valueOf" =>
      match self.date_time_value(this_arg) {
        Some(t) => Number(t)
        None => self.error_or_undefined()
      }
    "Date.prototype.setTime" => {
      let t = if args.length() > 0 { self.to_number_value(args[0]) } else { js_nan }
      match self.peek_error() {
        Some(err) => err
        None => {
          let clipped = time_clip(t)
          let _ = js_set_prop(this_arg, "__class", String("Date"))
          let _ = js_set_prop(this_arg, "__date_value", Number(clipped))
          Number(clipped)
        }
      }
    }
    "Date.prototype.getFullYear" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (year, _, _, _, _, _, _) = break_time(t)
            Number(year.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getYear" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (year, _, _, _, _, _, _) = break_time(t)
            Number((year - 1900).to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.setYear" => {
      let t_opt = self.date_time_value(this_arg)
      let t =
        match t_opt {
          Some(v) => v
          None => return self.error_or_undefined()
        }
      let y = if args.length() > 0 { self.to_number_value(args[0]) } else { js_nan }
      match self.peek_error() {
        Some(err) => err
        None => {
          let base_time = if t.is_nan() { 0.0 } else { t }
          if y.is_nan() {
            let _ = js_set_prop(this_arg, "__date_value", Number(js_nan))
            Number(js_nan)
          } else {
            let mut year = y.to_int()
            if year >= 0 && year <= 99 {
              year += 1900
            }
            let (_cur_year, month, day, hour, minute, second, milli) =
              break_time(base_time)
            let new_time =
              make_date_time(year, month, day, hour, minute, second, milli)
            let clipped = time_clip(new_time)
            let _ = js_set_prop(this_arg, "__date_value", Number(clipped))
            Number(clipped)
          }
        }
      }
    }
    "Symbol" => {
      if args.length() > 0 {
        String("Symbol(" + args[0].to_js_string() + ")")
      } else {
        String("Symbol()")
      }
    }
    "Boolean" =>
      if args.length() > 0 {
        let prim = JSValue::Bool(args[0].to_boolean())
        let bool_ctor = self.global_env.get("Boolean")
        let bool_proto = js_get_prop(bool_ctor, "prototype")
        let is_ctor = match self.get_proto(this_arg) {
          Some(p) =>
            match js_strict_eq(p, bool_proto) {
              Bool(true) => true
              _ => false
            }
          None => false
        }
        if is_ctor {
          let _ = js_set_prop(this_arg, "value", prim)
          this_arg
        } else {
          prim
        }
      } else {
        let prim = JSValue::Bool(false)
        let bool_ctor = self.global_env.get("Boolean")
        let bool_proto = js_get_prop(bool_ctor, "prototype")
        let is_ctor = match self.get_proto(this_arg) {
          Some(p) =>
            match js_strict_eq(p, bool_proto) {
              Bool(true) => true
              _ => false
            }
          None => false
        }
        if is_ctor {
          let _ = js_set_prop(this_arg, "value", prim)
          this_arg
        } else {
          prim
        }
      }
    "Number" =>
      if args.length() > 0 {
        let prim = JSValue::Number(args[0].to_number())
        let num_ctor = self.global_env.get("Number")
        let num_proto = js_get_prop(num_ctor, "prototype")
        let is_ctor = match self.get_proto(this_arg) {
          Some(p) =>
            match js_strict_eq(p, num_proto) {
              Bool(true) => true
              _ => false
            }
          None => false
        }
        if is_ctor {
          let _ = js_set_prop(this_arg, "value", prim)
          this_arg
        } else {
          prim
        }
      } else {
        let prim = JSValue::Number(0.0)
        let num_ctor = self.global_env.get("Number")
        let num_proto = js_get_prop(num_ctor, "prototype")
        let is_ctor = match self.get_proto(this_arg) {
          Some(p) =>
            match js_strict_eq(p, num_proto) {
              Bool(true) => true
              _ => false
            }
          None => false
        }
        if is_ctor {
          let _ = js_set_prop(this_arg, "value", prim)
          this_arg
        } else {
          prim
        }
      }
    "String" =>
      if args.length() > 0 {
        let prim = JSValue::String(self.to_string_value(args[0]))
        let str_ctor = self.global_env.get("String")
        let str_proto = js_get_prop(str_ctor, "prototype")
        let is_ctor = match self.get_proto(this_arg) {
          Some(p) =>
            match js_strict_eq(p, str_proto) {
              Bool(true) => true
              _ => false
            }
          None => false
        }
        if is_ctor {
          let _ = js_set_prop(this_arg, "value", prim)
          this_arg
        } else {
          prim
        }
      } else {
        let prim = JSValue::String("")
        let str_ctor = self.global_env.get("String")
        let str_proto = js_get_prop(str_ctor, "prototype")
        let is_ctor = match self.get_proto(this_arg) {
          Some(p) =>
            match js_strict_eq(p, str_proto) {
              Bool(true) => true
              _ => false
            }
          None => false
        }
        if is_ctor {
          let _ = js_set_prop(this_arg, "value", prim)
          this_arg
        } else {
          prim
        }
      }
    "String.fromCharCode" => {
      let mut out = ""
      for arg in args {
        let code = arg.to_number().to_int()
        let unit = code.to_uint16()
        let ch = unit.unsafe_to_char()
        out = out + ch.to_string()
      }
      String(out)
    }
    "String.fromCodePoint" => {
      let mut out = ""
      for arg in args {
        let code = arg.to_number().to_int()
        if code < 0 || code > 0x10ffff {
          return self.set_error_kind("RangeError", "Invalid code point")
        }
        let ch = code.unsafe_to_char()
        out = out + ch.to_string()
      }
      String(out)
    }
    "RegExp" => {
      let pattern_val = if args.length() > 0 { args[0] } else { String("") }
      let flags = if args.length() > 1 { args[1].to_js_string() } else { "" }
      if is_regexp(pattern_val) && flags == "" {
        pattern_val
      } else {
        let pattern = pattern_val.to_js_string()
        self.make_regexp(pattern, flags)
      }
    }
    "RegExp.prototype.exec" => {
      if not(is_regexp(this_arg)) {
        return self.set_error_kind("TypeError", "RegExp.prototype.exec called on non-RegExp")
      }
      let input = if args.length() > 0 { self.to_string_value(args[0]) } else { "" }
      let pattern = regexp_source(this_arg)
      let flags = regexp_flags(this_arg)
      let mut last_index = 0
      if regexp_has_global(flags) {
        match js_get_prop(this_arg, "lastIndex") {
          Number(n) => last_index = n.to_int()
          _ => last_index = 0
        }
      }
      match regexp_exec_groups(pattern, flags, input, last_index) {
        None => {
          let _ = js_set_prop(this_arg, "lastIndex", Number(0.0))
          Null
        }
        Some((start, end, groups)) => {
          let arr = js_array_from(groups)
          let _ = js_set_prop(arr, "index", Number(start.to_double()))
          let _ = js_set_prop(arr, "input", String(input))
          let _ = js_set_prop(this_arg, "lastIndex", Number(end.to_double()))
          arr
        }
      }
    }
    "RegExp.prototype.compile" => {
      if not(is_regexp(this_arg)) {
        return self.set_error_kind("TypeError", "RegExp.prototype.compile called on non-RegExp")
      }
      let pattern_val = if args.length() > 0 { args[0] } else { String("") }
      let flags_val = if args.length() > 1 { args[1] } else { Undefined }
      let (pattern, flags) =
        if is_regexp(pattern_val) && flags_val is Undefined {
          (regexp_source(pattern_val), regexp_flags(pattern_val))
        } else {
          let p = pattern_val.to_js_string()
          let f = if flags_val is Undefined { "" } else { flags_val.to_js_string() }
          (p, f)
        }
      match regexp_compile(pattern, flags) {
        None => return self.set_error_kind("SyntaxError", "Invalid regular expression")
        Some(_) => ()
      }
      let norm_flags = normalize_regexp_flags(flags)
      let _ = js_set_prop(this_arg, "source", String(pattern))
      let _ = js_set_prop(this_arg, "flags", String(norm_flags))
      let _ = js_set_prop(this_arg, "global", Bool(regexp_has_global(norm_flags)))
      let _ = js_set_prop(this_arg, "lastIndex", Number(0.0))
      this_arg
    }
    "RegExp.prototype.test" => {
      if not(is_regexp(this_arg)) {
        return self.set_error_kind("TypeError", "RegExp.prototype.test called on non-RegExp")
      }
      let input = if args.length() > 0 { self.to_string_value(args[0]) } else { "" }
      let pattern = regexp_source(this_arg)
      let flags = regexp_flags(this_arg)
      let mut last_index = 0
      if regexp_has_global(flags) {
        match js_get_prop(this_arg, "lastIndex") {
          Number(n) => last_index = n.to_int()
          _ => last_index = 0
        }
      }
      match regexp_first_match(pattern, flags, input, last_index) {
        None => {
          let _ = js_set_prop(this_arg, "lastIndex", Number(0.0))
          Bool(false)
        }
        Some((_start, end)) => {
          let _ = js_set_prop(this_arg, "lastIndex", Number(end.to_double()))
          Bool(true)
        }
      }
    }
    "console.log" => {
      let parts : Array[String] = []
      for arg in args {
        parts.push(arg.to_js_string())
      }
      println(parts.join(" "))
      Undefined
    }
    "eval" => {
      let src = if args.length() > 0 { args[0].to_js_string() } else { "" }
      self.eval_script_source(src)
    }
    "Reflect.construct" => {
      if args.length() == 0 {
        Undefined
      } else {
        let target = args[0]
        let new_target = if args.length() > 2 { args[2] } else { target }
        let call_args : Array[JSValue] = []
        if args.length() > 1 {
          match args[1] {
            Array(arr) =>
              for item in arr.items {
                call_args.push(item)
              }
            _ => ()
          }
        }
        match target {
          Function(closure) =>
            match closure.body {
              Native("Function") => self.call_native("Function", Undefined, call_args)
              _ => self.construct_with(target, new_target, call_args)
            }
          _ => Undefined
        }
      }
    }
    "Reflect.get" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let key_val = if args.length() > 1 { args[1] } else { Undefined }
      let receiver = if args.length() > 2 { args[2] } else { target }
      let key = self.normalize_prop_key(key_val.to_js_string())
      if self.is_proxy(target) {
        self.proxy_get(target, key, receiver)
      } else {
        self.get_prop_value_with_receiver(target, receiver, key)
      }
    }
    "Reflect.set" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let key_val = if args.length() > 1 { args[1] } else { Undefined }
      let value = if args.length() > 2 { args[2] } else { Undefined }
      let receiver = if args.length() > 3 { args[3] } else { target }
      let key = self.normalize_prop_key(key_val.to_js_string())
      if self.is_proxy(target) {
        Bool(self.proxy_set(target, key, value, receiver))
      } else {
        if self.is_proxy(receiver) {
          let desc = self.proxy_get_own_property_descriptor(receiver, key)
          match self.peek_error() {
            Some(_) => return Bool(false)
            None => ()
          }
          let new_desc =
            match desc {
              Undefined => self.make_data_descriptor(value, true, true, true)
              _ => {
                let has_enum = self.has_own_prop(desc, "enumerable")
                let enumerable =
                  if has_enum {
                    self.get_prop_value(desc, "enumerable").to_boolean()
                  } else {
                    true
                  }
                let has_config = self.has_own_prop(desc, "configurable")
                let configurable =
                  if has_config {
                    self.get_prop_value(desc, "configurable").to_boolean()
                  } else {
                    true
                  }
                let has_value = self.has_own_prop(desc, "value")
                if has_value {
                  let _ = self.get_prop_value(desc, "value")
                }
                let has_writable = self.has_own_prop(desc, "writable")
                let writable =
                  if has_writable {
                    self.get_prop_value(desc, "writable").to_boolean()
                  } else {
                    true
                  }
                let _ = self.has_own_prop(desc, "get")
                let _ = self.has_own_prop(desc, "set")
                self.make_data_descriptor(value, writable, enumerable, configurable)
              }
            }
          let _ = self.proxy_define_property(receiver, key, new_desc)
          match self.peek_error() {
            Some(_) => Bool(false)
            None => Bool(true)
          }
        } else {
          self.set_prop_value(target, key, value)
          match self.peek_error() {
            Some(_) => Bool(false)
            None => Bool(true)
          }
        }
      }
    }
    "Reflect.has" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let key_val = if args.length() > 1 { args[1] } else { Undefined }
      let key = self.normalize_prop_key(key_val.to_js_string())
      if self.is_proxy(target) {
        Bool(self.proxy_has(target, key))
      } else {
        Bool(js_has_prop(target, key))
      }
    }
    "Reflect.defineProperty" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let key_val = if args.length() > 1 { args[1] } else { Undefined }
      let desc = if args.length() > 2 { args[2] } else { Undefined }
      let key = self.normalize_prop_key(key_val.to_js_string())
      if self.is_proxy(target) {
        let result = self.proxy_define_property(target, key, desc)
        match self.peek_error() {
          Some(_) => Bool(false)
          None => Bool(result.to_boolean())
        }
      } else {
        let _ = self.define_property(target, key, desc)
        match self.peek_error() {
          Some(_) => Bool(false)
          None => Bool(true)
        }
      }
    }
    "Reflect.getPrototypeOf" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      if self.is_proxy(target) {
        self.proxy_get_prototype_of(target)
      } else {
        match target {
          Object(map) => match map.prototype {
            Some(p) => p
            None => Null
          }
          Function(closure) => match closure.object_proto {
            Some(p) => p
            None => Null
          }
          Array(arr) => match arr.prototype {
            Some(p) => p
            None => Null
          }
          _ => Undefined
        }
      }
    }
    "Reflect.getOwnPropertyDescriptor" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let key_val = if args.length() > 1 { args[1] } else { Undefined }
      let call_args : Array[JSValue] = []
      call_args.push(target)
      call_args.push(key_val)
      self.call_native("Object.getOwnPropertyDescriptor", Undefined, call_args)
    }
    "Math.floor" =>
      if args.length() > 0 {
        Number(args[0].to_number().floor())
      } else {
        Number(js_nan)
      }
    "Math.ceil" =>
      if args.length() > 0 {
        Number(args[0].to_number().ceil())
      } else {
        Number(js_nan)
      }
    "Math.abs" =>
      if args.length() > 0 {
        Number(args[0].to_number().abs())
      } else {
        Number(js_nan)
      }
    "Math.sqrt" =>
      if args.length() > 0 {
        Number(args[0].to_number().sqrt())
      } else {
        Number(js_nan)
      }
    "Math.cos" =>
      if args.length() > 0 {
        Number(@math.cos(args[0].to_number()))
      } else {
        Number(js_nan)
      }
    "Math.sin" =>
      if args.length() > 0 {
        Number(@math.sin(args[0].to_number()))
      } else {
        Number(js_nan)
      }
    "Math.tan" =>
      if args.length() > 0 {
        Number(@math.tan(args[0].to_number()))
      } else {
        Number(js_nan)
      }
    "Math.exp" =>
      if args.length() > 0 {
        Number(@math.exp(args[0].to_number()))
      } else {
        Number(js_nan)
      }
    "Math.log" =>
      if args.length() > 0 {
        Number(@math.ln(args[0].to_number()))
      } else {
        Number(js_nan)
      }
    "Math.trunc" =>
      if args.length() > 0 {
        let n = args[0].to_number()
        if n.is_nan() || n.is_inf() {
          Number(n)
        } else if n >= 0.0 {
          Number(n.floor())
        } else {
          Number(n.ceil())
        }
      } else {
        Number(js_nan)
      }
    "Math.min" =>
      if args.length() == 0 {
        Number(1.0 / 0.0)
      } else if args.length() == 1 {
        Number(args[0].to_number())
      } else {
        let mut min_val = args[0].to_number()
        if min_val.is_nan() {
          return Number(min_val)
        }
        for i in 1..<args.length() {
          let val = args[i].to_number()
          if val.is_nan() {
            return Number(val)
          }
          if val < min_val {
            min_val = val
          }
        }
        Number(min_val)
      }
    "Math.max" =>
      if args.length() == 0 {
        Number(-1.0 / 0.0)
      } else if args.length() == 1 {
        Number(args[0].to_number())
      } else {
        let mut max_val = args[0].to_number()
        if max_val.is_nan() {
          return Number(max_val)
        }
        for i in 1..<args.length() {
          let val = args[i].to_number()
          if val.is_nan() {
            return Number(val)
          }
          if val > max_val {
            max_val = val
          }
        }
        Number(max_val)
      }
    "Math.round" =>
      if args.length() > 0 {
        Number(args[0].to_number().round())
      } else {
        Number(js_nan)
      }
    "Math.random" =>
      // TODO: implementation
      Number(0.5)
    // test262 harness functions
    "print" => {
      let parts : Array[String] = []
      for arg in args {
        parts.push(arg.to_js_string())
      }
      println(parts.join(" "))
      Undefined
    }
    "escape" => {
      let input =
        if args.length() > 0 {
          self.to_string_value(args[0])
        } else {
          "undefined"
        }
      match self.peek_error() {
        Some(err) => err
        None => String(escape_string_value(input))
      }
    }
    "unescape" => {
      let input =
        if args.length() > 0 {
          self.to_string_value(args[0])
        } else {
          "undefined"
        }
      match self.peek_error() {
        Some(err) => err
        None => String(unescape_string_value(input))
      }
    }
    "isNaN" => {
      let num = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Bool(num.is_nan())
    }
    "isFinite" => {
      let num = if args.length() > 0 { args[0].to_number() } else { 0.0 / 0.0 }
      Bool(not(num.is_nan()) && not(num.is_inf()) && not(num.is_neg_inf()))
    }
    "parseInt" => {
      let input_str = if args.length() > 0 {
        args[0].to_js_string()
      } else {
        "NaN"
      }
      let radix = if args.length() > 1 {
        let r = args[1].to_number().to_int()
        if r == 0 { 10 } else { r }
      } else {
        10
      }
      // Handle hex prefix
      let trimmed = input_str.trim_start().to_string()
      let (actual_str, actual_radix) : (String, Int) = if radix == 16 || radix == 0 {
        if trimmed.has_prefix("0x") || trimmed.has_prefix("0X") {
          ((try { trimmed[2:] } catch { _ => trimmed }).to_string(), 16)
        } else {
          (trimmed, if radix == 0 { 10 } else { radix })
        }
      } else {
        (trimmed, radix)
      }
      if actual_radix < 2 || actual_radix > 36 {
        Number(0.0 / 0.0) // NaN
      } else {
        let result : Int = try {
          @strconv.parse_int(actual_str, base=actual_radix)
        } catch {
          _ => {
            // Try without base if it fails
            try { @strconv.parse_int(actual_str) } catch { _ => 0 }
          }
        }
        // If parsing fails completely, return NaN
        // For simplicity, just return the parsed value or 0
        Number(result.to_double())
      }
    }
    "parseFloat" => {
      let input_str = if args.length() > 0 {
        args[0].to_js_string()
      } else {
        "NaN"
      }
      let trimmed = input_str.trim_start().to_string()
      let result : Double = try {
        @strconv.parse_double(trimmed)
      } catch {
        _ => 0.0 / 0.0 // NaN
      }
      Number(result)
    }
    "assert" =>
      if args.length() > 0 {
        let condition = args[0].to_boolean()
        if condition {
          Undefined
        } else {
          let msg = if args.length() > 1 {
            args[1].to_js_string()
          } else {
            "Assertion failed"
          }
          self.set_error(msg)
        }
      } else {
        Undefined
      }
    "assert.sameValue" =>
      if args.length() >= 2 {
        let actual = args[0]
        let expected = args[1]
        let result = assert_same_value(
          actual,
          expected,
          if args.length() > 2 { Some(args[2].to_js_string()) } else { None },
        )
        match result {
          Success => Undefined
          Failure(msg) => self.set_error(msg)
        }
      } else {
        Undefined
      }
    "assert.notSameValue" =>
      if args.length() >= 2 {
        let actual = args[0]
        let unexpected = args[1]
        let result = assert_not_same_value(
          actual,
          unexpected,
          if args.length() > 2 { Some(args[2].to_js_string()) } else { None },
        )
        match result {
          Success => Undefined
          Failure(msg) => self.set_error(msg)
        }
      } else {
        Undefined
      }
    "assert.compareArray" =>
      if args.length() >= 2 {
        let actual = args[0]
        let expected = args[1]
        let result = compare_array(
          actual,
          expected,
          if args.length() > 2 { Some(args[2].to_js_string()) } else { None },
        )
        match result {
          Success => Undefined
          Failure(msg) => self.set_error(msg)
        }
      } else {
        Undefined
      }
    "assert.throws" => {
      if args.length() < 2 {
        return self.set_error("assert.throws requires 2 args")
      }
      let expected = args[0]
      let thunk = args[1]
      match thunk {
        Function(_) => ()
        _ => return self.set_error_kind("TypeError", "assert.throws requires a function")
      }
      let _ = self.take_error()
      let _ = self.call_function(thunk, Undefined, [])
      match self.take_error() {
        None => self.set_error("Expected an error to be thrown")
        Some(e) => {
          let expected_name = js_get_prop(expected, "name")
          let actual_name = js_get_prop(e, "name")
          match (expected_name, actual_name) {
            (String(en), String(an)) =>
              if en == an {
                Undefined
              } else {
                self.set_error("Expected " + en + " but got " + an)
              }
            _ => Undefined
          }
        }
      }
    }
    "$DONOTEVALUATE" => {
      // This function should never be called in a passing test
      self.set_error("$DONOTEVALUATE was called")
    }
    "$ERROR" => {
      let msg = if args.length() > 0 {
        args[0].to_js_string()
      } else {
        "$ERROR"
      }
      self.set_error(msg)
    }
    "$DONE" =>
      if args.length() > 0 {
        let err = args[0]
        if !err.is_undefined() {
          self.set_error("Async test failed: " + err.to_js_string())
        } else {
          Undefined
        }
      } else {
        Undefined
      }
    "Test262Error.thrower" => {
      let msg = if args.length() > 0 { args[0].to_js_string() } else { "Test262Error" }
      self.set_error_kind("Test262Error", msg)
    }
    "$262.evalScript" =>
      if args.length() > 0 {
        let code = args[0].to_js_string()
        self.eval_script_source(code)
      } else {
        Undefined
      }
    "$262.createRealm" => {
      let realm = self.new_object()
      let other = JSInterpreter::new()
      let other_global = other.global_env.get("globalThis")
      let _ = js_set_prop(realm, "global", other_global)
      let current_array_proto = js_get_prop(self.global_env.get("Array"), "prototype")
      match current_array_proto {
        Object(_) | Function(_) | Array(_) => js_set_default_array_proto(current_array_proto)
        _ => ()
      }
      realm
    }
    _ => Undefined
  }
}

///|
// / newcreate
fn JSInterpreter::new_instance(
  self : JSInterpreter,
  class_name : String,
  args : Array[JSValue],
  env : JSEnv,
) -> JSValue {
  match class_name {
    "Test262Error" => {
      let msg = if args.length() > 0 {
        args[0].to_js_string()
      } else {
        ""
      }
      let obj = self.new_object()
      let _ = js_set_prop(obj, "name", JSValue::String("Test262Error"))
      let _ = js_set_prop(obj, "message", JSValue::String(msg))
      obj
    }
    "Function" => self.call_native("Function", Undefined, args)
    "Boolean" => {
      let val =
        if args.length() > 0 {
          JSValue::Bool(args[0].to_boolean())
        } else {
          JSValue::Bool(false)
        }
      let ctor = env.get("Boolean")
      let proto = js_get_prop(ctor, "prototype")
      let obj = match proto {
        Object(_) | Function(_) => js_new_object_with_proto(Some(proto))
        _ => self.new_object()
      }
      let _ = js_set_prop(obj, "value", val)
      obj
    }
    "Number" => {
      let val =
        if args.length() > 0 {
          JSValue::Number(args[0].to_number())
        } else {
          JSValue::Number(0.0)
        }
      let ctor = env.get("Number")
      let proto = js_get_prop(ctor, "prototype")
      let obj = match proto {
        Object(_) | Function(_) => js_new_object_with_proto(Some(proto))
        _ => self.new_object()
      }
      let _ = js_set_prop(obj, "value", val)
      obj
    }
    "String" => {
      let val =
        if args.length() > 0 {
          JSValue::String(args[0].to_js_string())
        } else {
          JSValue::String("")
        }
      let ctor = env.get("String")
      let proto = js_get_prop(ctor, "prototype")
      let obj = match proto {
        Object(_) | Function(_) => js_new_object_with_proto(Some(proto))
        _ => self.new_object()
      }
      let _ = js_set_prop(obj, "value", val)
      obj
    }
    "Array" =>
      if args.length() == 1 {
        match args[0] {
          Number(n) => {
            let len = n.to_int()
            let arr = js_new_array()
            if len > 0 {
              let _ = js_set_prop(arr, "length", Number(n))
            }
            arr
          }
          _ => js_array_from(args.copy())
        }
      } else {
        js_array_from(args.copy())
      }
    "Promise" => self.promise_construct(args)
    "Proxy" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let handler = if args.length() > 1 { args[1] } else { Undefined }
      self.new_proxy(target, handler)
    }
    "RegExp" => {
      let pattern_val = if args.length() > 0 { args[0] } else { String("") }
      let flags = if args.length() > 1 { args[1].to_js_string() } else { "" }
      if is_regexp(pattern_val) && flags == "" {
        pattern_val
      } else {
        let pattern = pattern_val.to_js_string()
        self.make_regexp(pattern, flags)
      }
    }
    "Object" => self.new_object()
    _ => {
      // lookup
      let ctor = env.get(class_name)
      match ctor {
        Function(_) => self.construct_with(ctor, ctor, args)
        _ => self.new_object()
      }
    }
  }
}
