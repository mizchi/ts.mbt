///|
async fn main_async() -> Unit {
  let args = @env.args()
  if args.length() < 2 {
    print_usage()
    return
  }
  let command = args[1]
  match command {
    "run" => {
      if args.length() < 3 {
        println("Error: no file specified")
        return
      }
      let file_path = args[2]
      run_ts_file(file_path)
    }
    "test262" => {
      if args.length() < 3 {
        println("Error: no test directory or file specified")
        return
      }
      let test_path = args[2]
      run_test262(test_path)
    }
    _ => {
      println("Unknown command: \{command}")
      print_usage()
    }
  }
}

///|
fn main {
  @async.run_async_main(main_async)
}

///|
fn print_usage() -> Unit {
  println("Usage: wasm5-ts <command> [args...]")
  println("")
  println("Commands:")
  println("  run <file>         Run a TypeScript/JavaScript file")
  println("  test262 <path>     Run test262 tests (file or directory)")
}

///|
async fn run_ts_file(file_path : String) -> Unit {
  let content = @fs.read_file(file_path).text() catch {
    e => {
      println("Error reading file: \{e}")
      return
    }
  }
  let interp = @runtime.JSInterpreter::new()
  if has_module_syntax(content) {
    let module_cache : Array[(String, @runtime.JSValue)] = []
    let result = eval_module(interp, file_path, module_cache, source=content) catch {
      e => {
        println("Error: \{e}")
        return
      }
    }
    if is_error_value(result) {
      let error_msg = @runtime.js_get_prop(result, "error")
      println("Error: \{error_msg.to_js_string()}")
    }
  } else {
    // Wrap source in function main() for non-module code
    let wrapped = "function main() {\n" + content + "\n}"
    let result = interp.run(wrapped) catch {
      e => {
        println("Error: \{e}")
        return
      }
    }
    println(result.to_js_string())
  }
}

///|
priv struct Test262Meta {
  includes : Array[String]
  flags : Array[String]
  negative : Bool
  negative_phase : String?
  negative_type : String?
}

///|
fn join_path(base : String, name : String) -> String {
  if base.has_suffix("/") {
    base + name
  } else {
    base + "/" + name
  }
}

///|
fn normalize_path(path : String) -> String {
  let is_abs = path.has_prefix("/")
  let parts : Array[String] = []
  for part_view in path.split("/") {
    let part = part_view.to_string()
    if part == "" {
      if is_abs && parts.length() == 0 {
        parts.push("")
      }
      continue
    }
    if part == "." {
      continue
    }
    if part == ".." {
      if parts.length() > 0 {
        let last = parts[parts.length() - 1]
        if last != "" && last != ".." {
          let _ = parts.pop()
          continue
        }
      }
      parts.push("..")
    } else {
      parts.push(part)
    }
  }
  if parts.length() == 0 {
    return if is_abs { "/" } else { "." }
  }
  if parts.length() == 1 && parts[0] == "" {
    return "/"
  }
  let mut result = parts[0]
  if result == "" {
    result = "/"
  }
  for i in 1..<parts.length() {
    if result == "/" {
      result = result + parts[i]
    } else {
      result = result + "/" + parts[i]
    }
  }
  result
}

///|
fn dirname(path : String) -> String {
  match path.rev_find("/") {
    Some(idx) => path[:idx].to_string() catch { _ => "." }
    None => "."
  }
}

///|
fn is_fixture_path(path : String) -> Bool {
  path.contains("_FIXTURE.js")
}

///|
fn has_module_syntax(content : String) -> Bool {
  for line in content.split("\n") {
    let trimmed = line.trim().to_string()
    if trimmed.has_prefix("import ") || trimmed.has_prefix("export ") {
      return true
    }
  }
  false
}

///|
fn module_cache_get(
  cache : Array[(String, @runtime.JSValue)],
  path : String,
) -> @runtime.JSValue? {
  for item in cache {
    let (key, value) = item
    if key == path {
      return Some(value)
    }
  }
  None
}

///|
fn module_cache_set(
  cache : Array[(String, @runtime.JSValue)],
  path : String,
  exports : @runtime.JSValue,
) -> Unit {
  if module_cache_get(cache, path) is None {
    cache.push((path, exports))
  }
}

///|
fn resolve_module_path(base_path : String, spec : String) -> String {
  let candidate = if spec.has_prefix("./") || spec.has_prefix("../") {
    join_path(dirname(base_path), spec)
  } else {
    spec
  }
  let normalized = normalize_path(candidate)
  if normalized.has_suffix(".js") || normalized.has_suffix(".mjs") {
    return normalized
  }
  normalized + ".js"
}

///|
fn is_error_value(value : @runtime.JSValue) -> Bool {
  match value {
    @runtime.JSValue::Object(_) =>
      match @runtime.js_get_prop(value, "error") {
        @runtime.JSValue::String(_) => true
        _ => false
      }
    _ => false
  }
}

///|
fn make_export_getter(
  interp : @runtime.JSInterpreter,
  module_env : @runtime.JSEnv,
  name : String,
  module_exports? : @runtime.JSValue? = None,
) -> @runtime.JSValue {
  let getter = @runtime.js_new_native_function_with_env(
    "__export_get__",
    module_env,
    Some(interp.function_proto),
  )
  let _ = @runtime.js_set_prop(
    getter,
    "__export_name",
    @runtime.js_string(name),
  )
  match module_exports {
    Some(exports) => {
      let _ = @runtime.js_set_prop(getter, "__export_module", exports)

    }
    None => ()
  }
  getter
}

///|
fn define_export_accessors(
  interp : @runtime.JSInterpreter,
  exports : @runtime.JSValue,
  module_env : @runtime.JSEnv,
  specs : Array[@ast.TsExportSpec],
) -> Unit {
  for spec in specs {
    let getter = make_export_getter(interp, module_env, spec.local_name)
    let _ = @runtime.js_define_accessor_prop(
      exports,
      spec.export_name,
      Some(getter),
      None,
      true,
      true,
    )

  }
}

///|
fn define_reexport_accessor(
  interp : @runtime.JSInterpreter,
  exports : @runtime.JSValue,
  module_env : @runtime.JSEnv,
  dep_exports : @runtime.JSValue,
  imported : String,
  export_name : String,
) -> Unit {
  let getter = make_export_getter(
    interp,
    module_env,
    imported,
    module_exports=Some(dep_exports),
  )
  let _ = @runtime.js_define_accessor_prop(
    exports,
    export_name,
    Some(getter),
    None,
    true,
    true,
  )

}

///|
fn export_all_accessors(
  interp : @runtime.JSInterpreter,
  exports : @runtime.JSValue,
  module_env : @runtime.JSEnv,
  dep_exports : @runtime.JSValue,
) -> Unit {
  match dep_exports {
    @runtime.JSValue::Object(map) =>
      for prop in map.props {
        if prop.key != "default" {
          define_reexport_accessor(
            interp,
            exports,
            module_env,
            dep_exports,
            prop.key,
            prop.key,
          )
        }
      }
    @runtime.JSValue::Function(closure) =>
      for prop in closure.props {
        if prop.key != "default" {
          define_reexport_accessor(
            interp,
            exports,
            module_env,
            dep_exports,
            prop.key,
            prop.key,
          )
        }
      }
    _ => ()
  }
}

///|
fn define_import_bindings(
  interp : @runtime.JSInterpreter,
  module_env : @runtime.JSEnv,
  imports : Array[(@ast.TsImportDecl, @runtime.JSValue)],
) -> Unit {
  for item in imports {
    let (decl, dep_exports) = item
    if decl.side_effect_only || decl.type_only {
      continue
    }
    match decl.default_binding {
      Some(name) => {
        let value = interp.get_prop_value(dep_exports, "default")
        module_env.define_const(name, value)
      }
      None => ()
    }
    match decl.namespace_binding {
      Some(name) => module_env.define_const(name, dep_exports)
      None => ()
    }
    for item in decl.named_bindings {
      let (imported, local_name) = item
      let value = interp.get_prop_value(dep_exports, imported)
      module_env.define_const(local_name, value)
    }
  }
}

///|
fn refresh_import_bindings(
  interp : @runtime.JSInterpreter,
  module_env : @runtime.JSEnv,
  imports : Array[(@ast.TsImportDecl, @runtime.JSValue)],
) -> Unit {
  for item in imports {
    let (decl, dep_exports) = item
    if decl.side_effect_only || decl.type_only {
      continue
    }
    match decl.default_binding {
      Some(name) => {
        let value = interp.get_prop_value(dep_exports, "default")
        let _ = module_env.force_set(name, value)

      }
      None => ()
    }
    match decl.namespace_binding {
      Some(name) => {
        let _ = module_env.force_set(name, dep_exports)

      }
      None => ()
    }
    for item in decl.named_bindings {
      let (imported, local_name) = item
      let value = interp.get_prop_value(dep_exports, imported)
      let _ = module_env.force_set(local_name, value)

    }
  }
}

///|
async fn eval_module(
  interp : @runtime.JSInterpreter,
  path : String,
  cache : Array[(String, @runtime.JSValue)],
  source? : String,
) -> @runtime.JSValue raise @parser.ParseError {
  match module_cache_get(cache, path) {
    Some(exports) => return exports
    None => ()
  }
  let exports = @runtime.js_new_object()
  module_cache_set(cache, path, exports)
  let content = match source {
    Some(src) => src
    None =>
      @fs.read_file(path).text() catch {
        e => raise @parser.ParseError::ParseError("Failed to read module: \{e}")
      }
  }
  let module_block = @parser.parse_module_block_from_source(content)
  let module_env = @runtime.js_new_env(Some(interp.global_env))
  let undefined_value = interp.global_env.get("undefined")
  module_env.define_const("this", undefined_value)
  module_env.define_const("__strict__", undefined_value)
  let resolved_imports : Array[(@ast.TsImportDecl, @runtime.JSValue)] = []
  for decl in module_block.imports {
    let dep_path = resolve_module_path(path, decl.module_spec)
    let dep_exports = eval_module(interp, dep_path, cache)
    if is_error_value(dep_exports) {
      return dep_exports
    }
    resolved_imports.push((decl, dep_exports))
  }
  let resolved_reexports : Array[(@ast.TsReExportSpec, @runtime.JSValue)] = []
  for reexport in module_block.reexports {
    let dep_path = resolve_module_path(path, reexport.module_spec)
    let dep_exports = eval_module(interp, dep_path, cache)
    if is_error_value(dep_exports) {
      return dep_exports
    }
    resolved_reexports.push((reexport, dep_exports))
  }
  define_export_accessors(interp, exports, module_env, module_block.exports)
  for item in resolved_reexports {
    let (reexport, dep_exports) = item
    match reexport.kind {
      @ast.TsReExportKind::Named(items) =>
        for spec in items {
          let (imported, export_name) = spec
          define_reexport_accessor(
            interp, exports, module_env, dep_exports, imported, export_name,
          )
        }
      @ast.TsReExportKind::All =>
        export_all_accessors(interp, exports, module_env, dep_exports)
      @ast.TsReExportKind::Namespace(name) => {
        let _ = @runtime.js_set_prop(exports, name, dep_exports)

      }
    }
  }
  define_import_bindings(interp, module_env, resolved_imports)
  interp.hoist_block(module_block.block, module_env)
  refresh_import_bindings(interp, module_env, resolved_imports)
  for stmt in module_block.block.stmts {
    refresh_import_bindings(interp, module_env, resolved_imports)
    match interp.exec_stmt(stmt, module_env) {
      Some(val) => {
        if is_error_value(val) {
          return val
        }
        return val
      }
      None => ()
    }
  }
  interp.drain_microtasks()
  exports
}

///|
fn parse_bracket_list(line : String) -> Array[String] {
  let start = line.find("[")
  let end_ = line.rev_find("]")
  match (start, end_) {
    (Some(s), Some(e)) => if e <= s { return [] }
    _ => return []
  }
  let inner = try {
    match (start, end_) {
      (Some(s), Some(e)) => line[s + 1:e].to_string()
      _ => ""
    }
  } catch {
    _ => ""
  }
  let items = inner.split(",")
  let result : Array[String] = []
  for item in items {
    let trimmed = item.trim().to_string()
    if trimmed.length() == 0 {
      continue
    }
    let stripped = if trimmed.length() >= 2 &&
      trimmed.has_prefix("\"") &&
      trimmed.has_suffix("\"") {
      trimmed[1:trimmed.length() - 1].to_string() catch {
        _ => trimmed
      }
    } else {
      trimmed
    }
    result.push(stripped)
  }
  result
}

///|
fn parse_test262_meta(content : String) -> Test262Meta {
  let includes : Array[String] = []
  let flags : Array[String] = []
  let mut negative = false
  let mut negative_phase : String? = None
  let mut negative_type : String? = None
  let mut meta_block = ""
  match content.find("/*---") {
    Some(start) => {
      let rest = content[start + 5:].to_string() catch { _ => "" }
      match rest.find("---*/") {
        Some(end_) => meta_block = rest[:end_].to_string() catch { _ => "" }
        None => ()
      }
    }
    None => ()
  }
  let lines : Array[String] = []
  if meta_block.length() > 0 {
    for line in meta_block.split("\n") {
      lines.push(line.to_string())
    }
  } else {
    for line in content.split("\n") {
      let trimmed = line.trim().to_string()
      if trimmed.length() == 0 {
        continue
      }
      if not(trimmed.has_prefix("//")) {
        break
      }
      let body = trimmed[2:].trim().to_string() catch { _ => "" }
      lines.push(body)
    }
  }
  for raw in lines {
    let line = raw.trim().to_string()
    let body = if line.has_prefix("*") {
      line[1:].trim().to_string() catch {
        _ => line
      }
    } else {
      line
    }
    if body.has_prefix("includes:") {
      for item in parse_bracket_list(body) {
        includes.push(item)
      }
    } else if body.has_prefix("flags:") {
      for item in parse_bracket_list(body) {
        flags.push(item)
      }
    } else if body.has_prefix("negative:") {
      negative = true
    } else if body.has_prefix("phase:") {
      let value = body[6:].trim().to_string() catch { _ => "" }
      if value.length() > 0 {
        negative_phase = Some(value)
      }
    } else if body.has_prefix("type:") {
      let value = body[5:].trim().to_string() catch { _ => "" }
      if value.length() > 0 {
        negative_type = Some(value)
      }
    }
  }
  { includes, flags, negative, negative_phase, negative_type }
}

///|
fn contains(xs : Array[String], value : String) -> Bool {
  for item in xs {
    if item == value {
      return true
    }
  }
  false
}

///|
fn include_prelude(name : String) -> String? {
  match name {
    "assert.js" => Some("")
    "sta.js" => Some("")
    "compareArray.js" => Some("")
    "nans.js" =>
      Some(
        (
          #|let NaNs = [0/0];
        ),
      )
    "propertyHelper.js" =>
      Some(
        (
          #|var __isArray = Array.isArray;
          #|var __defineProperty = Object.defineProperty;
          #|var __getOwnPropertyDescriptor = Object.getOwnPropertyDescriptor;
          #|var __getOwnPropertyNames = Object.getOwnPropertyNames;
          #|var __join = Function.prototype.call.bind(Array.prototype.join);
          #|var __push = Function.prototype.call.bind(Array.prototype.push);
          #|var __hasOwnProperty = Function.prototype.call.bind(Object.prototype.hasOwnProperty);
          #|var __propertyIsEnumerable = Function.prototype.call.bind(Object.prototype.propertyIsEnumerable);
          #|var nonIndexNumericPropertyName = Math.pow(2, 32) - 1;
          #|function isSameValue(a, b) {
          #|  if (a === 0 && b === 0) return 1 / a === 1 / b;
          #|  if (a !== a && b !== b) return true;
          #|  return a === b;
          #|}
          #|function isConfigurable(obj, name) {
          #|  try { delete obj[name]; } catch (e) {
          #|    if (!(e instanceof TypeError)) throw new Test262Error("Expected TypeError, got " + e);
          #|  }
          #|  return !__hasOwnProperty(obj, name);
          #|}
          #|function isEnumerable(obj, name) {
          #|  var stringCheck = false;
          #|  if (typeof name === "string") {
          #|    for (var x in obj) { if (x === name) { stringCheck = true; break; } }
          #|  } else { stringCheck = true; }
          #|  return stringCheck && __hasOwnProperty(obj, name) && __propertyIsEnumerable(obj, name);
          #|}
          #|function isWritable(obj, name, verifyProp, value) {
          #|  var unlikelyValue = __isArray(obj) && name === "length" ? nonIndexNumericPropertyName : "unlikelyValue";
          #|  var newValue = value || unlikelyValue;
          #|  var hadValue = __hasOwnProperty(obj, name);
          #|  var oldValue = obj[name];
          #|  var writeSucceeded;
          #|  if (arguments.length < 4 && newValue === oldValue) { newValue = newValue + "2"; }
          #|  try { obj[name] = newValue; } catch (e) {
          #|    if (!(e instanceof TypeError)) throw new Test262Error("Expected TypeError, got " + e);
          #|  }
          #|  writeSucceeded = isSameValue(obj[verifyProp || name], newValue);
          #|  if (writeSucceeded) {
          #|    if (hadValue) { obj[name] = oldValue; } else { delete obj[name]; }
          #|  }
          #|  return writeSucceeded;
          #|}
          #|function verifyProperty(obj, name, desc, options) {
          #|  if (arguments.length < 3) { assert(false, 'verifyProperty should receive at least 3 arguments'); return false; }
          #|  var originalDesc = __getOwnPropertyDescriptor(obj, name);
          #|  var nameStr = String(name);
          #|  if (desc === undefined) {
          #|    assert.sameValue(originalDesc, undefined, "obj['" + nameStr + "'] descriptor should be undefined");
          #|    return true;
          #|  }
          #|  assert(__hasOwnProperty(obj, name), "obj should have an own property " + nameStr);
          #|  assert.notSameValue(desc, null, "The desc argument should be an object or undefined, null");
          #|  assert.sameValue(typeof desc, "object", "The desc argument should be an object or undefined, " + String(desc));
          #|  var names = __getOwnPropertyNames(desc);
          #|  for (var i = 0; i < names.length; i++) {
          #|    assert(names[i] === "value" || names[i] === "writable" || names[i] === "enumerable" || names[i] === "configurable" || names[i] === "get" || names[i] === "set", "Invalid descriptor field: " + names[i]);
          #|  }
          #|  var failures = [];
          #|  if (__hasOwnProperty(desc, 'value')) {
          #|    if (!isSameValue(desc.value, originalDesc.value)) { __push(failures, "obj['" + nameStr + "'] descriptor value should be " + desc.value); }
          #|    if (!isSameValue(desc.value, obj[name])) { __push(failures, "obj['" + nameStr + "'] value should be " + desc.value); }
          #|  }
          #|  if (__hasOwnProperty(desc, 'enumerable') && desc.enumerable !== undefined) {
          #|    if (desc.enumerable !== originalDesc.enumerable || desc.enumerable !== isEnumerable(obj, name)) {
          #|      __push(failures, "obj['" + nameStr + "'] descriptor should " + (desc.enumerable ? '' : 'not ') + "be enumerable");
          #|    }
          #|  }
          #|  if (__hasOwnProperty(desc, 'writable') && desc.writable !== undefined) {
          #|    if (desc.writable !== originalDesc.writable || desc.writable !== isWritable(obj, name)) {
          #|      __push(failures, "obj['" + nameStr + "'] descriptor should " + (desc.writable ? '' : 'not ') + "be writable");
          #|    }
          #|  }
          #|  if (__hasOwnProperty(desc, 'configurable') && desc.configurable !== undefined) {
          #|    if (desc.configurable !== originalDesc.configurable || desc.configurable !== isConfigurable(obj, name)) {
          #|      __push(failures, "obj['" + nameStr + "'] descriptor should " + (desc.configurable ? '' : 'not ') + "be configurable");
          #|    }
          #|  }
          #|  if (failures.length) { assert(false, __join(failures, '; ')); }
          #|  if (options && options.restore) { __defineProperty(obj, name, originalDesc); }
          #|  return true;
          #|}
          #|function verifyCallableProperty(obj, name, functionName, functionLength, desc, options) {
          #|  var value = obj[name];
          #|  assert.sameValue(typeof value, "function", "obj['" + String(name) + "'] descriptor should be a function");
          #|  if (desc === undefined) { desc = { writable: true, enumerable: false, configurable: true, value: value }; }
          #|  else if (!__hasOwnProperty(desc, "value") && !__hasOwnProperty(desc, "get")) { desc.value = value; }
          #|  verifyProperty(obj, name, desc, options);
          #|  if (functionName === undefined) {
          #|    if (typeof name === "symbol") { functionName = "[" + name.description + "]"; } else { functionName = name; }
          #|  }
          #|  verifyProperty(value, "name", { value: functionName, writable: false, enumerable: false, configurable: desc.configurable }, options);
          #|  verifyProperty(value, "length", { value: functionLength, writable: false, enumerable: false, configurable: desc.configurable }, options);
          #|}
          #|function verifyEqualTo(obj, name, value) { if (!isSameValue(obj[name], value)) throw new Test262Error("Expected obj[" + String(name) + "] to equal " + value + ", actually " + obj[name]); }
          #|function verifyWritable(obj, name, verifyProp, value) {
          #|  if (!verifyProp) { assert(__getOwnPropertyDescriptor(obj, name).writable, "Expected obj[" + String(name) + "] to have writable:true."); }
          #|  if (!isWritable(obj, name, verifyProp, value)) throw new Test262Error("Expected obj[" + String(name) + "] to be writable, but was not.");
          #|}
          #|function verifyNotWritable(obj, name, verifyProp, value) {
          #|  if (!verifyProp) { assert(!__getOwnPropertyDescriptor(obj, name).writable, "Expected obj[" + String(name) + "] to have writable:false."); }
          #|  if (isWritable(obj, name, verifyProp)) throw new Test262Error("Expected obj[" + String(name) + "] NOT to be writable, but was.");
          #|}
          #|function verifyEnumerable(obj, name) {
          #|  assert(__getOwnPropertyDescriptor(obj, name).enumerable, "Expected obj[" + String(name) + "] to have enumerable:true.");
          #|  if (!isEnumerable(obj, name)) throw new Test262Error("Expected obj[" + String(name) + "] to be enumerable, but was not.");
          #|}
          #|function verifyNotEnumerable(obj, name) {
          #|  assert(!__getOwnPropertyDescriptor(obj, name).enumerable, "Expected obj[" + String(name) + "] to have enumerable:false.");
          #|  if (isEnumerable(obj, name)) throw new Test262Error("Expected obj[" + String(name) + "] NOT to be enumerable, but was.");
          #|}
          #|function verifyConfigurable(obj, name) {
          #|  assert(__getOwnPropertyDescriptor(obj, name).configurable, "Expected obj[" + String(name) + "] to have configurable:true.");
          #|  if (!isConfigurable(obj, name)) throw new Test262Error("Expected obj[" + String(name) + "] to be configurable, but was not.");
          #|}
          #|function verifyNotConfigurable(obj, name) {
          #|  assert(!__getOwnPropertyDescriptor(obj, name).configurable, "Expected obj[" + String(name) + "] to have configurable:false.");
          #|  if (isConfigurable(obj, name)) throw new Test262Error("Expected obj[" + String(name) + "] NOT to be configurable, but was.");
          #|}
          #|var verifyPrimordialProperty = verifyProperty;
          #|var verifyPrimordialCallableProperty = verifyCallableProperty;
        ),
      )
    "fnGlobalObject.js" =>
      Some(
        (
          #|var __globalObject = Function("return this;")();
          #|function fnGlobalObject() { return __globalObject; }
        ),
      )
    "isConstructor.js" =>
      Some(
        (
          #|function isConstructor(f) {
          #|  if (typeof f !== "function") { throw new Test262Error("isConstructor invoked with a non-function value"); }
          #|  try { Reflect.construct(function(){}, [], f); } catch (e) { return false; }
          #|  return true;
          #|}
        ),
      )
    "deepEqual.js" =>
      Some(
        (
          #|function deepEqual(a, b) {
          #|  if (a === b) return true;
          #|  if (typeof a !== typeof b) return false;
          #|  if (typeof a !== "object" || a === null || b === null) return false;
          #|  var keysA = Object.keys(a), keysB = Object.keys(b);
          #|  if (keysA.length !== keysB.length) return false;
          #|  for (var i = 0; i < keysA.length; i++) {
          #|    if (!deepEqual(a[keysA[i]], b[keysA[i]])) return false;
          #|  }
          #|  return true;
          #|}
          #|assert.deepEqual = function(actual, expected, message) {
          #|  if (!deepEqual(actual, expected)) {
          #|    throw new Test262Error(message || "deepEqual assertion failed");
          #|  }
          #|};
        ),
      )
    "decimalToHexString.js" =>
      Some(
        (
          #|function decimalToHexString(n) {
          #|  var hex = "0123456789ABCDEF";
          #|  n >>>= 0;
          #|  var s = "";
          #|  while (n) { s = hex[n & 0xf] + s; n >>>= 4; }
          #|  while (s.length < 4) { s = "0" + s; }
          #|  return s;
          #|}
          #|function decimalToPercentHexString(n) {
          #|  var hex = "0123456789ABCDEF";
          #|  return "%" + hex[(n >> 4) & 0xf] + hex[n & 0xf];
          #|}
        ),
      )
    "proxyTrapsHelper.js" =>
      Some(
        (
          #|function allowProxyTraps(overrides) {
          #|  function throwTest262Error(msg) { return function () { throw new Test262Error(msg); }; }
          #|  if (!overrides) { overrides = {}; }
          #|  return {
          #|    getPrototypeOf: overrides.getPrototypeOf || throwTest262Error('[[GetPrototypeOf]] trap called'),
          #|    setPrototypeOf: overrides.setPrototypeOf || throwTest262Error('[[SetPrototypeOf]] trap called'),
          #|    isExtensible: overrides.isExtensible || throwTest262Error('[[IsExtensible]] trap called'),
          #|    preventExtensions: overrides.preventExtensions || throwTest262Error('[[PreventExtensions]] trap called'),
          #|    getOwnPropertyDescriptor: overrides.getOwnPropertyDescriptor || throwTest262Error('[[GetOwnProperty]] trap called'),
          #|    has: overrides.has || throwTest262Error('[[HasProperty]] trap called'),
          #|    get: overrides.get || throwTest262Error('[[Get]] trap called'),
          #|    set: overrides.set || throwTest262Error('[[Set]] trap called'),
          #|    deleteProperty: overrides.deleteProperty || throwTest262Error('[[Delete]] trap called'),
          #|    defineProperty: overrides.defineProperty || throwTest262Error('[[DefineOwnProperty]] trap called'),
          #|    enumerate: throwTest262Error('[[Enumerate]] trap called: this trap has been removed'),
          #|    ownKeys: overrides.ownKeys || throwTest262Error('[[OwnPropertyKeys]] trap called'),
          #|    apply: overrides.apply || throwTest262Error('[[Call]] trap called'),
          #|    construct: overrides.construct || throwTest262Error('[[Construct]] trap called')
          #|  };
          #|}
        ),
      )
    "asyncHelpers.js" =>
      Some(
        (
          #|function asyncTest(testFunc) {
          #|  if (!Object.prototype.hasOwnProperty.call(globalThis, "$DONE")) {
          #|    throw new Test262Error("asyncTest called without async flag");
          #|  }
          #|  if (typeof testFunc !== "function") {
          #|    $DONE(new Test262Error("asyncTest called with non-function argument"));
          #|    return;
          #|  }
          #|  try {
          #|    testFunc().then(function () { $DONE(); }, function (error) { $DONE(error); });
          #|  } catch (syncError) { $DONE(syncError); }
          #|}
          #|assert.throwsAsync = function (expectedErrorConstructor, func, message) {
          #|  return new Promise(function (resolve) {
          #|    var fail = function (detail) {
          #|      if (message === undefined) { throw new Test262Error(detail); }
          #|      throw new Test262Error(message + " " + detail);
          #|    };
          #|    if (typeof expectedErrorConstructor !== "function") {
          #|      fail("assert.throwsAsync called with an argument that is not an error constructor");
          #|    }
          #|    if (typeof func !== "function") {
          #|      fail("assert.throwsAsync called with an argument that is not a function");
          #|    }
          #|    var expectedName = expectedErrorConstructor.name;
          #|    var expectation = "Expected a " + expectedName + " to be thrown asynchronously";
          #|    var res;
          #|    try { res = func(); } catch (thrown) { fail(expectation + " but the function threw synchronously"); }
          #|    if (res === null || typeof res !== "object" || typeof res.then !== "function") {
          #|      fail(expectation + " but result was not a thenable");
          #|    }
          #|    var onResFulfilled, onResRejected;
          #|    var resSettlementP = new Promise(function (onFulfilled, onRejected) {
          #|      onResFulfilled = onFulfilled;
          #|      onResRejected = onRejected;
          #|    });
          #|    try { res.then(onResFulfilled, onResRejected); } catch (thrown) {
          #|      fail(expectation + " but .then threw synchronously");
          #|    }
          #|    resolve(resSettlementP.then(
          #|      function () { fail(expectation + " but no exception was thrown at all"); },
          #|      function (thrown) {
          #|        var actualName;
          #|        if (thrown === null || typeof thrown !== "object") {
          #|          fail(expectation + " but thrown value was not an object");
          #|        } else if (thrown.constructor !== expectedErrorConstructor) {
          #|          actualName = thrown.constructor.name;
          #|          if (expectedName === actualName) {
          #|            fail(expectation + " but got a different error constructor with the same name");
          #|          }
          #|          fail(expectation + " but got a " + actualName);
          #|        }
          #|      }
          #|    ));
          #|  });
          #|};
        ),
      )
    "testTypedArray.js" => Some("")
    "detachArrayBuffer.js" => Some("")
    "testBigIntTypedArray.js" => Some("")
    _ => None
  }
}

///|
fn build_includes(includes : Array[String]) -> (String, Array[String]) {
  let mut prelude = ""
  let missing : Array[String] = []
  for inc in includes {
    match include_prelude(inc) {
      Some(code) => if code.length() > 0 { prelude = prelude + code + "\n" }
      None => missing.push(inc)
    }
  }
  (prelude, missing)
}

///|
fn should_skip_test(meta : Test262Meta, content : String) -> String? {
  // async tests are now supported - no longer skipping
  let is_module = contains(meta.flags, "module")
  for line in content.split("\n") {
    let trimmed = line.trim().to_string()
    if !is_module &&
      (trimmed.has_prefix("import ") || trimmed.has_prefix("export ")) {
      return Some("module syntax")
    }
    if trimmed.has_prefix("with ") || trimmed.has_prefix("with(") {
      return Some("with statement not supported")
    }
  }
  None
}

///|
fn normalize_negative_phase(phase : String?) -> String? {
  match phase {
    Some(value) => if value == "early" { Some("parse") } else { Some(value) }
    None => None
  }
}

///|
fn negative_phase_matches(
  expected_phase : String?,
  actual_phase : String,
) -> Bool {
  match normalize_negative_phase(expected_phase) {
    Some(value) => value == actual_phase
    None => true
  }
}

///|
fn get_error_name(value : @runtime.JSValue) -> String? {
  match value {
    @runtime.JSValue::Object(_) =>
      match @runtime.js_get_prop(value, "name") {
        @runtime.JSValue::String(name) => Some(name)
        _ => None
      }
    @runtime.JSValue::Function(_) =>
      match @runtime.js_get_prop(value, "name") {
        @runtime.JSValue::String(name) => Some(name)
        _ => None
      }
    _ => None
  }
}

///|
fn option_or_empty(value : String?) -> String {
  match value {
    Some(v) => v
    None => ""
  }
}

///|
fn negative_type_matches(
  expected_type : String?,
  actual_phase : String,
  error_value : @runtime.JSValue?,
) -> Bool {
  match expected_type {
    None => true
    Some(kind) =>
      if actual_phase == "parse" {
        kind == "SyntaxError"
      } else {
        match error_value {
          Some(value) =>
            match get_error_name(value) {
              Some(name) => name == kind
              None => false
            }
          None => false
        }
      }
  }
}

///|
async fn collect_test_files(path : String, out : Array[String]) -> Unit {
  let kind = @fs.kind(path, follow_symlink=false) catch {
    _ => @fs.FileKind::Unknown
  }
  match kind {
    @fs.FileKind::Directory => {
      let entries = @fs.readdir(
        path,
        include_hidden=false,
        include_special=false,
        sort=true,
      ) catch {
        _ => []
      }
      for name in entries {
        if name == "harness" {
          continue
        }
        let child = join_path(path, name)
        collect_test_files(child, out)
      }
    }
    @fs.FileKind::Regular => if path.has_suffix(".js") { out.push(path) }
    _ => ()
  }
}

///|
fn wrap_test_source(source : String) -> String {
  "function main() {\n" + source + "\n}"
}

///|
fn load_test_list(content : String) -> Array[String] {
  let result : Array[String] = []
  for line in content.split("\n") {
    let trimmed = line.trim().to_string()
    if trimmed.length() == 0 {
      continue
    }
    if trimmed.has_prefix("#") {
      continue
    }
    result.push(trimmed)
  }
  result
}

///|
fn has_glob_meta(pattern : String) -> Bool {
  for c in pattern {
    if c == '*' || c == '?' {
      return true
    }
  }
  false
}

///|
fn split_patterns(patterns : Array[String]) -> (Array[String], Array[String]) {
  let includes : Array[String] = []
  let excludes : Array[String] = []
  for pat in patterns {
    if pat.has_prefix("!") {
      let sub = pat[1:].to_string() catch { _ => "" }
      if sub.length() > 0 {
        excludes.push(sub)
      }
    } else {
      includes.push(pat)
    }
  }
  (includes, excludes)
}

///|
fn match_segment(pat : String, seg : String) -> Bool {
  let pchars : Array[Char] = []
  let schars : Array[Char] = []
  for c in pat {
    pchars.push(c)
  }
  for c in seg {
    schars.push(c)
  }
  fn rec(
    pchars : Array[Char],
    schars : Array[Char],
    pi : Int,
    si : Int,
  ) -> Bool {
    if pi >= pchars.length() {
      return si >= schars.length()
    }
    let pc = pchars[pi]
    if pc == '*' {
      let mut k = si
      while k <= schars.length() {
        if rec(pchars, schars, pi + 1, k) {
          return true
        }
        k += 1
      }
      return false
    }
    if pc == '?' {
      if si < schars.length() {
        return rec(pchars, schars, pi + 1, si + 1)
      }
      return false
    }
    if si < schars.length() && pc == schars[si] {
      return rec(pchars, schars, pi + 1, si + 1)
    }
    false
  }

  rec(pchars, schars, 0, 0)
}

///|
fn split_path_parts(path : String) -> Array[String] {
  let parts : Array[String] = []
  for part in path.split("/") {
    let s = part.to_string()
    parts.push(s)
  }
  parts
}

///|
fn glob_match(pattern : String, path : String) -> Bool {
  let pparts = split_path_parts(pattern)
  let sparts = split_path_parts(path)
  fn rec(
    pparts : Array[String],
    sparts : Array[String],
    pi : Int,
    si : Int,
  ) -> Bool {
    if pi >= pparts.length() {
      return si >= sparts.length()
    }
    let part = pparts[pi]
    if part == "**" {
      if pi + 1 >= pparts.length() {
        return true
      }
      let mut k = si
      while k <= sparts.length() {
        if rec(pparts, sparts, pi + 1, k) {
          return true
        }
        k += 1
      }
      return false
    }
    if si >= sparts.length() {
      return false
    }
    if match_segment(part, sparts[si]) {
      return rec(pparts, sparts, pi + 1, si + 1)
    }
    false
  }

  rec(pparts, sparts, 0, 0)
}

///|
fn matches_any(patterns : Array[String], path : String) -> Bool {
  for pat in patterns {
    if has_glob_meta(pat) {
      if glob_match(pat, path) {
        return true
      }
    } else if pat == path {
      return true
    }
  }
  false
}

///|
async fn run_test262(test_path : String) -> Unit {
  let files : Array[String] = []
  let kind = @fs.kind(test_path, follow_symlink=false) catch {
    _ => @fs.FileKind::Unknown
  }
  match kind {
    @fs.FileKind::Directory => collect_test_files(test_path, files)
    @fs.FileKind::Regular =>
      if test_path.has_suffix(".txt") {
        let list_content = @fs.read_file(test_path).text() catch {
          e => {
            println("Error reading test list: \{e}")
            return
          }
        }
        let patterns = load_test_list(list_content)
        let mut use_glob = false
        for pat in patterns {
          if pat.has_prefix("!") || has_glob_meta(pat) {
            use_glob = true
            break
          }
        }
        if use_glob {
          let (includes, excludes) = split_patterns(patterns)
          let candidates : Array[String] = []
          let base = "test262/test"
          collect_test_files(base, candidates)
          for path in candidates {
            if matches_any(includes, path) && not(matches_any(excludes, path)) {
              files.push(path)
            }
          }
        } else {
          for path in patterns {
            files.push(path)
          }
        }
      } else {
        files.push(test_path)
      }
    _ => {
      println("Error: test path not found: \{test_path}")
      return
    }
  }
  let total_files = files.length()
  let progress_interval = 200
  let per_test_step_limit = 10_000_000
  let mut passed = 0
  let mut failed = 0
  let mut skipped = 0
  for i, path in files {
    let _ = @fs.write_file(
      "test262.current.txt",
      @utf8.encode(path),
      create=0o644,
    ) catch {
      _ => ()
    }
    if is_fixture_path(path) {
      skipped += 1
      println("SKIP: \{path} (fixture)")
      continue
    }
    let content = @fs.read_file(path).text() catch {
      e => {
        failed += 1
        println("ERROR: \{path} - \{e}")
        continue
      }
    }
    let meta = parse_test262_meta(content)
    let (include_src, missing_includes) = build_includes(meta.includes)
    if missing_includes.length() > 0 {
      skipped += 1
      let missing_list = missing_includes.join(", ")
      println("SKIP: \{path} (missing includes: \{missing_list})")
      continue
    }
    match should_skip_test(meta, content) {
      Some(reason) => {
        skipped += 1
        println("SKIP: \{path} (\{reason})")
        continue
      }
      None => ()
    }
    let interp = @runtime.JSInterpreter::new()
    interp.set_step_limit(per_test_step_limit)
    let undefined_value = interp.global_env.get("undefined")
    let is_module = contains(meta.flags, "module") || has_module_syntax(content)
    let mut result = undefined_value
    let mut has_error = false
    let mut error_phase = ""
    let mut error_message = ""
    if is_module {
      if include_src.length() > 0 {
        let wrapped_inc = wrap_test_source(include_src)
        let _ = interp.run(wrapped_inc) catch {
          e => {
            has_error = true
            error_phase = "parse"
            error_message = "\{e}"
            undefined_value
          }
        }

      }
      if not(has_error) {
        let module_cache : Array[(String, @runtime.JSValue)] = []
        result = eval_module(interp, path, module_cache, source=content) catch {
          e => {
            has_error = true
            error_phase = "parse"
            error_message = "\{e}"
            undefined_value
          }
        }
      }
    } else {
      let mut source = include_src + content
      if contains(meta.flags, "onlyStrict") {
        source = "\"use strict\";\n" + source
      }
      // For negative parse tests, first try to parse the source directly
      // to catch SyntaxErrors that wouldn't be caught inside a function wrapper
      if meta.negative && option_or_empty(meta.negative_phase) == "parse" {
        let parser = @parser.Parser::from_source(source)
        try {
          let _ = parser.parse_module()

        } catch {
          e => {
            has_error = true
            error_phase = "parse"
            error_message = "\{e}"
          }
        }
      }
      if not(has_error) {
        let wrapped = wrap_test_source(source)
        result = interp.run(wrapped) catch {
          e => {
            has_error = true
            error_phase = "parse"
            error_message = "\{e}"
            undefined_value
          }
        }
      }
    }
    if has_error {
      if meta.negative {
        let phase_ok = negative_phase_matches(meta.negative_phase, error_phase)
        let type_ok = negative_type_matches(
          meta.negative_type,
          error_phase,
          None,
        )
        if phase_ok && type_ok {
          passed += 1
        } else {
          failed += 1
          let expected_phase = option_or_empty(meta.negative_phase)
          let expected_type = option_or_empty(meta.negative_type)
          println(
            "FAIL: \{path} - negative mismatch (phase=\{expected_phase}, type=\{expected_type}, got=\{error_phase})",
          )
        }
      } else {
        failed += 1
        println("ERROR: \{path} - \{error_message}")
      }
      continue
    }
    let mut runtime_error : @runtime.JSValue? = None
    if is_error_value(result) {
      runtime_error = Some(result)
    }
    // For async tests, also check last_error from $DONE(error)
    match runtime_error {
      Some(_) => ()
      None =>
        match interp.get_last_error() {
          Some(err) => runtime_error = Some(err)
          None => ()
        }
    }
    if meta.negative {
      match runtime_error {
        Some(err_value) => {
          let phase_ok = negative_phase_matches(meta.negative_phase, "runtime")
          let type_ok = negative_type_matches(
            meta.negative_type,
            "runtime",
            Some(err_value),
          )
          if phase_ok && type_ok {
            passed += 1
          } else {
            failed += 1
            let expected_phase = option_or_empty(meta.negative_phase)
            let expected_type = option_or_empty(meta.negative_type)
            let actual_name = option_or_empty(get_error_name(err_value))
            println(
              "FAIL: \{path} - negative mismatch (phase=\{expected_phase}, type=\{expected_type}, got=runtime/\{actual_name})",
            )
          }
        }
        None => {
          failed += 1
          println("FAIL: \{path} - negative test did not throw")
        }
      }
    } else {
      match runtime_error {
        Some(err_value) =>
          match @runtime.js_get_prop(err_value, "error") {
            @runtime.JSValue::String(msg) => {
              failed += 1
              println("FAIL: \{path} - \{msg}")
            }
            _ => {
              failed += 1
              println("FAIL: \{path} - runtime error")
            }
          }
        None => passed += 1
      }
    }
    let _ = @fs.write_file(
      "test262.last_done.txt",
      @utf8.encode(path),
      create=0o644,
    ) catch {
      _ => ()
    }
    let done = i + 1
    if done % progress_interval == 0 || done == total_files {
      println(
        "test262 progress: \{done}/\{total_files} (passed=\{passed}, failed=\{failed}, skipped=\{skipped})",
      )
    }
  }
  println(
    "test262 results: total=\{total_files}, passed=\{passed}, failed=\{failed}, skipped=\{skipped}",
  )
}
