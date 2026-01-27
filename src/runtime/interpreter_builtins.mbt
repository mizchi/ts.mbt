///|
// /
fn JSInterpreter::install_builtins(self : JSInterpreter) -> Unit {
  let global_obj = self.new_object()

  // Object.prototype
  let has_own = self.make_native("Object.hasOwnProperty")
  self.set_function_length(has_own, 1.0)
  let _ = js_set_prop(self.object_proto, "hasOwnProperty", has_own)
  let to_string_fn = self.make_native("Object.prototype.toString")
  self.set_function_length(to_string_fn, 0.0)
  let _ = js_set_prop(self.object_proto, "toString", to_string_fn)
  let is_proto_fn = self.make_native("Object.prototype.isPrototypeOf")
  self.set_function_length(is_proto_fn, 1.0)
  let _ = js_set_prop(self.object_proto, "isPrototypeOf", is_proto_fn)
  let value_of_fn = self.make_native("Object.prototype.valueOf")
  self.set_function_length(value_of_fn, 0.0)
  let _ = js_set_prop(self.object_proto, "valueOf", value_of_fn)
  let prop_enum_fn = self.make_native("Object.prototype.propertyIsEnumerable")
  self.set_function_length(prop_enum_fn, 1.0)
  let _ = js_set_prop(self.object_proto, "propertyIsEnumerable", prop_enum_fn)

  // Object
  let object_ctor = self.make_native("Object")
  let _ = js_define_data_prop(object_ctor, "prototype", self.object_proto, true, false, true)
  let _ = js_set_prop(object_ctor, "name", JSValue::String("Object"))
  let _ = js_set_prop(self.object_proto, "constructor", object_ctor)
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
  let obj_is_ext = self.make_native("Object.isExtensible")
  self.set_function_length(obj_is_ext, 1.0)
  let _ = js_set_prop(object_ctor, "isExtensible", obj_is_ext)
  let obj_is = self.make_native("Object.is")
  self.set_function_length(obj_is, 2.0)
  let _ = js_set_prop(object_ctor, "is", obj_is)
  self.global_env.define_var("Object", object_ctor)
  let _ = js_set_prop(global_obj, "Object", object_ctor)

  // console
  let console = self.new_object()
  let _ = js_set_prop(console, "log", self.make_native("console.log"))
  self.global_env.define_var("console", console)
  let _ = js_set_prop(global_obj, "console", console)

  // Math
  let math = self.new_object()
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
  let bool_value_of = self.make_native("Boolean.prototype.valueOf")
  self.set_function_length(bool_value_of, 0.0)
  let _ = js_set_prop(boolean_proto, "valueOf", bool_value_of)
  self.global_env.define_var("Boolean", boolean_ctor)
  let _ = js_set_prop(global_obj, "Boolean", boolean_ctor)

  let number_proto = self.new_object()
  let number_ctor = self.make_native("Number")
  self.set_function_length(number_ctor, 1.0)
  self.set_function_name(number_ctor, "Number")
  let _ = js_define_data_prop(number_ctor, "prototype", number_proto, true, false, true)
  let _ = js_set_prop(number_proto, "constructor", number_ctor)
  let num_value_of = self.make_native("Number.prototype.valueOf")
  self.set_function_length(num_value_of, 0.0)
  let _ = js_set_prop(number_proto, "valueOf", num_value_of)
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
  let test262_ctor = self.make_native("Test262Error")
  self.set_function_name(test262_ctor, "Test262Error")
  let _ = js_define_data_prop(test262_ctor, "prototype", self.new_object(), true, false, true)
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

  // eval
  let eval_fn = self.make_native("eval")
  self.set_function_length(eval_fn, 1.0)
  self.global_env.define_var("eval", eval_fn)
  let _ = js_set_prop(global_obj, "eval", eval_fn)

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

  // Symbol
  let symbol_fn = self.make_native("Symbol")
  self.set_function_length(symbol_fn, 0.0)
  let _ = js_set_prop(symbol_fn, "hasInstance", String("@@hasInstance"))
  self.global_env.define_var("Symbol", symbol_fn)
  let _ = js_set_prop(global_obj, "Symbol", symbol_fn)

  // Reflect
  let reflect = self.new_object()
  let _ = js_set_prop(reflect, "construct", self.make_native("Reflect.construct"))
  self.global_env.define_var("Reflect", reflect)
  let _ = js_set_prop(global_obj, "Reflect", reflect)
}

///|
fn JSInterpreter::call_native(
  self : JSInterpreter,
  name : String,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  if name.has_prefix("Array.prototype.") {
    let method_name = (try { name[16:] } catch { _ => "" }).to_string()
    match this_arg {
      Array(arr) => return self.array_method(arr, method_name, args)
      _ =>
        if method_name == "map" {
          let callback = if args.length() > 0 { args[0] } else { Undefined }
          let len_value = self.get_prop_value(this_arg, "length")
          match self.peek_error() {
            Some(err) => return err
            None => ()
          }
          let mut len_num = self.to_number_value(len_value)
          match self.peek_error() {
            Some(err) => return err
            None => ()
          }
          if len_num.is_nan() {
            len_num = 0.0
          }
          if len_num.is_inf() || len_num < 0.0 {
            return self.set_error_kind("RangeError", "Invalid array length")
          }
          let len = len_num.to_int()
          if len > 1_000_000 {
            return self.set_error_kind("RangeError", "Invalid array length")
          }
          if not(self.is_callable(callback)) {
            return self.set_error_kind(
              "TypeError",
              "Array.prototype.map requires a callback",
            )
          }
          let callback_this = if args.length() > 1 { args[1] } else { Undefined }
          let result : Array[JSValue] = []
          let mut i = 0
          while i < len {
            let key = i.to_string()
            if js_has_prop(this_arg, key) {
              let value = self.get_prop_value(this_arg, key)
              let mapped = self.call_function(
                callback,
                callback_this,
                [value, JSValue::Number(i.to_double()), this_arg],
              )
              result.push(mapped)
            } else {
              result.push(Undefined)
            }
            i += 1
          }
          return js_array_from(result)
        } else {
          return self.set_error_kind(
            "TypeError",
            "Array.prototype." + method_name + " called on non-array",
            )
        }
    }
  }
  if name.has_prefix("String.prototype.") {
    let method_name = (try { name[17:] } catch { _ => "" }).to_string()
    match this_arg {
      Undefined | Null =>
        return self.set_error_kind(
          "TypeError",
          "String.prototype." + method_name + " called on null or undefined",
        )
      _ => {
        let s = self.to_string_value(this_arg)
        return self.string_method(s, method_name, args)
      }
    }
  }
  match name {
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
      let key = if args.length() > 1 { args[1].to_js_string() } else { "" }
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
            if idx >= 0 && idx < arr.items.length() {
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
            Undefined
          }
        _ => Undefined
      }
    }
    "Object.defineProperty" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let key = if args.length() > 1 { args[1].to_js_string() } else { "" }
      let desc = if args.length() > 2 { args[2] } else { Undefined }
      let is_obj = match desc {
        Object(_) | Function(_) => true
        _ => false
      }
      if not(is_obj) {
        return target
      }
      let has_get = self.has_own_prop(desc, "get")
      let has_set = self.has_own_prop(desc, "set")
      let enumerable = if self.has_own_prop(desc, "enumerable") {
        js_get_prop(desc, "enumerable").to_boolean()
      } else {
        false
      }
      let configurable = if self.has_own_prop(desc, "configurable") {
        js_get_prop(desc, "configurable").to_boolean()
      } else {
        false
      }
      if has_get || has_set {
        let get_val = if has_get { js_get_prop(desc, "get") } else { Undefined }
        let set_val = if has_set { js_get_prop(desc, "set") } else { Undefined }
        let getter = match get_val {
          Undefined => None
          _ => Some(get_val)
        }
        let setter = match set_val {
          Undefined => None
          _ => Some(set_val)
        }
        let _ = js_define_accessor_prop(target, key, getter, setter, enumerable, configurable)
        target
      } else {
        let value = if self.has_own_prop(desc, "value") { js_get_prop(desc, "value") } else { Undefined }
        let writable = if self.has_own_prop(desc, "writable") {
          js_get_prop(desc, "writable").to_boolean()
        } else {
          false
        }
        let _ = js_define_data_prop(target, key, value, writable, enumerable, configurable)
        target
      }
    }
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
        BreakSignal | ContinueSignal => "Object"
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
    "Number.prototype.valueOf" => js_get_prop(this_arg, "value")
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
        Some(gen_id) => self.generator_next(gen_id)
        None =>
          self.set_error_kind("TypeError", "Generator.prototype.next called on non-generator")
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
          this_arg
        }
        _ => String("Date")
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
        let prim = JSValue::String(args[0].to_js_string())
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
      let wrapped = "function main() {\n" + src + "\n}"
      let result = try {
        let parser = @parser.Parser::from_source(wrapped)
        let module_ = parser.parse_module()
        self.run_module(module_)
      } catch {
        @parser.ParseError::ParseError(msg) => {
          let _ = self.set_error_kind("SyntaxError", msg)
          Undefined
        }
      }
      result
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
    "$262.evalScript" =>
      if args.length() > 0 {
        let code = args[0].to_js_string()
        self.run(code) catch {
          _ => {
            let wrapped = "function main() {\n" + code + "\n}"
            self.run(wrapped) catch {
              e2 => {
                let _ = self.set_error("$262.evalScript parse error: \{e2}")
                Undefined
              }
            }
          }
        }
      } else {
        Undefined
      }
    "$262.createRealm" => {
      let realm = self.new_object()
      let global_obj = self.global_env.get("globalThis")
      let _ = js_set_prop(realm, "global", global_obj)
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
