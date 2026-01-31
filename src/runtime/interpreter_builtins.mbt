///|
fn JSInterpreter::install_collections(
  self : JSInterpreter,
  global_obj : JSValue,
) -> Unit {
  // Map
  let map_ctor = self.make_native("Map")
  self.set_function_length(map_ctor, 0.0)
  self.set_function_name(map_ctor, "Map")
  let map_proto = self.new_object()
  set_proto_method(map_proto, "get", self.make_native("Map.prototype.get"))
  set_proto_method(map_proto, "set", self.make_native("Map.prototype.set"))
  set_proto_method(map_proto, "has", self.make_native("Map.prototype.has"))
  set_proto_method(map_proto, "delete", self.make_native("Map.prototype.delete"))
  set_proto_method(map_proto, "clear", self.make_native("Map.prototype.clear"))
  set_proto_method(map_proto, "keys", self.make_native("Map.prototype.keys"))
  set_proto_method(map_proto, "values", self.make_native("Map.prototype.values"))
  set_proto_method(map_proto, "entries", self.make_native("Map.prototype.entries"))
  set_proto_method(map_proto, "forEach", self.make_native("Map.prototype.forEach"))
  set_proto_method(map_proto, "@@iterator", self.make_native("Map.prototype.entries"))
  let _ = js_define_data_prop(
    map_ctor, "prototype", map_proto, true, false, true,
  )
  self.global_env.define_var("Map", map_ctor)
  set_global_ctor(global_obj, "Map", map_ctor)

  // Set
  let set_ctor = self.make_native("Set")
  self.set_function_length(set_ctor, 0.0)
  self.set_function_name(set_ctor, "Set")
  let set_proto = self.new_object()
  set_proto_method(set_proto, "add", self.make_native("Set.prototype.add"))
  set_proto_method(set_proto, "has", self.make_native("Set.prototype.has"))
  set_proto_method(set_proto, "delete", self.make_native("Set.prototype.delete"))
  set_proto_method(set_proto, "clear", self.make_native("Set.prototype.clear"))
  set_proto_method(set_proto, "keys", self.make_native("Set.prototype.values"))
  set_proto_method(set_proto, "values", self.make_native("Set.prototype.values"))
  set_proto_method(set_proto, "entries", self.make_native("Set.prototype.entries"))
  set_proto_method(set_proto, "forEach", self.make_native("Set.prototype.forEach"))
  set_proto_method(set_proto, "@@iterator", self.make_native("Set.prototype.values"))
  let _ = js_define_data_prop(
    set_ctor, "prototype", set_proto, true, false, true,
  )
  self.global_env.define_var("Set", set_ctor)
  set_global_ctor(global_obj, "Set", set_ctor)

  // WeakMap
  let weakmap_ctor = self.make_native("WeakMap")
  self.set_function_length(weakmap_ctor, 0.0)
  self.set_function_name(weakmap_ctor, "WeakMap")
  let weakmap_proto = self.new_object()
  set_proto_method(weakmap_proto, "get", self.make_native("WeakMap.prototype.get"))
  set_proto_method(weakmap_proto, "set", self.make_native("WeakMap.prototype.set"))
  set_proto_method(weakmap_proto, "has", self.make_native("WeakMap.prototype.has"))
  set_proto_method(weakmap_proto, "delete", self.make_native("WeakMap.prototype.delete"))
  let _ = js_define_data_prop(
    weakmap_ctor, "prototype", weakmap_proto, true, false, true,
  )
  self.global_env.define_var("WeakMap", weakmap_ctor)
  set_global_ctor(global_obj, "WeakMap", weakmap_ctor)

  // WeakSet
  let weakset_ctor = self.make_native("WeakSet")
  self.set_function_length(weakset_ctor, 0.0)
  self.set_function_name(weakset_ctor, "WeakSet")
  let weakset_proto = self.new_object()
  set_proto_method(weakset_proto, "add", self.make_native("WeakSet.prototype.add"))
  set_proto_method(weakset_proto, "has", self.make_native("WeakSet.prototype.has"))
  set_proto_method(weakset_proto, "delete", self.make_native("WeakSet.prototype.delete"))
  let _ = js_define_data_prop(
    weakset_ctor, "prototype", weakset_proto, true, false, true,
  )
  self.global_env.define_var("WeakSet", weakset_ctor)
  set_global_ctor(global_obj, "WeakSet", weakset_ctor)

  // FinalizationRegistry
  let fr_ctor = self.make_native("FinalizationRegistry")
  self.set_function_length(fr_ctor, 1.0)
  self.set_function_name(fr_ctor, "FinalizationRegistry")
  let fr_proto = self.new_object()
  set_proto_method(fr_proto, "register", self.make_native("FinalizationRegistry.prototype.register"))
  set_proto_method(fr_proto, "unregister", self.make_native("FinalizationRegistry.prototype.unregister"))
  set_proto_method(fr_proto, "cleanupSome", self.make_native("FinalizationRegistry.prototype.cleanupSome"))
  let _ = js_define_data_prop(fr_ctor, "prototype", fr_proto, true, false, true)
  self.global_env.define_var("FinalizationRegistry", fr_ctor)
  set_global_ctor(global_obj, "FinalizationRegistry", fr_ctor)

  // WeakRef
  let weakref_ctor = self.make_native("WeakRef")
  self.set_function_length(weakref_ctor, 1.0)
  self.set_function_name(weakref_ctor, "WeakRef")
  let weakref_proto = self.new_object()
  set_proto_method(weakref_proto, "deref", self.make_native("WeakRef.prototype.deref"))
  let _ = js_define_data_prop(
    weakref_ctor, "prototype", weakref_proto, true, false, true,
  )
  self.global_env.define_var("WeakRef", weakref_ctor)
  set_global_ctor(global_obj, "WeakRef", weakref_ctor)

  // ArrayBuffer
  let ab_ctor = self.make_native("ArrayBuffer")
  self.set_function_length(ab_ctor, 1.0)
  self.set_function_name(ab_ctor, "ArrayBuffer")
  let ab_proto = self.new_object()
  // ArrayBuffer.prototype.byteLength getter
  let ab_bytelength_get = self.make_native("ArrayBuffer.prototype.byteLength")
  self.set_function_length(ab_bytelength_get, 0.0)
  self.set_function_name(ab_bytelength_get, "get byteLength")
  let _ = js_define_accessor_prop(
    ab_proto,
    "byteLength",
    Some(ab_bytelength_get),
    None,
    false,
    true,
  )
  // ArrayBuffer.prototype.maxByteLength getter
  let ab_maxbytelength_get = self.make_native(
    "ArrayBuffer.prototype.maxByteLength",
  )
  self.set_function_length(ab_maxbytelength_get, 0.0)
  self.set_function_name(ab_maxbytelength_get, "get maxByteLength")
  let _ = js_define_accessor_prop(
    ab_proto,
    "maxByteLength",
    Some(ab_maxbytelength_get),
    None,
    false,
    true,
  )
  // ArrayBuffer.prototype.resizable getter
  let ab_resizable_get = self.make_native("ArrayBuffer.prototype.resizable")
  self.set_function_length(ab_resizable_get, 0.0)
  self.set_function_name(ab_resizable_get, "get resizable")
  let _ = js_define_accessor_prop(
    ab_proto,
    "resizable",
    Some(ab_resizable_get),
    None,
    false,
    true,
  )
  // ArrayBuffer.prototype.detached getter
  let ab_detached_get = self.make_native("ArrayBuffer.prototype.detached")
  self.set_function_length(ab_detached_get, 0.0)
  self.set_function_name(ab_detached_get, "get detached")
  let _ = js_define_accessor_prop(
    ab_proto,
    "detached",
    Some(ab_detached_get),
    None,
    false,
    true,
  )
  // ArrayBuffer.prototype methods
  let ab_slice = self.make_native("ArrayBuffer.prototype.slice")
  self.set_function_length(ab_slice, 2.0)
  self.set_function_name(ab_slice, "slice")
  set_proto_method(ab_proto, "slice", ab_slice)
  let ab_resize = self.make_native("ArrayBuffer.prototype.resize")
  self.set_function_length(ab_resize, 1.0)
  self.set_function_name(ab_resize, "resize")
  set_proto_method(ab_proto, "resize", ab_resize)
  let ab_transfer = self.make_native("ArrayBuffer.prototype.transfer")
  self.set_function_length(ab_transfer, 0.0)
  self.set_function_name(ab_transfer, "transfer")
  set_proto_method(ab_proto, "transfer", ab_transfer)
  let ab_transfer_fixed = self.make_native(
    "ArrayBuffer.prototype.transferToFixedLength",
  )
  self.set_function_length(ab_transfer_fixed, 0.0)
  self.set_function_name(ab_transfer_fixed, "transferToFixedLength")
  set_proto_method(ab_proto, "transferToFixedLength", ab_transfer_fixed)
  // ArrayBuffer.prototype[@@toStringTag]
  let _ = js_define_data_prop(
    ab_proto,
    "@@toStringTag",
    String("ArrayBuffer"),
    false,
    false,
    true,
  )
  let _ = js_define_data_prop(ab_ctor, "prototype", ab_proto, true, false, true)
  set_proto_method(ab_ctor, "isView", self.make_native("ArrayBuffer.isView"))
  self.global_env.define_var("ArrayBuffer", ab_ctor)
  set_global_ctor(global_obj, "ArrayBuffer", ab_ctor)

  // DataView
  let dv_ctor = self.make_native("DataView")
  self.set_function_length(dv_ctor, 1.0)
  self.set_function_name(dv_ctor, "DataView")
  let dv_proto = self.new_object()
  // DataView.prototype getters
  let dv_buffer_get = self.make_native("DataView.prototype.buffer")
  self.set_function_length(dv_buffer_get, 0.0)
  self.set_function_name(dv_buffer_get, "get buffer")
  let _ = js_define_accessor_prop(
    dv_proto,
    "buffer",
    Some(dv_buffer_get),
    None,
    false,
    true,
  )
  let dv_bytelength_get = self.make_native("DataView.prototype.byteLength")
  self.set_function_length(dv_bytelength_get, 0.0)
  self.set_function_name(dv_bytelength_get, "get byteLength")
  let _ = js_define_accessor_prop(
    dv_proto,
    "byteLength",
    Some(dv_bytelength_get),
    None,
    false,
    true,
  )
  let dv_byteoffset_get = self.make_native("DataView.prototype.byteOffset")
  self.set_function_length(dv_byteoffset_get, 0.0)
  self.set_function_name(dv_byteoffset_get, "get byteOffset")
  let _ = js_define_accessor_prop(
    dv_proto,
    "byteOffset",
    Some(dv_byteoffset_get),
    None,
    false,
    true,
  )
  // DataView.prototype methods
  set_proto_method(dv_proto, "getInt8", self.make_native("DataView.prototype.getInt8"))
  set_proto_method(dv_proto, "getUint8", self.make_native("DataView.prototype.getUint8"))
  set_proto_method(dv_proto, "getInt16", self.make_native("DataView.prototype.getInt16"))
  set_proto_method(dv_proto, "getUint16", self.make_native("DataView.prototype.getUint16"))
  set_proto_method(dv_proto, "getInt32", self.make_native("DataView.prototype.getInt32"))
  set_proto_method(dv_proto, "getUint32", self.make_native("DataView.prototype.getUint32"))
  set_proto_method(dv_proto, "getFloat32", self.make_native("DataView.prototype.getFloat32"))
  set_proto_method(dv_proto, "getFloat64", self.make_native("DataView.prototype.getFloat64"))
  set_proto_method(dv_proto, "setInt8", self.make_native("DataView.prototype.setInt8"))
  set_proto_method(dv_proto, "setUint8", self.make_native("DataView.prototype.setUint8"))
  set_proto_method(dv_proto, "setInt16", self.make_native("DataView.prototype.setInt16"))
  set_proto_method(dv_proto, "setUint16", self.make_native("DataView.prototype.setUint16"))
  set_proto_method(dv_proto, "setInt32", self.make_native("DataView.prototype.setInt32"))
  set_proto_method(dv_proto, "setUint32", self.make_native("DataView.prototype.setUint32"))
  set_proto_method(dv_proto, "setFloat32", self.make_native("DataView.prototype.setFloat32"))
  set_proto_method(dv_proto, "setFloat64", self.make_native("DataView.prototype.setFloat64"))
  // DataView.prototype[@@toStringTag]
  let _ = js_define_data_prop(
    dv_proto,
    "@@toStringTag",
    String("DataView"),
    false,
    false,
    true,
  )
  let _ = js_define_data_prop(dv_ctor, "prototype", dv_proto, true, false, true)
  self.global_env.define_var("DataView", dv_ctor)
  set_global_ctor(global_obj, "DataView", dv_ctor)

  // Create abstract %TypedArray% intrinsic first
  let typed_array_ctor = self.make_native("TypedArray")
  self.set_function_length(typed_array_ctor, 0.0)
  self.set_function_name(typed_array_ctor, "TypedArray")
  let typed_array_proto = self.new_object()
  // TypedArray.prototype methods (shared by all typed arrays)
  self.install_method(typed_array_proto, "set", "TypedArray.prototype.set", 1.0)
  self.install_method(
    typed_array_proto, "subarray", "TypedArray.prototype.subarray", 2.0,
  )
  self.install_method(
    typed_array_proto, "slice", "TypedArray.prototype.slice", 2.0,
  )
  self.install_method(
    typed_array_proto, "fill", "TypedArray.prototype.fill", 1.0,
  )
  self.install_method(
    typed_array_proto, "copyWithin", "TypedArray.prototype.copyWithin", 2.0,
  )
  self.install_method(
    typed_array_proto, "forEach", "TypedArray.prototype.forEach", 1.0,
  )
  self.install_method(typed_array_proto, "map", "TypedArray.prototype.map", 1.0)
  self.install_method(
    typed_array_proto, "filter", "TypedArray.prototype.filter", 1.0,
  )
  self.install_method(
    typed_array_proto, "reduce", "TypedArray.prototype.reduce", 1.0,
  )
  self.install_method(
    typed_array_proto, "reduceRight", "TypedArray.prototype.reduceRight", 1.0,
  )
  self.install_method(
    typed_array_proto, "every", "TypedArray.prototype.every", 1.0,
  )
  self.install_method(
    typed_array_proto, "some", "TypedArray.prototype.some", 1.0,
  )
  self.install_method(
    typed_array_proto, "find", "TypedArray.prototype.find", 1.0,
  )
  self.install_method(
    typed_array_proto, "findIndex", "TypedArray.prototype.findIndex", 1.0,
  )
  self.install_method(
    typed_array_proto, "indexOf", "TypedArray.prototype.indexOf", 1.0,
  )
  self.install_method(
    typed_array_proto, "lastIndexOf", "TypedArray.prototype.lastIndexOf", 1.0,
  )
  self.install_method(
    typed_array_proto, "includes", "TypedArray.prototype.includes", 1.0,
  )
  self.install_method(
    typed_array_proto, "join", "TypedArray.prototype.join", 1.0,
  )
  self.install_method(
    typed_array_proto, "reverse", "TypedArray.prototype.reverse", 0.0,
  )
  self.install_method(
    typed_array_proto, "sort", "TypedArray.prototype.sort", 1.0,
  )
  self.install_method(typed_array_proto, "at", "TypedArray.prototype.at", 1.0)
  self.install_method(
    typed_array_proto, "keys", "TypedArray.prototype.keys", 0.0,
  )
  self.install_method(
    typed_array_proto, "values", "TypedArray.prototype.values", 0.0,
  )
  self.install_method(
    typed_array_proto, "entries", "TypedArray.prototype.entries", 0.0,
  )
  self.install_method(
    typed_array_proto, "@@iterator", "TypedArray.prototype.values", 0.0,
  )
  self.install_method(
    typed_array_proto, "toLocaleString", "TypedArray.prototype.toLocaleString", 0.0,
  )
  self.install_method(
    typed_array_proto, "findLast", "TypedArray.prototype.findLast", 1.0,
  )
  self.install_method(
    typed_array_proto, "findLastIndex", "TypedArray.prototype.findLastIndex", 1.0,
  )
  self.install_method(
    typed_array_proto, "with", "TypedArray.prototype.with", 2.0,
  )
  self.install_method(
    typed_array_proto, "toReversed", "TypedArray.prototype.toReversed", 0.0,
  )
  self.install_method(
    typed_array_proto, "toSorted", "TypedArray.prototype.toSorted", 1.0,
  )
  // TypedArray.prototype[@@toStringTag] getter
  let ta_toStringTag_get = self.make_native(
    "TypedArray.prototype.@@toStringTag",
  )
  self.set_function_length(ta_toStringTag_get, 0.0)
  self.set_function_name(ta_toStringTag_get, "get [Symbol.toStringTag]")
  let _ = js_define_accessor_prop(
    typed_array_proto,
    "@@toStringTag",
    Some(ta_toStringTag_get),
    None,
    false,
    true,
  )
  // TypedArray.prototype getters: length, byteLength, byteOffset, buffer
  let ta_length_get = self.make_native("TypedArray.prototype.length")
  self.set_function_length(ta_length_get, 0.0)
  self.set_function_name(ta_length_get, "get length")
  let _ = js_define_accessor_prop(
    typed_array_proto,
    "length",
    Some(ta_length_get),
    None,
    false,
    true,
  )
  let ta_byteLength_get = self.make_native("TypedArray.prototype.byteLength")
  self.set_function_length(ta_byteLength_get, 0.0)
  self.set_function_name(ta_byteLength_get, "get byteLength")
  let _ = js_define_accessor_prop(
    typed_array_proto,
    "byteLength",
    Some(ta_byteLength_get),
    None,
    false,
    true,
  )
  let ta_byteOffset_get = self.make_native("TypedArray.prototype.byteOffset")
  self.set_function_length(ta_byteOffset_get, 0.0)
  self.set_function_name(ta_byteOffset_get, "get byteOffset")
  let _ = js_define_accessor_prop(
    typed_array_proto,
    "byteOffset",
    Some(ta_byteOffset_get),
    None,
    false,
    true,
  )
  let ta_buffer_get = self.make_native("TypedArray.prototype.buffer")
  self.set_function_length(ta_buffer_get, 0.0)
  self.set_function_name(ta_buffer_get, "get buffer")
  let _ = js_define_accessor_prop(
    typed_array_proto,
    "buffer",
    Some(ta_buffer_get),
    None,
    false,
    true,
  )
  // TypedArray[@@species] getter
  let ta_species_get = self.make_native("TypedArray.@@species")
  self.set_function_length(ta_species_get, 0.0)
  self.set_function_name(ta_species_get, "get [Symbol.species]")
  let _ = js_define_accessor_prop(
    typed_array_ctor,
    "@@species",
    Some(ta_species_get),
    None,
    false,
    true,
  )
  // TypedArray.from and TypedArray.of
  self.install_static_method(typed_array_ctor, "from", "TypedArray.from", 1.0)
  self.install_static_method(typed_array_ctor, "of", "TypedArray.of", 0.0)
  let _ = js_define_data_prop(
    typed_array_ctor, "prototype", typed_array_proto, false, false, false,
  )
  // Store globally for harness access
  self.global_env.define_var("TypedArray", typed_array_ctor)
  set_global_ctor(global_obj, "TypedArray", typed_array_ctor)

  // Concrete TypedArray constructors
  let typed_arrays = [
    "Int8Array", "Uint8Array", "Uint8ClampedArray", "Int16Array", "Uint16Array",
    "Int32Array", "Uint32Array", "Float32Array", "Float64Array",
  ]
  for name in typed_arrays {
    let ctor = self.make_native(name)
    self.set_function_length(ctor, 3.0)
    self.set_function_name(ctor, name)
    // ctor[[Prototype]] = TypedArray
    let _ = js_set_prop(ctor, "__proto__", typed_array_ctor)
    // Create individual prototype that inherits from TypedArray.prototype
    let proto = self.new_object()
    let _ = js_set_prop(proto, "__proto__", typed_array_proto)
    set_proto_method(proto, "constructor", ctor)
    // BYTES_PER_ELEMENT on prototype and constructor
    let bytes_per = match name {
      "Int8Array" | "Uint8Array" | "Uint8ClampedArray" => 1.0
      "Int16Array" | "Uint16Array" => 2.0
      "Int32Array" | "Uint32Array" | "Float32Array" => 4.0
      "Float64Array" => 8.0
      _ => 1.0
    }
    let _ = js_define_data_prop(
      proto,
      "BYTES_PER_ELEMENT",
      Number(bytes_per),
      false,
      false,
      false,
    )
    let _ = js_define_data_prop(
      ctor,
      "BYTES_PER_ELEMENT",
      Number(bytes_per),
      false,
      false,
      false,
    )
    let _ = js_define_data_prop(ctor, "prototype", proto, false, false, false)
    self.global_env.define_var(name, ctor)
    set_global_ctor(global_obj, name, ctor)
  }

  // BigInt64Array/BigUint64Array
  let big_typed_arrays = ["BigInt64Array", "BigUint64Array"]
  for name in big_typed_arrays {
    let ctor = self.make_native(name)
    self.set_function_length(ctor, 3.0)
    self.set_function_name(ctor, name)
    let _ = js_set_prop(ctor, "__proto__", typed_array_ctor)
    let proto = self.new_object()
    let _ = js_set_prop(proto, "__proto__", typed_array_proto)
    set_proto_method(proto, "constructor", ctor)
    let _ = js_define_data_prop(
      proto,
      "BYTES_PER_ELEMENT",
      Number(8.0),
      false,
      false,
      false,
    )
    let _ = js_define_data_prop(
      ctor,
      "BYTES_PER_ELEMENT",
      Number(8.0),
      false,
      false,
      false,
    )
    let _ = js_define_data_prop(ctor, "prototype", proto, false, false, false)
    self.global_env.define_var(name, ctor)
    set_global_ctor(global_obj, name, ctor)
  }

  // testTypedArray.js harness - arrays of constructors
  // floatArrayConstructors
  let float_ctors = js_new_array()
  let _ = js_array_push(float_ctors, self.global_env.get("Float64Array"))
  let _ = js_array_push(float_ctors, self.global_env.get("Float32Array"))
  self.global_env.define_var("floatArrayConstructors", float_ctors)
  set_global_ctor(global_obj, "floatArrayConstructors", float_ctors)
  // nonClampedIntArrayConstructors
  let non_clamped_int_ctors = js_new_array()
  let _ = js_array_push(
    non_clamped_int_ctors,
    self.global_env.get("Int32Array"),
  )
  let _ = js_array_push(
    non_clamped_int_ctors,
    self.global_env.get("Int16Array"),
  )
  let _ = js_array_push(non_clamped_int_ctors, self.global_env.get("Int8Array"))
  let _ = js_array_push(
    non_clamped_int_ctors,
    self.global_env.get("Uint32Array"),
  )
  let _ = js_array_push(
    non_clamped_int_ctors,
    self.global_env.get("Uint16Array"),
  )
  let _ = js_array_push(
    non_clamped_int_ctors,
    self.global_env.get("Uint8Array"),
  )
  self.global_env.define_var(
    "nonClampedIntArrayConstructors", non_clamped_int_ctors,
  )
  let _ = js_set_prop(
    global_obj, "nonClampedIntArrayConstructors", non_clamped_int_ctors,
  )
  // intArrayConstructors
  let int_ctors = js_new_array()
  let _ = js_array_push(int_ctors, self.global_env.get("Int32Array"))
  let _ = js_array_push(int_ctors, self.global_env.get("Int16Array"))
  let _ = js_array_push(int_ctors, self.global_env.get("Int8Array"))
  let _ = js_array_push(int_ctors, self.global_env.get("Uint32Array"))
  let _ = js_array_push(int_ctors, self.global_env.get("Uint16Array"))
  let _ = js_array_push(int_ctors, self.global_env.get("Uint8Array"))
  let _ = js_array_push(int_ctors, self.global_env.get("Uint8ClampedArray"))
  self.global_env.define_var("intArrayConstructors", int_ctors)
  set_global_ctor(global_obj, "intArrayConstructors", int_ctors)
  // typedArrayConstructors (all non-bigint)
  let typed_ctors = js_new_array()
  let _ = js_array_push(typed_ctors, self.global_env.get("Float64Array"))
  let _ = js_array_push(typed_ctors, self.global_env.get("Float32Array"))
  let _ = js_array_push(typed_ctors, self.global_env.get("Int32Array"))
  let _ = js_array_push(typed_ctors, self.global_env.get("Int16Array"))
  let _ = js_array_push(typed_ctors, self.global_env.get("Int8Array"))
  let _ = js_array_push(typed_ctors, self.global_env.get("Uint32Array"))
  let _ = js_array_push(typed_ctors, self.global_env.get("Uint16Array"))
  let _ = js_array_push(typed_ctors, self.global_env.get("Uint8Array"))
  let _ = js_array_push(typed_ctors, self.global_env.get("Uint8ClampedArray"))
  self.global_env.define_var("typedArrayConstructors", typed_ctors)
  set_global_ctor(global_obj, "typedArrayConstructors", typed_ctors)
  // bigIntArrayConstructors (for testBigIntTypedArray.js)
  let bigint_ctors = js_new_array()
  let _ = js_array_push(bigint_ctors, self.global_env.get("BigInt64Array"))
  let _ = js_array_push(bigint_ctors, self.global_env.get("BigUint64Array"))
  self.global_env.define_var("bigIntArrayConstructors", bigint_ctors)
  set_global_ctor(global_obj, "bigIntArrayConstructors", bigint_ctors)

}

///|
fn JSInterpreter::install_symbol(
  self : JSInterpreter,
  global_obj : JSValue,
) -> Unit {
  let symbol_fn = self.make_native("Symbol")
  self.set_function_length(symbol_fn, 0.0)
  // Create Symbol.prototype
  let symbol_proto = self.new_object()
  set_proto_method(symbol_proto, "__class", String("Symbol"))
  // Symbol.prototype.description (getter)
  let sym_desc_get = self.make_native("Symbol.prototype.description")
  self.set_function_length(sym_desc_get, 0.0)
  self.set_function_name(sym_desc_get, "get description")
  let _ = js_define_accessor_prop(
    symbol_proto,
    "description",
    Some(sym_desc_get),
    None,
    false,
    true,
  )
  // Symbol.prototype.toString
  let sym_to_str = self.make_native("Symbol.prototype.toString")
  self.set_function_length(sym_to_str, 0.0)
  self.set_function_name(sym_to_str, "toString")
  let _ = js_define_data_prop(
    symbol_proto, "toString", sym_to_str, true, false, true,
  )
  // Symbol.prototype.valueOf
  let sym_value_of = self.make_native("Symbol.prototype.valueOf")
  self.set_function_length(sym_value_of, 0.0)
  self.set_function_name(sym_value_of, "valueOf")
  let _ = js_define_data_prop(
    symbol_proto, "valueOf", sym_value_of, true, false, true,
  )
  // Symbol.prototype[@@toPrimitive]
  let sym_to_prim = self.make_native("Symbol.prototype[@@toPrimitive]")
  self.set_function_length(sym_to_prim, 1.0)
  self.set_function_name(sym_to_prim, "[Symbol.toPrimitive]")
  let _ = js_define_data_prop(
    symbol_proto, "@@toPrimitive", sym_to_prim, false, false, true,
  )
  // Symbol.prototype[@@toStringTag]
  let _ = js_define_data_prop(
    symbol_proto,
    "@@toStringTag",
    String("Symbol"),
    false,
    false,
    true,
  )
  let _ = js_define_data_prop(
    symbol_fn, "prototype", symbol_proto, false, false, false,
  )
  // Symbol.for
  let symbol_for = self.make_native("Symbol.for")
  self.set_function_length(symbol_for, 1.0)
  self.set_function_name(symbol_for, "for")
  let _ = js_define_data_prop(symbol_fn, "for", symbol_for, true, false, true)
  // Symbol.keyFor
  let symbol_key_for = self.make_native("Symbol.keyFor")
  self.set_function_length(symbol_key_for, 1.0)
  self.set_function_name(symbol_key_for, "keyFor")
  let _ = js_define_data_prop(
    symbol_fn, "keyFor", symbol_key_for, true, false, true,
  )
  // Well-known symbols (not enumerable, not writable, not configurable)
  let well_known = [
    ("asyncIterator", "@@asyncIterator"),
    ("hasInstance", "@@hasInstance"),
    ("isConcatSpreadable", "@@isConcatSpreadable"),
    ("iterator", "@@iterator"),
    ("match", "@@match"),
    ("matchAll", "@@matchAll"),
    ("replace", "@@replace"),
    ("search", "@@search"),
    ("species", "@@species"),
    ("split", "@@split"),
    ("toPrimitive", "@@toPrimitive"),
    ("toStringTag", "@@toStringTag"),
    ("unscopables", "@@unscopables"),
    ("dispose", "@@dispose"),
    ("asyncDispose", "@@asyncDispose"),
  ]
  for pair in well_known {
    let (name, value) = pair
    let _ = js_define_data_prop(
      symbol_fn,
      name,
      String(value),
      false,
      false,
      false,
    )

  }
  self.global_env.define_var("Symbol", symbol_fn)
  set_global_ctor(global_obj, "Symbol", symbol_fn)

}

///|
fn JSInterpreter::install_error_ctor(
  self : JSInterpreter,
  global_obj : JSValue,
  name : String,
) -> Unit {
  let ctor = self.make_native(name)
  self.set_function_name(ctor, name)
  let _ = js_define_data_prop(
    ctor,
    "prototype",
    self.new_object(),
    true,
    false,
    true,
  )
  self.global_env.define_var(name, ctor)
  set_global_ctor(global_obj, name, ctor)
}

///|
fn JSInterpreter::install_errors(
  self : JSInterpreter,
  global_obj : JSValue,
) -> Unit {
  self.install_error_ctor(global_obj, "Error")
  self.install_error_ctor(global_obj, "SyntaxError")
  self.install_error_ctor(global_obj, "TypeError")
  self.install_error_ctor(global_obj, "ReferenceError")
  self.install_error_ctor(global_obj, "RangeError")
  self.install_error_ctor(global_obj, "AggregateError")
  self.install_error_ctor(global_obj, "URIError")
  self.install_error_ctor(global_obj, "EvalError")
}

///|
fn JSInterpreter::install_math(
  self : JSInterpreter,
  global_obj : JSValue,
) -> Unit {
  let math = self.new_object()
  set_proto_method(math, "__class", String("Math"))
  set_proto_method(math, "floor", self.make_native("Math.floor"))
  set_proto_method(math, "ceil", self.make_native("Math.ceil"))
  set_proto_method(math, "abs", self.make_native("Math.abs"))
  set_proto_method(math, "sqrt", self.make_native("Math.sqrt"))
  set_proto_method(math, "min", self.make_native("Math.min"))
  set_proto_method(math, "max", self.make_native("Math.max"))
  set_proto_method(math, "round", self.make_native("Math.round"))
  set_proto_method(math, "random", self.make_native("Math.random"))
  set_proto_method(math, "cos", self.make_native("Math.cos"))
  set_proto_method(math, "sin", self.make_native("Math.sin"))
  set_proto_method(math, "tan", self.make_native("Math.tan"))
  set_proto_method(math, "exp", self.make_native("Math.exp"))
  set_proto_method(math, "log", self.make_native("Math.log"))
  set_proto_method(math, "trunc", self.make_native("Math.trunc"))
  set_proto_method(math, "pow", self.make_native("Math.pow"))
  set_proto_method(math, "sign", self.make_native("Math.sign"))
  set_proto_method(math, "log10", self.make_native("Math.log10"))
  set_proto_method(math, "log2", self.make_native("Math.log2"))
  set_proto_method(math, "cbrt", self.make_native("Math.cbrt"))
  set_proto_method(math, "hypot", self.make_native("Math.hypot"))
  set_proto_method(math, "atan2", self.make_native("Math.atan2"))
  set_proto_method(math, "asin", self.make_native("Math.asin"))
  set_proto_method(math, "acos", self.make_native("Math.acos"))
  set_proto_method(math, "atan", self.make_native("Math.atan"))
  set_proto_method(math, "sinh", self.make_native("Math.sinh"))
  set_proto_method(math, "cosh", self.make_native("Math.cosh"))
  set_proto_method(math, "tanh", self.make_native("Math.tanh"))
  set_proto_method(math, "asinh", self.make_native("Math.asinh"))
  set_proto_method(math, "acosh", self.make_native("Math.acosh"))
  set_proto_method(math, "atanh", self.make_native("Math.atanh"))
  set_proto_method(math, "expm1", self.make_native("Math.expm1"))
  set_proto_method(math, "log1p", self.make_native("Math.log1p"))
  set_proto_method(math, "fround", self.make_native("Math.fround"))
  set_proto_method(math, "clz32", self.make_native("Math.clz32"))
  set_proto_method(math, "imul", self.make_native("Math.imul"))
  let _ = js_define_data_prop(math, "PI", Number(@math.PI), false, false, false)
  let _ = js_define_data_prop(
    math,
    "E",
    Number(@math.exp(1.0)),
    false,
    false,
    false,
  )
  let _ = js_define_data_prop(
    math,
    "LN2",
    Number(@math.ln(2.0)),
    false,
    false,
    false,
  )
  let _ = js_define_data_prop(
    math,
    "LN10",
    Number(@math.ln(10.0)),
    false,
    false,
    false,
  )
  let _ = js_define_data_prop(
    math,
    "LOG2E",
    Number(1.0 / @math.ln(2.0)),
    false,
    false,
    false,
  )
  let _ = js_define_data_prop(
    math,
    "LOG10E",
    Number(1.0 / @math.ln(10.0)),
    false,
    false,
    false,
  )
  let _ = js_define_data_prop(
    math,
    "SQRT2",
    Number(2.0.sqrt()),
    false,
    false,
    false,
  )
  let _ = js_define_data_prop(
    math,
    "SQRT1_2",
    Number(0.5.sqrt()),
    false,
    false,
    false,
  )
  self.global_env.define_var("Math", math)
  set_global_ctor(global_obj, "Math", math)

}

///|
/// Helper to install a method on a prototype with length property
fn JSInterpreter::install_method(
  self : JSInterpreter,
  proto : JSValue,
  name : String,
  native_name : String,
  length : Double,
) -> Unit {
  let fn_val = self.make_native(native_name)
  self.set_function_length(fn_val, length)
  self.set_function_name(fn_val, name)
  let _ = js_define_data_prop(proto, name, fn_val, true, false, true)

}

///|
/// Helper to install a static method on a constructor
fn JSInterpreter::install_static_method(
  self : JSInterpreter,
  ctor : JSValue,
  name : String,
  native_name : String,
  length : Double,
) -> Unit {
  let fn_val = self.make_native(native_name)
  self.set_function_length(fn_val, length)
  self.set_function_name(fn_val, name)
  let _ = js_define_data_prop(ctor, name, fn_val, true, false, true)

}

///|
// /
fn JSInterpreter::install_builtins(self : JSInterpreter) -> Unit {
  let global_obj = self.new_object()

  // Object.prototype - all properties should be non-enumerable
  self.install_method(
    self.object_proto,
    "hasOwnProperty",
    "Object.hasOwnProperty",
    1.0,
  )
  self.install_method(
    self.object_proto,
    "toString",
    "Object.prototype.toString",
    0.0,
  )
  self.install_method(
    self.object_proto,
    "isPrototypeOf",
    "Object.prototype.isPrototypeOf",
    1.0,
  )
  self.install_method(
    self.object_proto,
    "valueOf",
    "Object.prototype.valueOf",
    0.0,
  )
  self.install_method(
    self.object_proto,
    "propertyIsEnumerable",
    "Object.prototype.propertyIsEnumerable",
    1.0,
  )

  // Object
  let object_ctor = self.make_native("Object")
  let _ = js_define_data_prop(
    object_ctor,
    "prototype",
    self.object_proto,
    true,
    false,
    true,
  )
  set_proto_method(object_ctor, "name", JSValue::String("Object"))
  let _ = js_define_data_prop(
    self.object_proto,
    "constructor",
    object_ctor,
    true,
    false,
    true,
  )
  self.install_static_method(
    object_ctor, "getOwnPropertyNames", "Object.getOwnPropertyNames", 1.0,
  )
  self.install_static_method(object_ctor, "create", "Object.create", 2.0)
  self.install_static_method(
    object_ctor, "getPrototypeOf", "Object.getPrototypeOf", 1.0,
  )
  self.install_static_method(
    object_ctor, "getOwnPropertyDescriptor", "Object.getOwnPropertyDescriptor", 2.0,
  )
  self.install_static_method(
    object_ctor, "defineProperty", "Object.defineProperty", 3.0,
  )
  self.install_method(
    object_ctor, "setPrototypeOf", "Object.setPrototypeOf", 2.0,
  )
  self.install_static_method(
    object_ctor, "isExtensible", "Object.isExtensible", 1.0,
  )
  self.install_static_method(object_ctor, "is", "Object.is", 2.0)
  self.install_static_method(object_ctor, "keys", "Object.keys", 1.0)
  self.install_static_method(
    object_ctor, "getOwnPropertySymbols", "Object.getOwnPropertySymbols", 1.0,
  )
  self.install_static_method(object_ctor, "values", "Object.values", 1.0)
  self.install_static_method(object_ctor, "entries", "Object.entries", 1.0)
  self.install_static_method(object_ctor, "assign", "Object.assign", 2.0)
  self.install_static_method(
    object_ctor, "fromEntries", "Object.fromEntries", 1.0,
  )
  self.install_static_method(
    object_ctor, "preventExtensions", "Object.preventExtensions", 1.0,
  )
  self.install_static_method(object_ctor, "freeze", "Object.freeze", 1.0)
  self.install_static_method(object_ctor, "seal", "Object.seal", 1.0)
  self.install_static_method(object_ctor, "isFrozen", "Object.isFrozen", 1.0)
  self.install_static_method(object_ctor, "isSealed", "Object.isSealed", 1.0)
  self.global_env.define_var("Object", object_ctor)
  set_global_ctor(global_obj, "Object", object_ctor)

  // console
  let console = self.new_object()
  set_proto_method(console, "log", self.make_native("console.log"))
  self.global_env.define_var("console", console)
  set_global_ctor(global_obj, "console", console)
  self.install_math(global_obj)

  // JSON
  let json_obj = self.new_object()
  set_proto_method(json_obj, "__class", String("JSON"))
  let json_parse = self.make_native("JSON.parse")
  self.set_function_length(json_parse, 2.0)
  set_proto_method(json_obj, "parse", json_parse)
  let json_stringify = self.make_native("JSON.stringify")
  self.set_function_length(json_stringify, 3.0)
  set_proto_method(json_obj, "stringify", json_stringify)
  self.global_env.define_var("JSON", json_obj)
  set_global_ctor(global_obj, "JSON", json_obj)

  // Function
  let call_fn = self.make_native("Function.call")
  self.set_function_length(call_fn, 1.0)
  set_proto_method(self.function_proto, "call", call_fn)
  let apply_fn = self.make_native("Function.apply")
  self.set_function_length(apply_fn, 2.0)
  set_proto_method(self.function_proto, "apply", apply_fn)
  let bind_fn = self.make_native("Function.bind")
  self.set_function_length(bind_fn, 1.0)
  set_proto_method(self.function_proto, "bind", bind_fn)
  let has_instance = self.make_native("Function.prototype[@@hasInstance]")
  self.set_function_length(has_instance, 1.0)
  set_proto_method(self.function_proto, "@@hasInstance", has_instance)
  let fn_to_string = self.make_native("Function.prototype.toString")
  self.set_function_length(fn_to_string, 0.0)
  set_proto_method(self.function_proto, "toString", fn_to_string)
  self.set_function_length(self.function_proto, 0.0)
  self.set_function_name(self.function_proto, "")
  let function_ctor = self.make_native("Function")
  self.set_function_length(function_ctor, 1.0)
  self.set_function_name(function_ctor, "Function")
  let _ = js_define_data_prop(
    function_ctor,
    "prototype",
    self.function_proto,
    true,
    false,
    true,
  )
  set_proto_method(self.function_proto, "constructor", function_ctor)
  self.global_env.define_var("Function", function_ctor)
  set_global_ctor(global_obj, "Function", function_ctor)

  // Boolean / Number / String
  let boolean_proto = self.new_object()
  let boolean_ctor = self.make_native("Boolean")
  self.set_function_length(boolean_ctor, 1.0)
  self.set_function_name(boolean_ctor, "Boolean")
  let _ = js_define_data_prop(
    boolean_ctor, "prototype", boolean_proto, true, false, true,
  )
  set_proto_method(boolean_proto, "constructor", boolean_ctor)
  set_proto_method(boolean_proto, "value", Bool(false))
  let bool_value_of = self.make_native("Boolean.prototype.valueOf")
  self.set_function_length(bool_value_of, 0.0)
  set_proto_method(boolean_proto, "valueOf", bool_value_of)
  let bool_to_string = self.make_native("Boolean.prototype.toString")
  self.set_function_length(bool_to_string, 0.0)
  set_proto_method(boolean_proto, "toString", bool_to_string)
  self.global_env.define_var("Boolean", boolean_ctor)
  set_global_ctor(global_obj, "Boolean", boolean_ctor)
  let number_proto = self.new_object()
  let number_ctor = self.make_native("Number")
  self.set_function_length(number_ctor, 1.0)
  self.set_function_name(number_ctor, "Number")
  let _ = js_define_data_prop(
    number_ctor, "prototype", number_proto, true, false, true,
  )
  set_proto_method(number_proto, "constructor", number_ctor)
  set_proto_method(number_proto, "value", Number(0.0))
  let num_value_of = self.make_native("Number.prototype.valueOf")
  self.set_function_length(num_value_of, 0.0)
  set_proto_method(number_proto, "valueOf", num_value_of)
  let num_to_string = self.make_native("Number.prototype.toString")
  self.set_function_length(num_to_string, 0.0)
  set_proto_method(number_proto, "toString", num_to_string)
  let num_is_nan = self.make_native("Number.isNaN")
  self.set_function_length(num_is_nan, 1.0)
  set_proto_method(number_ctor, "isNaN", num_is_nan)
  let _ = js_define_data_prop(
    number_ctor,
    "NaN",
    Number(js_nan),
    false,
    false,
    false,
  )
  let _ = js_define_data_prop(
    number_ctor,
    "POSITIVE_INFINITY",
    Number(1.0 / 0.0),
    false,
    false,
    false,
  )
  let _ = js_define_data_prop(
    number_ctor,
    "NEGATIVE_INFINITY",
    Number(-1.0 / 0.0),
    false,
    false,
    false,
  )
  let max_safe = JSValue::Number(9007199254740991.0)
  let _ = js_define_data_prop(
    number_ctor, "MAX_SAFE_INTEGER", max_safe, false, false, false,
  )
  let min_safe = JSValue::Number(-9007199254740991.0)
  let _ = js_define_data_prop(
    number_ctor, "MIN_SAFE_INTEGER", min_safe, false, false, false,
  )
  // MAX_VALUE: approximately 1.7976931348623157e+308
  let max_value = JSValue::Number(1.7976931348623157e+308)
  let _ = js_define_data_prop(
    number_ctor, "MAX_VALUE", max_value, false, false, false,
  )
  // MIN_VALUE: approximately 5e-324
  let min_value = JSValue::Number(5.0e-324)
  let _ = js_define_data_prop(
    number_ctor, "MIN_VALUE", min_value, false, false, false,
  )
  // EPSILON: 2^-52
  let epsilon = JSValue::Number(2.220446049250313e-16)
  let _ = js_define_data_prop(
    number_ctor, "EPSILON", epsilon, false, false, false,
  )
  self.global_env.define_var("Number", number_ctor)
  set_global_ctor(global_obj, "Number", number_ctor)
  // BigInt
  let bigint_proto = self.new_object()
  let bigint_ctor = self.make_native("BigInt")
  self.set_function_length(bigint_ctor, 1.0)
  self.set_function_name(bigint_ctor, "BigInt")
  let _ = js_define_data_prop(
    bigint_ctor, "prototype", bigint_proto, false, false, false,
  )
  set_proto_method(bigint_proto, "constructor", bigint_ctor)
  let bigint_value_of = self.make_native("BigInt.prototype.valueOf")
  self.set_function_length(bigint_value_of, 0.0)
  set_proto_method(bigint_proto, "valueOf", bigint_value_of)
  let bigint_to_string = self.make_native("BigInt.prototype.toString")
  self.set_function_length(bigint_to_string, 1.0)
  set_proto_method(bigint_proto, "toString", bigint_to_string)
  let bigint_to_locale_string = self.make_native(
    "BigInt.prototype.toLocaleString",
  )
  self.set_function_length(bigint_to_locale_string, 0.0)
  set_proto_method(bigint_proto, "toLocaleString", bigint_to_locale_string)
  // BigInt static methods
  set_proto_method(bigint_ctor, "asIntN", self.make_native("BigInt.asIntN"))
  set_proto_method(bigint_ctor, "asUintN", self.make_native("BigInt.asUintN"))
  self.global_env.define_var("BigInt", bigint_ctor)
  set_global_ctor(global_obj, "BigInt", bigint_ctor)
  let string_proto = self.new_object()
  let string_ctor = self.make_native("String")
  self.set_function_length(string_ctor, 1.0)
  self.set_function_name(string_ctor, "String")
  let _ = js_define_data_prop(
    string_ctor, "prototype", string_proto, true, false, true,
  )
  set_proto_method(string_proto, "constructor", string_ctor)
  set_proto_method(string_proto, "value", String(""))
  let str_value_of = self.make_native("String.prototype.valueOf")
  self.set_function_length(str_value_of, 0.0)
  set_proto_method(string_proto, "valueOf", str_value_of)
  let str_to_string = self.make_native("String.prototype.toString")
  self.set_function_length(str_to_string, 0.0)
  set_proto_method(string_proto, "toString", str_to_string)
  let str_char_at = self.make_native("String.prototype.charAt")
  self.set_function_length(str_char_at, 1.0)
  set_proto_method(string_proto, "charAt", str_char_at)
  let str_char_code_at = self.make_native("String.prototype.charCodeAt")
  self.set_function_length(str_char_code_at, 1.0)
  set_proto_method(string_proto, "charCodeAt", str_char_code_at)
  let str_code_point_at = self.make_native("String.prototype.codePointAt")
  self.set_function_length(str_code_point_at, 1.0)
  set_proto_method(string_proto, "codePointAt", str_code_point_at)
  let str_index_of = self.make_native("String.prototype.indexOf")
  self.set_function_length(str_index_of, 1.0)
  set_proto_method(string_proto, "indexOf", str_index_of)
  let str_last_index_of = self.make_native("String.prototype.lastIndexOf")
  self.set_function_length(str_last_index_of, 1.0)
  set_proto_method(string_proto, "lastIndexOf", str_last_index_of)
  let str_includes = self.make_native("String.prototype.includes")
  self.set_function_length(str_includes, 1.0)
  set_proto_method(string_proto, "includes", str_includes)
  let str_starts_with = self.make_native("String.prototype.startsWith")
  self.set_function_length(str_starts_with, 1.0)
  set_proto_method(string_proto, "startsWith", str_starts_with)
  let str_ends_with = self.make_native("String.prototype.endsWith")
  self.set_function_length(str_ends_with, 1.0)
  set_proto_method(string_proto, "endsWith", str_ends_with)
  let str_at = self.make_native("String.prototype.at")
  self.set_function_length(str_at, 1.0)
  set_proto_method(string_proto, "at", str_at)
  let str_split = self.make_native("String.prototype.split")
  self.set_function_length(str_split, 2.0)
  set_proto_method(string_proto, "split", str_split)
  let str_replace = self.make_native("String.prototype.replace")
  self.set_function_length(str_replace, 2.0)
  set_proto_method(string_proto, "replace", str_replace)
  let str_replace_all = self.make_native("String.prototype.replaceAll")
  self.set_function_length(str_replace_all, 2.0)
  set_proto_method(string_proto, "replaceAll", str_replace_all)
  let str_trim = self.make_native("String.prototype.trim")
  self.set_function_length(str_trim, 0.0)
  set_proto_method(string_proto, "trim", str_trim)
  let str_trim_start = self.make_native("String.prototype.trimStart")
  self.set_function_length(str_trim_start, 0.0)
  set_proto_method(string_proto, "trimStart", str_trim_start)
  // trimLeft is the same function object as trimStart (Annex B)
  let _ = js_define_data_prop(
    string_proto, "trimLeft", str_trim_start, true, false, true,
  )
  let str_trim_end = self.make_native("String.prototype.trimEnd")
  self.set_function_length(str_trim_end, 0.0)
  set_proto_method(string_proto, "trimEnd", str_trim_end)
  // trimRight is the same function object as trimEnd (Annex B)
  let _ = js_define_data_prop(
    string_proto, "trimRight", str_trim_end, true, false, true,
  )
  let str_slice = self.make_native("String.prototype.slice")
  self.set_function_length(str_slice, 2.0)
  set_proto_method(string_proto, "slice", str_slice)
  let str_substr = self.make_native("String.prototype.substr")
  self.set_function_length(str_substr, 2.0)
  set_proto_method(string_proto, "substr", str_substr)
  let str_substring = self.make_native("String.prototype.substring")
  self.set_function_length(str_substring, 2.0)
  set_proto_method(string_proto, "substring", str_substring)
  let str_concat = self.make_native("String.prototype.concat")
  self.set_function_length(str_concat, 1.0)
  set_proto_method(string_proto, "concat", str_concat)
  let str_to_upper = self.make_native("String.prototype.toUpperCase")
  self.set_function_length(str_to_upper, 0.0)
  set_proto_method(string_proto, "toUpperCase", str_to_upper)
  let str_to_lower = self.make_native("String.prototype.toLowerCase")
  self.set_function_length(str_to_lower, 0.0)
  set_proto_method(string_proto, "toLowerCase", str_to_lower)
  let str_to_locale_upper = self.make_native(
    "String.prototype.toLocaleUpperCase",
  )
  self.set_function_length(str_to_locale_upper, 0.0)
  set_proto_method(string_proto, "toLocaleUpperCase", str_to_locale_upper)
  let str_to_locale_lower = self.make_native(
    "String.prototype.toLocaleLowerCase",
  )
  self.set_function_length(str_to_locale_lower, 0.0)
  set_proto_method(string_proto, "toLocaleLowerCase", str_to_locale_lower)
  let str_repeat = self.make_native("String.prototype.repeat")
  self.set_function_length(str_repeat, 1.0)
  set_proto_method(string_proto, "repeat", str_repeat)
  let str_big = self.make_native("String.prototype.big")
  self.set_function_length(str_big, 0.0)
  set_proto_method(string_proto, "big", str_big)
  let str_small = self.make_native("String.prototype.small")
  self.set_function_length(str_small, 0.0)
  set_proto_method(string_proto, "small", str_small)
  let str_bold = self.make_native("String.prototype.bold")
  self.set_function_length(str_bold, 0.0)
  set_proto_method(string_proto, "bold", str_bold)
  let str_italics = self.make_native("String.prototype.italics")
  self.set_function_length(str_italics, 0.0)
  set_proto_method(string_proto, "italics", str_italics)
  let str_strike = self.make_native("String.prototype.strike")
  self.set_function_length(str_strike, 0.0)
  set_proto_method(string_proto, "strike", str_strike)
  let str_sub = self.make_native("String.prototype.sub")
  self.set_function_length(str_sub, 0.0)
  set_proto_method(string_proto, "sub", str_sub)
  let str_sup = self.make_native("String.prototype.sup")
  self.set_function_length(str_sup, 0.0)
  set_proto_method(string_proto, "sup", str_sup)
  let str_fixed = self.make_native("String.prototype.fixed")
  self.set_function_length(str_fixed, 0.0)
  set_proto_method(string_proto, "fixed", str_fixed)
  let str_blink = self.make_native("String.prototype.blink")
  self.set_function_length(str_blink, 0.0)
  set_proto_method(string_proto, "blink", str_blink)
  let str_fontcolor = self.make_native("String.prototype.fontcolor")
  self.set_function_length(str_fontcolor, 1.0)
  set_proto_method(string_proto, "fontcolor", str_fontcolor)
  let str_fontsize = self.make_native("String.prototype.fontsize")
  self.set_function_length(str_fontsize, 1.0)
  set_proto_method(string_proto, "fontsize", str_fontsize)
  let str_link = self.make_native("String.prototype.link")
  self.set_function_length(str_link, 1.0)
  set_proto_method(string_proto, "link", str_link)
  let str_pad_start = self.make_native("String.prototype.padStart")
  self.set_function_length(str_pad_start, 1.0)
  set_proto_method(string_proto, "padStart", str_pad_start)
  let str_pad_end = self.make_native("String.prototype.padEnd")
  self.set_function_length(str_pad_end, 1.0)
  set_proto_method(string_proto, "padEnd", str_pad_end)
  let str_from_char_code = self.make_native("String.fromCharCode")
  self.set_function_length(str_from_char_code, 1.0)
  set_proto_method(string_ctor, "fromCharCode", str_from_char_code)
  let str_from_code_point = self.make_native("String.fromCodePoint")
  self.set_function_length(str_from_code_point, 1.0)
  set_proto_method(string_ctor, "fromCodePoint", str_from_code_point)
  let str_iterator = self.make_native("String.prototype[@@iterator]")
  self.set_function_length(str_iterator, 0.0)
  set_proto_method(string_proto, "@@iterator", str_iterator)
  self.global_env.define_var("String", string_ctor)
  set_global_ctor(global_obj, "String", string_ctor)

  // RegExp (minimal)
  let regexp_proto = self.new_object()
  let regexp_ctor = self.make_native("RegExp")
  self.set_function_length(regexp_ctor, 2.0)
  self.set_function_name(regexp_ctor, "RegExp")
  let _ = js_define_data_prop(
    regexp_ctor, "prototype", regexp_proto, true, false, true,
  )
  set_proto_method(regexp_proto, "constructor", regexp_ctor)
  let re_exec = self.make_native("RegExp.prototype.exec")
  self.set_function_length(re_exec, 1.0)
  set_proto_method(regexp_proto, "exec", re_exec)
  let re_test = self.make_native("RegExp.prototype.test")
  self.set_function_length(re_test, 1.0)
  set_proto_method(regexp_proto, "test", re_test)
  let re_compile = self.make_native("RegExp.prototype.compile")
  self.set_function_length(re_compile, 2.0)
  set_proto_method(regexp_proto, "compile", re_compile)
  self.global_env.define_var("RegExp", regexp_ctor)
  set_global_ctor(global_obj, "RegExp", regexp_ctor)

  // Array
  let array_proto = self.new_object()
  let array_ctor = self.make_native("Array")
  self.set_function_length(array_ctor, 1.0)
  self.set_function_name(array_ctor, "Array")
  let _ = js_define_data_prop(
    array_ctor, "prototype", array_proto, true, false, true,
  )
  set_proto_method(array_proto, "constructor", array_ctor)
  js_set_default_array_proto(array_proto)
  let array_to_string = self.make_native("Array.prototype.toString")
  self.set_function_length(array_to_string, 0.0)
  set_proto_method(array_proto, "toString", array_to_string)
  let array_push = self.make_native("Array.prototype.push")
  self.set_function_length(array_push, 1.0)
  set_proto_method(array_proto, "push", array_push)
  let array_pop = self.make_native("Array.prototype.pop")
  self.set_function_length(array_pop, 0.0)
  set_proto_method(array_proto, "pop", array_pop)
  let array_shift = self.make_native("Array.prototype.shift")
  self.set_function_length(array_shift, 0.0)
  set_proto_method(array_proto, "shift", array_shift)
  let array_unshift = self.make_native("Array.prototype.unshift")
  self.set_function_length(array_unshift, 1.0)
  set_proto_method(array_proto, "unshift", array_unshift)
  let array_join = self.make_native("Array.prototype.join")
  self.set_function_length(array_join, 1.0)
  set_proto_method(array_proto, "join", array_join)
  let array_index_of = self.make_native("Array.prototype.indexOf")
  self.set_function_length(array_index_of, 1.0)
  set_proto_method(array_proto, "indexOf", array_index_of)
  let array_last_index_of = self.make_native("Array.prototype.lastIndexOf")
  self.set_function_length(array_last_index_of, 1.0)
  set_proto_method(array_proto, "lastIndexOf", array_last_index_of)
  let array_includes = self.make_native("Array.prototype.includes")
  self.set_function_length(array_includes, 1.0)
  set_proto_method(array_proto, "includes", array_includes)
  let array_map = self.make_native("Array.prototype.map")
  self.set_function_length(array_map, 1.0)
  set_proto_method(array_proto, "map", array_map)
  let array_filter = self.make_native("Array.prototype.filter")
  self.set_function_length(array_filter, 1.0)
  set_proto_method(array_proto, "filter", array_filter)
  let array_reduce = self.make_native("Array.prototype.reduce")
  self.set_function_length(array_reduce, 1.0)
  set_proto_method(array_proto, "reduce", array_reduce)
  let array_reduce_right = self.make_native("Array.prototype.reduceRight")
  self.set_function_length(array_reduce_right, 1.0)
  set_proto_method(array_proto, "reduceRight", array_reduce_right)
  let array_for_each = self.make_native("Array.prototype.forEach")
  self.set_function_length(array_for_each, 1.0)
  set_proto_method(array_proto, "forEach", array_for_each)
  let array_find = self.make_native("Array.prototype.find")
  self.set_function_length(array_find, 1.0)
  set_proto_method(array_proto, "find", array_find)
  let array_find_index = self.make_native("Array.prototype.findIndex")
  self.set_function_length(array_find_index, 1.0)
  set_proto_method(array_proto, "findIndex", array_find_index)
  let array_find_last = self.make_native("Array.prototype.findLast")
  self.set_function_length(array_find_last, 1.0)
  set_proto_method(array_proto, "findLast", array_find_last)
  let array_find_last_index = self.make_native("Array.prototype.findLastIndex")
  self.set_function_length(array_find_last_index, 1.0)
  set_proto_method(array_proto, "findLastIndex", array_find_last_index)
  let array_every = self.make_native("Array.prototype.every")
  self.set_function_length(array_every, 1.0)
  set_proto_method(array_proto, "every", array_every)
  let array_some = self.make_native("Array.prototype.some")
  self.set_function_length(array_some, 1.0)
  set_proto_method(array_proto, "some", array_some)
  let array_concat = self.make_native("Array.prototype.concat")
  self.set_function_length(array_concat, 1.0)
  set_proto_method(array_proto, "concat", array_concat)
  let array_slice = self.make_native("Array.prototype.slice")
  self.set_function_length(array_slice, 2.0)
  set_proto_method(array_proto, "slice", array_slice)
  let array_splice = self.make_native("Array.prototype.splice")
  self.set_function_length(array_splice, 2.0)
  set_proto_method(array_proto, "splice", array_splice)
  let array_sort = self.make_native("Array.prototype.sort")
  self.set_function_length(array_sort, 1.0)
  set_proto_method(array_proto, "sort", array_sort)
  let array_to_sorted = self.make_native("Array.prototype.toSorted")
  self.set_function_length(array_to_sorted, 1.0)
  set_proto_method(array_proto, "toSorted", array_to_sorted)
  let array_to_reversed = self.make_native("Array.prototype.toReversed")
  self.set_function_length(array_to_reversed, 0.0)
  set_proto_method(array_proto, "toReversed", array_to_reversed)
  let array_to_spliced = self.make_native("Array.prototype.toSpliced")
  self.set_function_length(array_to_spliced, 2.0)
  set_proto_method(array_proto, "toSpliced", array_to_spliced)
  let array_with = self.make_native("Array.prototype.with")
  self.set_function_length(array_with, 2.0)
  set_proto_method(array_proto, "with", array_with)
  let array_flat = self.make_native("Array.prototype.flat")
  self.set_function_length(array_flat, 0.0)
  set_proto_method(array_proto, "flat", array_flat)
  let array_flat_map = self.make_native("Array.prototype.flatMap")
  self.set_function_length(array_flat_map, 1.0)
  set_proto_method(array_proto, "flatMap", array_flat_map)
  let array_fill = self.make_native("Array.prototype.fill")
  self.set_function_length(array_fill, 1.0)
  set_proto_method(array_proto, "fill", array_fill)
  let array_copy_within = self.make_native("Array.prototype.copyWithin")
  self.set_function_length(array_copy_within, 2.0)
  set_proto_method(array_proto, "copyWithin", array_copy_within)
  let array_at = self.make_native("Array.prototype.at")
  self.set_function_length(array_at, 1.0)
  set_proto_method(array_proto, "at", array_at)
  let array_iterator = self.make_native("Array.prototype[@@iterator]")
  self.set_function_length(array_iterator, 0.0)
  set_proto_method(array_proto, "@@iterator", array_iterator)
  let is_array_fn = self.make_native("Array.isArray")
  self.set_function_length(is_array_fn, 1.0)
  set_proto_method(array_ctor, "isArray", is_array_fn)
  self.global_env.define_var("Array", array_ctor)
  set_global_ctor(global_obj, "Array", array_ctor)

  // Date
  let date_proto = self.new_object()
  let date_ctor = self.make_native("Date")
  self.set_function_length(date_ctor, 7.0)
  self.set_function_name(date_ctor, "Date")
  let _ = js_define_data_prop(
    date_ctor, "prototype", date_proto, true, false, true,
  )
  set_proto_method(date_proto, "constructor", date_ctor)
  let date_get_year = self.make_native("Date.prototype.getYear")
  self.set_function_length(date_get_year, 0.0)
  set_proto_method(date_proto, "getYear", date_get_year)
  let date_set_year = self.make_native("Date.prototype.setYear")
  self.set_function_length(date_set_year, 1.0)
  set_proto_method(date_proto, "setYear", date_set_year)
  let date_get_full_year = self.make_native("Date.prototype.getFullYear")
  self.set_function_length(date_get_full_year, 0.0)
  set_proto_method(date_proto, "getFullYear", date_get_full_year)
  let date_get_month = self.make_native("Date.prototype.getMonth")
  self.set_function_length(date_get_month, 0.0)
  set_proto_method(date_proto, "getMonth", date_get_month)
  let date_get_date = self.make_native("Date.prototype.getDate")
  self.set_function_length(date_get_date, 0.0)
  set_proto_method(date_proto, "getDate", date_get_date)
  let date_get_day = self.make_native("Date.prototype.getDay")
  self.set_function_length(date_get_day, 0.0)
  set_proto_method(date_proto, "getDay", date_get_day)
  let date_get_hours = self.make_native("Date.prototype.getHours")
  self.set_function_length(date_get_hours, 0.0)
  set_proto_method(date_proto, "getHours", date_get_hours)
  let date_get_minutes = self.make_native("Date.prototype.getMinutes")
  self.set_function_length(date_get_minutes, 0.0)
  set_proto_method(date_proto, "getMinutes", date_get_minutes)
  let date_get_seconds = self.make_native("Date.prototype.getSeconds")
  self.set_function_length(date_get_seconds, 0.0)
  set_proto_method(date_proto, "getSeconds", date_get_seconds)
  let date_get_milliseconds = self.make_native("Date.prototype.getMilliseconds")
  self.set_function_length(date_get_milliseconds, 0.0)
  set_proto_method(date_proto, "getMilliseconds", date_get_milliseconds)
  let date_get_utc_full_year = self.make_native("Date.prototype.getUTCFullYear")
  self.set_function_length(date_get_utc_full_year, 0.0)
  set_proto_method(date_proto, "getUTCFullYear", date_get_utc_full_year)
  let date_get_utc_month = self.make_native("Date.prototype.getUTCMonth")
  self.set_function_length(date_get_utc_month, 0.0)
  set_proto_method(date_proto, "getUTCMonth", date_get_utc_month)
  let date_get_utc_date = self.make_native("Date.prototype.getUTCDate")
  self.set_function_length(date_get_utc_date, 0.0)
  set_proto_method(date_proto, "getUTCDate", date_get_utc_date)
  let date_get_utc_day = self.make_native("Date.prototype.getUTCDay")
  self.set_function_length(date_get_utc_day, 0.0)
  set_proto_method(date_proto, "getUTCDay", date_get_utc_day)
  let date_get_utc_hours = self.make_native("Date.prototype.getUTCHours")
  self.set_function_length(date_get_utc_hours, 0.0)
  set_proto_method(date_proto, "getUTCHours", date_get_utc_hours)
  let date_get_utc_minutes = self.make_native("Date.prototype.getUTCMinutes")
  self.set_function_length(date_get_utc_minutes, 0.0)
  set_proto_method(date_proto, "getUTCMinutes", date_get_utc_minutes)
  let date_get_utc_seconds = self.make_native("Date.prototype.getUTCSeconds")
  self.set_function_length(date_get_utc_seconds, 0.0)
  set_proto_method(date_proto, "getUTCSeconds", date_get_utc_seconds)
  let date_get_utc_milliseconds = self.make_native(
    "Date.prototype.getUTCMilliseconds",
  )
  self.set_function_length(date_get_utc_milliseconds, 0.0)
  set_proto_method(date_proto, "getUTCMilliseconds", date_get_utc_milliseconds)
  let date_get_timezone_offset = self.make_native(
    "Date.prototype.getTimezoneOffset",
  )
  self.set_function_length(date_get_timezone_offset, 0.0)
  set_proto_method(date_proto, "getTimezoneOffset", date_get_timezone_offset)
  let date_to_string = self.make_native("Date.prototype.toString")
  self.set_function_length(date_to_string, 0.0)
  set_proto_method(date_proto, "toString", date_to_string)
  let date_to_date_string = self.make_native("Date.prototype.toDateString")
  self.set_function_length(date_to_date_string, 0.0)
  set_proto_method(date_proto, "toDateString", date_to_date_string)
  let date_to_time_string = self.make_native("Date.prototype.toTimeString")
  self.set_function_length(date_to_time_string, 0.0)
  set_proto_method(date_proto, "toTimeString", date_to_time_string)
  let date_to_iso_string = self.make_native("Date.prototype.toISOString")
  self.set_function_length(date_to_iso_string, 0.0)
  set_proto_method(date_proto, "toISOString", date_to_iso_string)
  let date_to_utc_string = self.make_native("Date.prototype.toUTCString")
  self.set_function_length(date_to_utc_string, 0.0)
  set_proto_method(date_proto, "toUTCString", date_to_utc_string)
  // toGMTString is an alias for toUTCString (Annex B)
  // { [[Writable]]: true, [[Enumerable]]: false, [[Configurable]]: true }
  let _ = js_define_data_prop(date_proto, "toGMTString", date_to_utc_string, true, false, true)
  let date_to_json = self.make_native("Date.prototype.toJSON")
  self.set_function_length(date_to_json, 1.0)
  set_proto_method(date_proto, "toJSON", date_to_json)
  let date_get_time = self.make_native("Date.prototype.getTime")
  self.set_function_length(date_get_time, 0.0)
  set_proto_method(date_proto, "getTime", date_get_time)
  let date_set_time = self.make_native("Date.prototype.setTime")
  self.set_function_length(date_set_time, 1.0)
  set_proto_method(date_proto, "setTime", date_set_time)
  let date_value_of = self.make_native("Date.prototype.valueOf")
  self.set_function_length(date_value_of, 0.0)
  set_proto_method(date_proto, "valueOf", date_value_of)
  self.global_env.define_var("Date", date_ctor)
  set_global_ctor(global_obj, "Date", date_ctor)
  self.install_errors(global_obj)

  // Promise (minimal)
  let promise_proto = self.new_object()
  let promise_ctor = self.make_native("Promise")
  self.set_function_length(promise_ctor, 1.0)
  self.set_function_name(promise_ctor, "Promise")
  let _ = js_define_data_prop(
    promise_ctor, "prototype", promise_proto, true, false, true,
  )
  set_proto_method(promise_ctor, "__default_proto__", promise_proto)
  set_proto_method(promise_proto, "constructor", promise_ctor)
  let promise_then = self.make_native("Promise.prototype.then")
  self.set_function_length(promise_then, 2.0)
  self.set_function_name(promise_then, "then")
  set_proto_method(promise_proto, "then", promise_then)
  set_proto_method(promise_ctor, "then", promise_then)
  let promise_catch = self.make_native("Promise.prototype.catch")
  self.set_function_length(promise_catch, 1.0)
  self.set_function_name(promise_catch, "catch")
  set_proto_method(promise_proto, "catch", promise_catch)
  let promise_finally = self.make_native("Promise.prototype.finally")
  self.set_function_length(promise_finally, 1.0)
  self.set_function_name(promise_finally, "finally")
  set_proto_method(promise_proto, "finally", promise_finally)
  let promise_resolve = self.make_native("Promise.resolve")
  self.set_function_length(promise_resolve, 1.0)
  self.set_function_name(promise_resolve, "resolve")
  set_proto_method(promise_ctor, "resolve", promise_resolve)
  let promise_reject = self.make_native("Promise.reject")
  self.set_function_length(promise_reject, 1.0)
  self.set_function_name(promise_reject, "reject")
  set_proto_method(promise_ctor, "reject", promise_reject)
  let promise_all = self.make_native("Promise.all")
  self.set_function_length(promise_all, 1.0)
  self.set_function_name(promise_all, "all")
  set_proto_method(promise_ctor, "all", promise_all)
  let promise_race = self.make_native("Promise.race")
  self.set_function_length(promise_race, 1.0)
  self.set_function_name(promise_race, "race")
  set_proto_method(promise_ctor, "race", promise_race)
  let promise_all_settled = self.make_native("Promise.allSettled")
  self.set_function_length(promise_all_settled, 1.0)
  self.set_function_name(promise_all_settled, "allSettled")
  set_proto_method(promise_ctor, "allSettled", promise_all_settled)
  let promise_any = self.make_native("Promise.any")
  self.set_function_length(promise_any, 1.0)
  self.set_function_name(promise_any, "any")
  set_proto_method(promise_ctor, "any", promise_any)
  let promise_with_resolvers = self.make_native("Promise.withResolvers")
  self.set_function_length(promise_with_resolvers, 0.0)
  self.set_function_name(promise_with_resolvers, "withResolvers")
  set_proto_method(promise_ctor, "withResolvers", promise_with_resolvers)
  let promise_try = self.make_native("Promise.try")
  self.set_function_length(promise_try, 1.0)
  self.set_function_name(promise_try, "try")
  set_proto_method(promise_ctor, "try", promise_try)
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
  set_global_ctor(global_obj, "Promise", promise_ctor)

  // Iterator helpers (minimal)
  let iterator_proto = self.new_object()
  let iterator_ctor = self.make_native("Iterator")
  self.set_function_length(iterator_ctor, 0.0)
  self.set_function_name(iterator_ctor, "Iterator")
  let _ = js_define_data_prop(
    iterator_ctor, "prototype", iterator_proto, false, false, false,
  )
  set_proto_method(iterator_proto, "constructor", iterator_ctor)
  let iterator_iter = self.make_native("Iterator.prototype[@@iterator]")
  self.set_function_length(iterator_iter, 0.0)
  let _ = js_define_data_prop(
    iterator_proto, "@@iterator", iterator_iter, true, false, true,
  )
  let iterator_from = self.make_native("Iterator.from")
  self.set_function_length(iterator_from, 1.0)
  self.set_function_name(iterator_from, "from")
  let _ = js_define_data_prop(
    iterator_ctor, "from", iterator_from, true, false, true,
  )
  let iter_map = self.make_native("Iterator.prototype.map")
  self.set_function_length(iter_map, 1.0)
  self.set_function_name(iter_map, "map")
  let _ = js_define_data_prop(
    iterator_proto, "map", iter_map, true, false, true,
  )
  let iter_filter = self.make_native("Iterator.prototype.filter")
  self.set_function_length(iter_filter, 1.0)
  self.set_function_name(iter_filter, "filter")
  let _ = js_define_data_prop(
    iterator_proto, "filter", iter_filter, true, false, true,
  )
  let iter_take = self.make_native("Iterator.prototype.take")
  self.set_function_length(iter_take, 1.0)
  self.set_function_name(iter_take, "take")
  let _ = js_define_data_prop(
    iterator_proto, "take", iter_take, true, false, true,
  )
  let iter_drop = self.make_native("Iterator.prototype.drop")
  self.set_function_length(iter_drop, 1.0)
  self.set_function_name(iter_drop, "drop")
  let _ = js_define_data_prop(
    iterator_proto, "drop", iter_drop, true, false, true,
  )
  let iter_flat_map = self.make_native("Iterator.prototype.flatMap")
  self.set_function_length(iter_flat_map, 1.0)
  self.set_function_name(iter_flat_map, "flatMap")
  let _ = js_define_data_prop(
    iterator_proto, "flatMap", iter_flat_map, true, false, true,
  )
  let iter_for_each = self.make_native("Iterator.prototype.forEach")
  self.set_function_length(iter_for_each, 1.0)
  self.set_function_name(iter_for_each, "forEach")
  let _ = js_define_data_prop(
    iterator_proto, "forEach", iter_for_each, true, false, true,
  )
  let iter_to_array = self.make_native("Iterator.prototype.toArray")
  self.set_function_length(iter_to_array, 0.0)
  self.set_function_name(iter_to_array, "toArray")
  let _ = js_define_data_prop(
    iterator_proto, "toArray", iter_to_array, true, false, true,
  )
  let iter_reduce = self.make_native("Iterator.prototype.reduce")
  self.set_function_length(iter_reduce, 1.0)
  self.set_function_name(iter_reduce, "reduce")
  let _ = js_define_data_prop(
    iterator_proto, "reduce", iter_reduce, true, false, true,
  )
  let iter_every = self.make_native("Iterator.prototype.every")
  self.set_function_length(iter_every, 1.0)
  self.set_function_name(iter_every, "every")
  let _ = js_define_data_prop(
    iterator_proto, "every", iter_every, true, false, true,
  )
  let iter_some = self.make_native("Iterator.prototype.some")
  self.set_function_length(iter_some, 1.0)
  self.set_function_name(iter_some, "some")
  let _ = js_define_data_prop(
    iterator_proto, "some", iter_some, true, false, true,
  )
  let iter_find = self.make_native("Iterator.prototype.find")
  self.set_function_length(iter_find, 1.0)
  self.set_function_name(iter_find, "find")
  let _ = js_define_data_prop(
    iterator_proto, "find", iter_find, true, false, true,
  )
  let helper_proto = self.new_object()
  let helper_next = self.make_native("IteratorHelper.prototype.next")
  self.set_function_length(helper_next, 0.0)
  self.set_function_name(helper_next, "next")
  let _ = js_define_data_prop(
    helper_proto, "next", helper_next, true, false, true,
  )
  let helper_return = self.make_native("IteratorHelper.prototype.return")
  self.set_function_length(helper_return, 0.0)
  self.set_function_name(helper_return, "return")
  let _ = js_define_data_prop(
    helper_proto, "return", helper_return, true, false, true,
  )
  let helper_throw = self.make_native("IteratorHelper.prototype.throw")
  self.set_function_length(helper_throw, 0.0)
  self.set_function_name(helper_throw, "throw")
  let _ = js_define_data_prop(
    helper_proto, "throw", helper_throw, true, false, true,
  )
  set_proto_method(helper_proto, "__proto__", iterator_proto)
  set_proto_method(iterator_ctor, "__helper_proto", helper_proto)
  self.global_env.define_var("Iterator", iterator_ctor)
  let _ = js_define_data_prop(
    global_obj, "Iterator", iterator_ctor, true, false, true,
  )
  let test262_ctor = self.make_native("Test262Error")
  self.set_function_name(test262_ctor, "Test262Error")
  let _ = js_define_data_prop(
    test262_ctor,
    "prototype",
    self.new_object(),
    true,
    false,
    true,
  )
  let test262_thrower = self.make_native("Test262Error.thrower")
  self.set_function_length(test262_thrower, 0.0)
  let _ = js_set_prop(test262_ctor, "thrower", test262_thrower)
  self.global_env.define_var("Test262Error", test262_ctor)
  set_global_ctor(global_obj, "Test262Error", test262_ctor)

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
  let _ = js_set_prop(assert_obj, "throws", self.make_native("assert.throws"))
  self.global_env.define_var("assert", assert_obj)
  set_global_ctor(global_obj, "assert", assert_obj)

  // compareArray (deprecated, but still used in some test262 tests)
  let compare_array_fn = self.make_native("compareArray")
  self.global_env.define_var("compareArray", compare_array_fn)
  set_global_ctor(global_obj, "compareArray", compare_array_fn)

  // print
  let print_fn = self.make_native("print")
  self.global_env.define_var("print", print_fn)
  set_global_ctor(global_obj, "print", print_fn)

  // gc - VM-level garbage collection
  let gc_fn = self.make_native("gc")
  self.set_function_length(gc_fn, 0.0)
  self.global_env.define_var("gc", gc_fn)
  set_global_ctor(global_obj, "gc", gc_fn)

  // $enterScope - Perceus scope management
  let enter_scope_fn = self.make_native("$enterScope")
  self.set_function_length(enter_scope_fn, 0.0)
  self.global_env.define_var("$enterScope", enter_scope_fn)
  set_global_ctor(global_obj, "$enterScope", enter_scope_fn)

  // $exitScope - Exit scope and cleanup unreachable objects
  let exit_scope_fn = self.make_native("$exitScope")
  self.set_function_length(exit_scope_fn, 0.0)
  self.global_env.define_var("$exitScope", exit_scope_fn)
  set_global_ctor(global_obj, "$exitScope", exit_scope_fn)

  // $markEscaped - Mark an object as escaped from current scope
  let mark_escaped_fn = self.make_native("$markEscaped")
  self.set_function_length(mark_escaped_fn, 1.0)
  self.global_env.define_var("$markEscaped", mark_escaped_fn)
  set_global_ctor(global_obj, "$markEscaped", mark_escaped_fn)
  let escape_fn = self.make_native("escape")
  self.set_function_length(escape_fn, 1.0)
  self.global_env.define_var("escape", escape_fn)
  let _ = js_define_data_prop(global_obj, "escape", escape_fn, true, false, true)
  let unescape_fn = self.make_native("unescape")
  self.set_function_length(unescape_fn, 1.0)
  self.global_env.define_var("unescape", unescape_fn)
  let _ = js_define_data_prop(global_obj, "unescape", unescape_fn, true, false, true)

  // eval
  let eval_fn = self.make_native("eval")
  self.set_function_length(eval_fn, 1.0)
  self.global_env.define_var("eval", eval_fn)
  let _ = js_define_data_prop(global_obj, "eval", eval_fn, true, false, true)

  // queueMicrotask
  let queue_microtask_fn = self.make_native("queueMicrotask")
  self.set_function_length(queue_microtask_fn, 1.0)
  self.global_env.define_var("queueMicrotask", queue_microtask_fn)
  let _ = js_define_data_prop(global_obj, "queueMicrotask", queue_microtask_fn, true, false, true)

  // $DONOTEVALUATE
  let donotevaluate_fn = self.make_native("$DONOTEVALUATE")
  self.global_env.define_var("$DONOTEVALUATE", donotevaluate_fn)
  set_global_ctor(global_obj, "$DONOTEVALUATE", donotevaluate_fn)

  // $ERROR / $DONE
  let error_fn = self.make_native("$ERROR")
  self.global_env.define_var("$ERROR", error_fn)
  set_global_ctor(global_obj, "$ERROR", error_fn)
  let done_fn = self.make_native("$DONE")
  self.global_env.define_var("$DONE", done_fn)
  set_global_ctor(global_obj, "$DONE", done_fn)

  // $262
  let t262 = self.new_object()
  let _ = js_set_prop(t262, "global", global_obj)
  let _ = js_set_prop(t262, "evalScript", self.make_native("$262.evalScript"))
  let _ = js_set_prop(t262, "createRealm", self.make_native("$262.createRealm"))
  let _ = js_set_prop(
    t262,
    "detachArrayBuffer",
    self.make_native("$262.detachArrayBuffer"),
  )
  let html_dda = self.new_object()
  let _ = js_set_prop(html_dda, "__class", String("IsHTMLDDA"))
  let _ = js_set_prop(html_dda, "$call", self.make_native("IsHTMLDDA"))
  let _ = js_set_prop(t262, "IsHTMLDDA", html_dda)
  self.global_env.define_var("$262", t262)
  set_global_ctor(global_obj, "$262", t262)

  // testTypedArray.js harness functions
  // Note: Constructor arrays are set up in install_collections
  let test_with_ta = self.make_native("testWithTypedArrayConstructors")
  self.global_env.define_var("testWithTypedArrayConstructors", test_with_ta)
  let _ = js_set_prop(
    global_obj, "testWithTypedArrayConstructors", test_with_ta,
  )
  let test_with_atomics = self.make_native(
    "testWithAtomicsFriendlyTypedArrayConstructors",
  )
  self.global_env.define_var(
    "testWithAtomicsFriendlyTypedArrayConstructors", test_with_atomics,
  )
  let _ = js_set_prop(
    global_obj, "testWithAtomicsFriendlyTypedArrayConstructors", test_with_atomics,
  )
  let test_with_non_atomics = self.make_native(
    "testWithNonAtomicsFriendlyTypedArrayConstructors",
  )
  self.global_env.define_var(
    "testWithNonAtomicsFriendlyTypedArrayConstructors", test_with_non_atomics,
  )
  let _ = js_set_prop(
    global_obj, "testWithNonAtomicsFriendlyTypedArrayConstructors", test_with_non_atomics,
  )
  let detach_buffer = self.make_native("$DETACHBUFFER")
  self.global_env.define_var("$DETACHBUFFER", detach_buffer)
  set_global_ctor(global_obj, "$DETACHBUFFER", detach_buffer)
  let test_with_bigint_ta = self.make_native(
    "testWithBigIntTypedArrayConstructors",
  )
  self.global_env.define_var(
    "testWithBigIntTypedArrayConstructors", test_with_bigint_ta,
  )
  let _ = js_set_prop(
    global_obj, "testWithBigIntTypedArrayConstructors", test_with_bigint_ta,
  )

  // globalThis / global
  self.global_env.define_var("globalThis", global_obj)
  self.global_env.define_var("global", global_obj)
  self.global_env.define_var("this", global_obj)
  self.global_env.define_var("undefined", Undefined)
  // Global constants: writable:false, enumerable:false, configurable:false (ES5.1 15.1.1)
  let _ = js_define_data_prop(
    global_obj,
    "undefined",
    Undefined,
    false,
    false,
    false,
  )
  let nan = JSValue::Number(0.0 / 0.0)
  let inf = JSValue::Number(1.0 / 0.0)
  self.global_env.define_var("NaN", nan)
  self.global_env.define_var("Infinity", inf)
  let _ = js_define_data_prop(global_obj, "NaN", nan, false, false, false)
  let _ = js_define_data_prop(global_obj, "Infinity", inf, false, false, false)

  // Global functions: isNaN, isFinite, parseInt, parseFloat
  // { [[Writable]]: true, [[Enumerable]]: false, [[Configurable]]: true }
  let is_nan_fn = self.make_native("isNaN")
  self.set_function_length(is_nan_fn, 1.0)
  self.global_env.define_var("isNaN", is_nan_fn)
  let _ = js_define_data_prop(global_obj, "isNaN", is_nan_fn, true, false, true)
  let is_finite_fn = self.make_native("isFinite")
  self.set_function_length(is_finite_fn, 1.0)
  self.global_env.define_var("isFinite", is_finite_fn)
  let _ = js_define_data_prop(global_obj, "isFinite", is_finite_fn, true, false, true)
  let parse_int_fn = self.make_native("parseInt")
  self.set_function_length(parse_int_fn, 2.0)
  self.global_env.define_var("parseInt", parse_int_fn)
  let _ = js_define_data_prop(global_obj, "parseInt", parse_int_fn, true, false, true)
  let parse_float_fn = self.make_native("parseFloat")
  self.set_function_length(parse_float_fn, 1.0)
  self.global_env.define_var("parseFloat", parse_float_fn)
  let _ = js_define_data_prop(global_obj, "parseFloat", parse_float_fn, true, false, true)
  self.install_symbol(global_obj)

  // Proxy (minimal)
  let proxy_ctor = self.make_native("Proxy")
  self.set_function_length(proxy_ctor, 2.0)
  self.set_function_name(proxy_ctor, "Proxy")
  let _ = js_define_data_prop(
    proxy_ctor,
    "prototype",
    self.new_object(),
    true,
    false,
    true,
  )
  self.global_env.define_var("Proxy", proxy_ctor)
  set_global_ctor(global_obj, "Proxy", proxy_ctor)

  // Reflect
  let reflect = self.new_object()
  set_proto_method(reflect, "construct", self.make_native("Reflect.construct"))
  let reflect_get = self.make_native("Reflect.get")
  self.set_function_length(reflect_get, 2.0)
  self.set_function_name(reflect_get, "get")
  set_proto_method(reflect, "get", reflect_get)
  let reflect_set = self.make_native("Reflect.set")
  self.set_function_length(reflect_set, 3.0)
  self.set_function_name(reflect_set, "set")
  set_proto_method(reflect, "set", reflect_set)
  let reflect_has = self.make_native("Reflect.has")
  self.set_function_length(reflect_has, 2.0)
  self.set_function_name(reflect_has, "has")
  set_proto_method(reflect, "has", reflect_has)
  let reflect_define = self.make_native("Reflect.defineProperty")
  self.set_function_length(reflect_define, 3.0)
  self.set_function_name(reflect_define, "defineProperty")
  set_proto_method(reflect, "defineProperty", reflect_define)
  let reflect_get_proto = self.make_native("Reflect.getPrototypeOf")
  self.set_function_length(reflect_get_proto, 1.0)
  self.set_function_name(reflect_get_proto, "getPrototypeOf")
  set_proto_method(reflect, "getPrototypeOf", reflect_get_proto)
  let reflect_get_desc = self.make_native("Reflect.getOwnPropertyDescriptor")
  self.set_function_length(reflect_get_desc, 2.0)
  self.set_function_name(reflect_get_desc, "getOwnPropertyDescriptor")
  set_proto_method(reflect, "getOwnPropertyDescriptor", reflect_get_desc)
  self.global_env.define_var("Reflect", reflect)
  set_global_ctor(global_obj, "Reflect", reflect)
  self.install_collections(global_obj)
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
        let use_string = match str_value {
          Some(s) => not(has_prop) && i >= 0 && i < s.length()
          None => false
        }
        if has_prop {
          let value = self.get_prop_value(receiver, key)
          parts.push(value.to_js_string())
        } else if use_string {
          match str_value {
            Some(s) => parts.push(s[i:i + 1].to_string() catch { _ => "" })
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
        let use_string = match str_value {
          Some(s) => not(has_prop) && i >= 0 && i < s.length()
          None => false
        }
        if not(has_prop) && not(use_string) {
          continue
        }
        let value = if has_prop {
          self.get_prop_value(receiver, key)
        } else {
          match str_value {
            Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
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
        let use_string = match str_value {
          Some(s) => not(has_prop) && i >= 0 && i < s.length()
          None => false
        }
        if has_prop || use_string {
          let value = if has_prop {
            self.get_prop_value(receiver, key)
          } else {
            match str_value {
              Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
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
        let value = if js_has_prop(receiver, key) {
          self.get_prop_value(receiver, key)
        } else {
          match str_value {
            Some(s) if i >= 0 && i < s.length() =>
              String(s[i:i + 1].to_string() catch { _ => "" })
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
        self.set_error_kind(
          "TypeError", "Array.prototype.map requires a callback",
        )
      } else {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError", "Array.prototype.map requires a callback",
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
              let use_string = match str_value {
                Some(s) => not(has_prop) && i >= 0 && i < s.length()
                None => false
              }
              if has_prop || use_string {
                let value = if has_prop {
                  self.get_prop_value(receiver, key)
                } else {
                  match str_value {
                    Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
                    None => Undefined
                  }
                }
                let args_array = [value, Number(i.to_double()), receiver]
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
        self.set_error_kind(
          "TypeError", "Array.prototype.filter requires a callback",
        )
      } else {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError", "Array.prototype.filter requires a callback",
          )
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let result : Array[JSValue] = []
        let mut i = 0
        while i < len {
          let key = i.to_string()
          let has_prop = js_has_prop(receiver, key)
          let use_string = match str_value {
            Some(s) => not(has_prop) && i >= 0 && i < s.length()
            None => false
          }
          if has_prop || use_string {
            let item = if has_prop {
              self.get_prop_value(receiver, key)
            } else {
              match str_value {
                Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
                None => Undefined
              }
            }
            let args_array = [item, Number(i.to_double()), receiver]
            let filtered = self.call_function(callback, this_arg, args_array)
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
        self.set_error_kind(
          "TypeError", "Array.prototype.reduce requires a callback",
        )
      } else {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError", "Array.prototype.reduce requires a callback",
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
            let use_string = match str_value {
              Some(s) => not(has_prop) && i >= 0 && i < s.length()
              None => false
            }
            if has_prop || use_string {
              accumulator = if has_prop {
                self.get_prop_value(receiver, key)
              } else {
                match str_value {
                  Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
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
              "TypeError", "Reduce of empty array with no initial value",
            )
          }
        }
        while i < len {
          let key = i.to_string()
          let has_prop = js_has_prop(receiver, key)
          let use_string = match str_value {
            Some(s) => not(has_prop) && i >= 0 && i < s.length()
            None => false
          }
          if has_prop || use_string {
            let value = if has_prop {
              self.get_prop_value(receiver, key)
            } else {
              match str_value {
                Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
                None => Undefined
              }
            }
            let args_array = [
              accumulator,
              value,
              Number(i.to_double()),
              receiver,
            ]
            accumulator = self.call_function(callback, Undefined, args_array)
          }
          i += 1
        }
        accumulator
      }
    "reduceRight" =>
      if args.length() == 0 {
        self.set_error_kind(
          "TypeError", "Array.prototype.reduceRight requires a callback",
        )
      } else {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError", "Array.prototype.reduceRight requires a callback",
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
            let use_string = match str_value {
              Some(s) => not(has_prop) && i >= 0 && i < s.length()
              None => false
            }
            if has_prop || use_string {
              accumulator = if has_prop {
                self.get_prop_value(receiver, key)
              } else {
                match str_value {
                  Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
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
              "TypeError", "Reduce of empty array with no initial value",
            )
          }
        }
        while i >= 0 {
          let key = i.to_string()
          let has_prop = js_has_prop(receiver, key)
          let use_string = match str_value {
            Some(s) => not(has_prop) && i >= 0 && i < s.length()
            None => false
          }
          if has_prop || use_string {
            let value = if has_prop {
              self.get_prop_value(receiver, key)
            } else {
              match str_value {
                Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
                None => Undefined
              }
            }
            let args_array = [
              accumulator,
              value,
              Number(i.to_double()),
              receiver,
            ]
            accumulator = self.call_function(callback, Undefined, args_array)
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
        self.set_error_kind(
          "TypeError", "Array.prototype.forEach requires a callback",
        )
      } else {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError", "Array.prototype.forEach requires a callback",
          )
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let mut i = 0
        while i < len {
          let key = i.to_string()
          let has_prop = js_has_prop(receiver, key)
          let use_string = match str_value {
            Some(s) => not(has_prop) && i >= 0 && i < s.length()
            None => false
          }
          if has_prop || use_string {
            let value = if has_prop {
              self.get_prop_value(receiver, key)
            } else {
              match str_value {
                Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
                None => Undefined
              }
            }
            let args_array = [value, Number(i.to_double()), receiver]
            let _ = self.call_function(callback, this_arg, args_array)

          }
          i += 1
        }
        Undefined
      }
    "every" =>
      if args.length() == 0 {
        self.set_error_kind(
          "TypeError", "Array.prototype.every requires a callback",
        )
      } else {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError", "Array.prototype.every requires a callback",
          )
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let mut i = 0
        while i < len {
          let key = i.to_string()
          let has_prop = js_has_prop(receiver, key)
          let use_string = match str_value {
            Some(s) => not(has_prop) && i >= 0 && i < s.length()
            None => false
          }
          if has_prop || use_string {
            let value = if has_prop {
              self.get_prop_value(receiver, key)
            } else {
              match str_value {
                Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
                None => Undefined
              }
            }
            let args_array = [value, Number(i.to_double()), receiver]
            let ok = self.call_function(callback, this_arg, args_array)
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
        self.set_error_kind(
          "TypeError", "Array.prototype.some requires a callback",
        )
      } else {
        let callback = args[0]
        if not(self.is_callable(callback)) {
          return self.set_error_kind(
            "TypeError", "Array.prototype.some requires a callback",
          )
        }
        let this_arg = if args.length() > 1 { args[1] } else { Undefined }
        let mut i = 0
        while i < len {
          let key = i.to_string()
          let has_prop = js_has_prop(receiver, key)
          let use_string = match str_value {
            Some(s) => not(has_prop) && i >= 0 && i < s.length()
            None => false
          }
          if has_prop || use_string {
            let value = if has_prop {
              self.get_prop_value(receiver, key)
            } else {
              match str_value {
                Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
                None => Undefined
              }
            }
            let args_array = [value, Number(i.to_double()), receiver]
            let ok = self.call_function(callback, this_arg, args_array)
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
          let use_string = match str_value {
            Some(s) => not(has_prop) && i >= 0 && i < s.length()
            None => false
          }
          if has_prop || use_string {
            let item = if has_prop {
              self.get_prop_value(receiver, key)
            } else {
              match str_value {
                Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
                None => Undefined
              }
            }
            let args_array = [item, Number(i.to_double()), receiver]
            let found = self.call_function(callback, this_arg, args_array)
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
          let use_string = match str_value {
            Some(s) => not(has_prop) && i >= 0 && i < s.length()
            None => false
          }
          if has_prop || use_string {
            let item = if has_prop {
              self.get_prop_value(receiver, key)
            } else {
              match str_value {
                Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
                None => Undefined
              }
            }
            let args_array = [item, Number(i.to_double()), receiver]
            let found = self.call_function(callback, this_arg, args_array)
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
          let use_string = match str_value {
            Some(s) => not(has_prop) && i >= 0 && i < s.length()
            None => false
          }
          if has_prop || use_string {
            let item = if has_prop {
              self.get_prop_value(receiver, key)
            } else {
              match str_value {
                Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
                None => Undefined
              }
            }
            let args_array = [item, Number(i.to_double()), receiver]
            let found = self.call_function(callback, this_arg, args_array)
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
          let use_string = match str_value {
            Some(s) => not(has_prop) && i >= 0 && i < s.length()
            None => false
          }
          if has_prop || use_string {
            let item = if has_prop {
              self.get_prop_value(receiver, key)
            } else {
              match str_value {
                Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
                None => Undefined
              }
            }
            let args_array = [item, Number(i.to_double()), receiver]
            let found = self.call_function(callback, this_arg, args_array)
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
            let has_prop = js_has_prop(receiver, key)
            let use_string = match str_value {
              Some(s) => not(has_prop) && i >= 0 && i < s.length()
              None => false
            }
            if has_prop || use_string {
              let value = if has_prop {
                self.get_prop_value(receiver, key)
              } else {
                match str_value {
                  Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
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
      let mut start = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
      let mut end = if args.length() > 2 {
        args[2].to_number().to_int()
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
        self.set_prop_value(receiver, i.to_string(), value)
      }
      self.set_prop_value(receiver, "length", Number(len.to_double()))
      receiver
    }
    "flat" => {
      let depth = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        1
      }
      if len <= 0 {
        return js_new_array()
      }
      let items : Array[JSValue] = []
      for i in 0..<len {
        let key = i.to_string()
        let has_prop = js_has_prop(receiver, key)
        let use_string = match str_value {
          Some(s) => not(has_prop) && i >= 0 && i < s.length()
          None => false
        }
        if has_prop || use_string {
          let value = if has_prop {
            self.get_prop_value(receiver, key)
          } else {
            match str_value {
              Some(s) => String(s[i:i + 1].to_string() catch { _ => "" })
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
      let mut idx = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
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
              String(s[idx:idx + 1].to_string() catch { _ => "" })
            _ => Undefined
          }
        }
      }
    }
    _ => Undefined
  }
}

///|
fn JSInterpreter::eval_script_source(
  self : JSInterpreter,
  source : String,
) -> JSValue {
  self.eval_script_source_with_strict(source, false)
}

///|
fn JSInterpreter::eval_script_source_with_strict(
  self : JSInterpreter,
  source : String,
  inherit_strict : Bool,
) -> JSValue {
  let block = @parser.parse_block_from_source_strict(source, inherit_strict) catch {
    @parser.ParseError::ParseError(msg) => {
      let _ = self.set_error_kind("SyntaxError", msg)
      return Undefined
    }
  }
  self.hoist_block(block, self.global_env)
  // Use exec_block_for_eval to properly track completion values
  let result = match self.exec_block_for_eval(block, self.global_env) {
    // For break/continue signals, use the completion value with UpdateEmpty
    (Some(BreakSignal(_)), completion)
    | (Some(ContinueSignal(_)), completion) =>
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
fn JSInterpreter::new_array_iterator(
  self : JSInterpreter,
  receiver : JSValue,
) -> JSValue {
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
  set_proto_method(iter, "next", next_fn)
  let iter_fn = self.make_native("Iterator.prototype[@@iterator]")
  self.set_function_length(iter_fn, 0.0)
  set_proto_method(iter, "@@iterator", iter_fn)
  iter
}

///|
fn JSInterpreter::new_string_iterator(
  self : JSInterpreter,
  value : String,
) -> JSValue {
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
  set_proto_method(iter, "next", next_fn)
  let iter_fn = self.make_native("Iterator.prototype[@@iterator]")
  self.set_function_length(iter_fn, 0.0)
  set_proto_method(iter, "@@iterator", iter_fn)
  iter
}

///|
fn JSInterpreter::own_property_keys(
  _self : JSInterpreter,
  obj : JSValue,
) -> Array[String] {
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
          let ch = JSValue::String(s[idx:idx + 1].to_string() catch { _ => "" })
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
  // Static "prototype" property on a function/class is not allowed to be redefined as a method
  // (ES6 14.5.14: It is a TypeError to attempt to define a static "prototype" method on a class)
  if key == "prototype" {
    match target {
      Function(_) =>
        // Check if this is trying to define a method (has "value" that is a function)
        match desc {
          Object(_) | Function(_) => {
            let has_value = self.has_own_prop(desc, "value")
            let has_get = self.has_own_prop(desc, "get")
            let has_set = self.has_own_prop(desc, "set")
            if has_value || has_get || has_set {
              return self.set_error_kind(
                "TypeError", "Cannot define property 'prototype' on a class constructor",
              )
            }
          }
          _ => ()
        }
      _ => ()
    }
  }
  let is_obj = match desc {
    Object(_) | Function(_) => true
    _ => false
  }
  if not(is_obj) {
    return self.set_error_kind(
      "TypeError", "Property description must be an object",
    )
  }
  let has_get = self.has_own_prop(desc, "get")
  let has_set = self.has_own_prop(desc, "set")
  let has_value = self.has_own_prop(desc, "value")
  let has_writable = self.has_own_prop(desc, "writable")
  if (has_get || has_set) && (has_value || has_writable) {
    return self.set_error_kind("TypeError", "Invalid property descriptor")
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
    let get_val = if has_get {
      self.get_prop_value(desc, "get")
    } else {
      match current {
        Some(prop) =>
          match prop.get {
            Some(g) => g
            None => Undefined
          }
        None => Undefined
      }
    }
    let set_val = if has_set {
      self.get_prop_value(desc, "set")
    } else {
      match current {
        Some(prop) =>
          match prop.set {
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
    let _ = js_define_accessor_prop(
      target, key, getter, setter, enumerable, configurable,
    )
    target
  } else {
    let value = if has_value {
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
    let _ = js_define_data_prop(
      target, key, value, writable, enumerable, configurable,
    )
    target
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
    let mut method_name = (name[15:] catch { _ => "" }).to_string()
    if method_name.has_prefix(".") {
      method_name = (method_name[1:] catch { _ => "" }).to_string()
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
      Bool(_) | Number(_) | String(_) =>
        self.wrap_primitive(self.global_env, this_arg)
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
    let mut method_name = (name[16:] catch { _ => "" }).to_string()
    if method_name.has_prefix(".") {
      method_name = (method_name[1:] catch { _ => "" }).to_string()
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
        let s = match this_arg {
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
  // Math dispatch
  if name.has_prefix("Math.") {
    match self.call_math_native(name, args) {
      Some(result) => return result
      None => ()
    }
  }
  // Object dispatch
  if name.has_prefix("Object.") {
    match self.call_object_native(name, this_arg, args) {
      Some(result) => return result
      None => ()
    }
  }
  // Iterator dispatch
  if name.has_prefix("Iterator.") ||
    name.has_prefix("IteratorHelper.") ||
    name.has_prefix("ArrayIterator.") ||
    name.has_prefix("StringIterator.") ||
    name.has_prefix("Generator.") ||
    name.has_prefix("MapIterator.") ||
    name.has_prefix("SetIterator.") {
    match self.call_iterator_native(name, this_arg, args) {
      Some(result) => return result
      None => ()
    }
  }
  match name {
    "Promise" =>
      self.set_error_kind(
        "TypeError", "Promise constructor must be called with new",
      )
    "Promise.resolve" => {
      let value = if args.length() > 0 { args[0] } else { Undefined }
      match this_arg {
        Object(_) | Function(_) =>
          self.promise_static_resolve_with_ctor(this_arg, value)
        _ =>
          self.set_error_kind(
            "TypeError", "Promise.resolve called on non-object",
          )
      }
    }
    "Promise.reject" => {
      let reason = if args.length() > 0 { args[0] } else { Undefined }
      match this_arg {
        Object(_) | Function(_) =>
          self.promise_static_reject_with_ctor(this_arg, reason)
        _ =>
          self.set_error_kind(
            "TypeError", "Promise.reject called on non-object",
          )
      }
    }
    "Promise.prototype.then" => {
      if not(self.is_promise(this_arg)) {
        return self.set_error_kind(
          "TypeError", "Promise.prototype.then called on non-Promise",
        )
      }
      let on_fulfilled = if args.length() > 0 { args[0] } else { Undefined }
      let on_rejected = if args.length() > 1 { args[1] } else { Undefined }
      let ctor = self.promise_species_constructor(this_arg)
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      let (result_promise, _resolve, _reject) = self.promise_new_capability(
        ctor,
      )
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      self.perform_promise_then(
        this_arg, on_fulfilled, on_rejected, result_promise,
      )
    }
    "Promise.prototype.catch" => {
      let on_rejected = if args.length() > 0 { args[0] } else { Undefined }
      let target = match this_arg {
        Undefined | Null =>
          return self.set_error_kind(
            "TypeError", "Promise.prototype.catch called on null or undefined",
          )
        Bool(_) | Number(_) | String(_) =>
          self.wrap_primitive(self.global_env, this_arg)
        _ => this_arg
      }
      let then_method = self.get_prop_value(target, "then")
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      if not(self.is_callable(then_method)) {
        return self.set_error_kind(
          "TypeError", "Promise.prototype.catch called on non-callable then",
        )
      }
      self.call_function(then_method, this_arg, [Undefined, on_rejected])
    }
    "Promise.prototype.finally" => {
      let on_finally = if args.length() > 0 { args[0] } else { Undefined }
      let target = match this_arg {
        Undefined | Null =>
          return self.set_error_kind(
            "TypeError", "Promise.prototype.finally called on null or undefined",
          )
        Bool(_) | Number(_) | String(_) =>
          self.wrap_primitive(self.global_env, this_arg)
        _ => this_arg
      }
      let then_method = self.get_prop_value(target, "then")
      match self.peek_error() {
        Some(err) => return err
        None => ()
      }
      if not(self.is_callable(then_method)) {
        return self.set_error_kind(
          "TypeError", "Promise.prototype.finally called on non-callable then",
        )
      }
      if not(self.is_callable(on_finally)) {
        return self.call_function(then_method, this_arg, [
          on_finally, on_finally,
        ])
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
      self.call_function(then_method, this_arg, [
        fulfill_handler, reject_handler,
      ])
    }
    "Promise.withResolvers" =>
      match this_arg {
        Object(_) | Function(_) => self.promise_with_resolvers(this_arg)
        _ =>
          self.set_error_kind(
            "TypeError", "Promise.withResolvers called on non-object",
          )
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
            self.set_error_kind(
              "TypeError", "Promise.try called on non-constructor",
            )
          } else {
            self.promise_try(this_arg, callback, rest_args)
          }
        _ =>
          self.set_error_kind("TypeError", "Promise.try called on non-object")
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
            return self.set_error_kind(
              "TypeError", "Promise capability already initialized",
            )
          }
          let _ = js_set_prop(cap, "resolve", resolve)
          let _ = js_set_prop(cap, "reject", reject)

        }
        _ => ()
      }
      Undefined
    }
    "Promise.__return_value__" =>
      if args.length() > 0 {
        args[0]
      } else {
        Undefined
      }
    "Promise.__throw_reason__" => {
      let reason = if args.length() > 0 { args[0] } else { Undefined }
      self.last_error = Some(reason)
      reason
    }
    "Promise.__finally_fulfill__" => {
      let on_finally = if args.length() > 0 { args[0] } else { Undefined }
      let ctor = if args.length() > 1 {
        args[1]
      } else {
        self.global_env.get("Promise")
      }
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
            let result_promise = self.promise_static_resolve_with_ctor(
              ctor, result,
            )
            let returner = self.make_bound_native("Promise.__return_value__", [
              value,
            ])
            return self.promise_then(result_promise, returner, Undefined)
          }
        }
      }
      value
    }
    "Promise.__finally_reject__" => {
      let on_finally = if args.length() > 0 { args[0] } else { Undefined }
      let ctor = if args.length() > 1 {
        args[1]
      } else {
        self.global_env.get("Promise")
      }
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
            let result_promise = self.promise_static_resolve_with_ctor(
              ctor, result,
            )
            let thrower = self.make_bound_native("Promise.__throw_reason__", [
              reason,
            ])
            return self.promise_then(result_promise, thrower, Undefined)
          }
        }
      }
      self.last_error = Some(reason)
      reason
    }
    "Promise.__all_fulfill__" => {
      let state = if args.length() > 0 { args[0] } else { Undefined }
      let index = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
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
      let index = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
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
      let index = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
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
      let index = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
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
        Object(_) | Function(_) =>
          self.promise_all_with_ctor(this_arg, iter, false)
        _ =>
          self.set_error_kind("TypeError", "Promise.all called on non-object")
      }
    }
    "Promise.race" => {
      let iter = if args.length() > 0 { args[0] } else { Undefined }
      match this_arg {
        Object(_) | Function(_) => self.promise_race_with_ctor(this_arg, iter)
        _ =>
          self.set_error_kind("TypeError", "Promise.race called on non-object")
      }
    }
    "Promise.allSettled" => {
      let iter = if args.length() > 0 { args[0] } else { Undefined }
      match this_arg {
        Object(_) | Function(_) =>
          self.promise_all_with_ctor(this_arg, iter, true)
        _ =>
          self.set_error_kind(
            "TypeError", "Promise.allSettled called on non-object",
          )
      }
    }
    "Promise.any" => {
      let iter = if args.length() > 0 { args[0] } else { Undefined }
      match this_arg {
        Object(_) | Function(_) => self.promise_any_with_ctor(this_arg, iter)
        _ =>
          self.set_error_kind("TypeError", "Promise.any called on non-object")
      }
    }
    "queueMicrotask" => {
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      if not(self.is_callable(callback)) {
        return self.set_error_kind(
          "TypeError", "queueMicrotask callback is not callable",
        )
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
    "IsHTMLDDA" => Null
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
      } else if trimmed.length() >= 2 &&
        trimmed.has_prefix("\"") &&
        trimmed.has_suffix("\"") {
        let inner = trimmed[1:trimmed.length() - 1].to_string() catch {
          _ => ""
        }
        String(self.json_unescape(inner))
      } else {
        let num = @strconv.parse_double(trimmed) catch {
          _ => return self.set_error_kind("SyntaxError", "Invalid JSON")
        }
        Number(num)
      }
    }
    "JSON.stringify" =>
      if args.length() == 0 {
        Undefined
      } else {
        let value = args[0]
        match self.json_stringify_value(value, 0, false) {
          Some(s) => String(s)
          None => Undefined
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
      let source = "function __f__(" + params_src + ") {\n" + body_src + "\n}"
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
            is_async: func.is_async,
            props: [],
            object_proto: Some(self.function_proto),
          })
          let formal_count = calc_formal_parameter_count(func.params)
          self.set_function_length(closure, formal_count.to_double())
          let proto = self.new_object()
          let _ = js_define_data_prop(
            proto, "constructor", closure, true, false, true,
          )
          let _ = js_define_data_prop(
            closure, "prototype", proto, true, false, true,
          )
          closure
        }
      } catch {
        @parser.ParseError::ParseError(msg) => {
          let _ = self.set_error_kind(
            "SyntaxError",
            "Function parse error: " + msg,
          )
          JSValue::Undefined
        }
      }
      func_value
    }
    "Function.prototype" => Undefined
    "Function.prototype[@@hasInstance]" =>
      if args.length() == 0 {
        Bool(false)
      } else {
        Bool(self.ordinary_has_instance(this_arg, args[0]))
      }
    "Function.prototype.toString" =>
      match this_arg {
        Function(closure) => {
          let name_prop = js_get_prop(this_arg, "name")
          let name = match name_prop {
            String(s) => s
            _ => ""
          }
          match closure.body {
            Native(_) => js_string("function \{name}() { [native code] }")
            Bound(_, _, _) => js_string("function \{name}() { [native code] }")
            Compiled(compiled) =>
              // Show as native-like for compiled functions
              js_string("function \{compiled.name}() { [compiled code] }")
            Ast(func) => {
              let params_arr : Array[String] = []
              for p in func.params {
                match p.binding {
                  Some(@ast.TsBinding::Ident(id)) => params_arr.push(id)
                  _ => params_arr.push("_")
                }
              }
              let params_str = params_arr.join(", ")
              if closure.is_arrow {
                if params_arr.length() == 1 {
                  js_string("\{params_str} => {}")
                } else {
                  js_string("(\{params_str}) => {}")
                }
              } else if closure.is_generator {
                js_string("function* \{name}(\{params_str}) {}")
              } else if name == "<anon>" || name == "" {
                js_string("function (\{params_str}) {}")
              } else {
                js_string("function \{name}(\{params_str}) {}")
              }
            }
          }
        }
        _ =>
          self.set_error_kind(
            "TypeError", "Function.prototype.toString requires that 'this' be a Function",
          )
      }
    "Function.call" => {
      let target = this_arg
      if not(self.is_callable(target)) {
        return self.set_error_kind(
          "TypeError", "Function.prototype.call called on non-callable",
        )
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
        return self.set_error_kind(
          "TypeError", "Function.prototype.apply called on non-callable",
        )
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
        return self.set_error_kind(
          "TypeError", "Function.prototype.bind called on non-callable",
        )
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
        is_async: false,
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
    "Array" =>
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
    "Array.isArray" =>
      if args.length() > 0 {
        match args[0] {
          Array(_) => Bool(true)
          _ => Bool(false)
        }
      } else {
        Bool(false)
      }
    "Date" =>
      match this_arg {
        Object(_) => {
          let _ = js_set_prop(this_arg, "__class", String("Date"))
          let time_val = if args.length() == 0 {
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
            let dt = if args.length() > 2 {
              self.to_number_value(args[2])
            } else {
              1.0
            }
            let h = if args.length() > 3 {
              self.to_number_value(args[3])
            } else {
              0.0
            }
            let min = if args.length() > 4 {
              self.to_number_value(args[4])
            } else {
              0.0
            }
            let s = if args.length() > 5 {
              self.to_number_value(args[5])
            } else {
              0.0
            }
            let ms = if args.length() > 6 {
              self.to_number_value(args[6])
            } else {
              0.0
            }
            match self.peek_error() {
              Some(err) => return err
              None =>
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
                  let time_val = @lib.make_date_time(
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
          let _ = js_set_prop(this_arg, "__date_value", Number(time_val))
          this_arg
        }
        _ => String("Date")
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
      let t = if args.length() > 0 {
        self.to_number_value(args[0])
      } else {
        js_nan
      }
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
            let (year, _, _, _, _, _, _) = @lib.break_time(t)
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
            let (year, _, _, _, _, _, _) = @lib.break_time(t)
            Number((year - 1900).to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.setYear" => {
      let t_opt = self.date_time_value(this_arg)
      let t = match t_opt {
        Some(v) => v
        None => return self.error_or_undefined()
      }
      let y = if args.length() > 0 {
        self.to_number_value(args[0])
      } else {
        js_nan
      }
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
            let (_cur_year, month, day, hour, minute, second, milli) = @lib.break_time(
              base_time,
            )
            let new_time = @lib.make_date_time(
              year, month, day, hour, minute, second, milli,
            )
            let clipped = time_clip(new_time)
            let _ = js_set_prop(this_arg, "__date_value", Number(clipped))
            Number(clipped)
          }
        }
      }
    }
    "Date.prototype.getMonth" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (_, month, _, _, _, _, _) = @lib.break_time(t)
            Number(month.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getDate" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (_, _, day, _, _, _, _) = @lib.break_time(t)
            Number(day.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getDay" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            // Day of week: 0 = Sunday, 1 = Monday, ..., 6 = Saturday
            // Jan 1, 1970 was Thursday (day 4)
            let days = (t / 86400000.0).floor().to_int()
            let day_of_week = (days % 7 + 4) % 7
            Number(day_of_week.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getHours" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (_, _, _, hour, _, _, _) = @lib.break_time(t)
            Number(hour.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getMinutes" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (_, _, _, _, minute, _, _) = @lib.break_time(t)
            Number(minute.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getSeconds" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (_, _, _, _, _, second, _) = @lib.break_time(t)
            Number(second.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getMilliseconds" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (_, _, _, _, _, _, milli) = @lib.break_time(t)
            Number(milli.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getUTCFullYear" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (year, _, _, _, _, _, _) = @lib.break_time(t)
            Number(year.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getUTCMonth" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (_, month, _, _, _, _, _) = @lib.break_time(t)
            Number(month.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getUTCDate" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (_, _, day, _, _, _, _) = @lib.break_time(t)
            Number(day.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getUTCDay" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let days = (t / 86400000.0).floor().to_int()
            let day_of_week = (days % 7 + 4) % 7
            Number(day_of_week.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getUTCHours" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (_, _, _, hour, _, _, _) = @lib.break_time(t)
            Number(hour.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getUTCMinutes" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (_, _, _, _, minute, _, _) = @lib.break_time(t)
            Number(minute.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getUTCSeconds" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (_, _, _, _, _, second, _) = @lib.break_time(t)
            Number(second.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getUTCMilliseconds" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Number(js_nan)
          } else {
            let (_, _, _, _, _, _, milli) = @lib.break_time(t)
            Number(milli.to_double())
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.getTimezoneOffset" =>
      // Return 0 for UTC (no timezone offset support currently)
      match self.date_time_value(this_arg) {
        Some(t) => if t.is_nan() { Number(js_nan) } else { Number(0.0) }
        None => self.error_or_undefined()
      }
    "Date.prototype.toString" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            String("Invalid Date")
          } else {
            let (year, month, day, hour, minute, second, _) = @lib.break_time(t)
            let day_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let month_names = [
              "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct",
              "Nov", "Dec",
            ]
            let days = (t / 86400000.0).floor().to_int()
            let day_of_week = (days % 7 + 4) % 7
            let day_name = day_names[day_of_week]
            let month_name = month_names[month]
            let day_str = if day < 10 {
              "0" + day.to_string()
            } else {
              day.to_string()
            }
            let hour_str = if hour < 10 {
              "0" + hour.to_string()
            } else {
              hour.to_string()
            }
            let min_str = if minute < 10 {
              "0" + minute.to_string()
            } else {
              minute.to_string()
            }
            let sec_str = if second < 10 {
              "0" + second.to_string()
            } else {
              second.to_string()
            }
            String(
              day_name +
              " " +
              month_name +
              " " +
              day_str +
              " " +
              year.to_string() +
              " " +
              hour_str +
              ":" +
              min_str +
              ":" +
              sec_str +
              " GMT+0000 (UTC)",
            )
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.toDateString" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            String("Invalid Date")
          } else {
            let (year, month, day, _, _, _, _) = @lib.break_time(t)
            let day_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let month_names = [
              "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct",
              "Nov", "Dec",
            ]
            let days = (t / 86400000.0).floor().to_int()
            let day_of_week = (days % 7 + 4) % 7
            let day_name = day_names[day_of_week]
            let month_name = month_names[month]
            let day_str = if day < 10 {
              "0" + day.to_string()
            } else {
              day.to_string()
            }
            String(
              day_name +
              " " +
              month_name +
              " " +
              day_str +
              " " +
              year.to_string(),
            )
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.toTimeString" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            String("Invalid Date")
          } else {
            let (_, _, _, hour, minute, second, _) = @lib.break_time(t)
            let hour_str = if hour < 10 {
              "0" + hour.to_string()
            } else {
              hour.to_string()
            }
            let min_str = if minute < 10 {
              "0" + minute.to_string()
            } else {
              minute.to_string()
            }
            let sec_str = if second < 10 {
              "0" + second.to_string()
            } else {
              second.to_string()
            }
            String(hour_str + ":" + min_str + ":" + sec_str + " GMT+0000 (UTC)")
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.toISOString" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            self.set_error_kind("RangeError", "Invalid time value")
          } else {
            let (year, month, day, hour, minute, second, milli) = @lib.break_time(
              t,
            )
            fn pad2(n : Int) -> String {
              if n < 10 {
                "0" + n.to_string()
              } else {
                n.to_string()
              }
            }

            fn pad3(n : Int) -> String {
              if n < 10 {
                "00" + n.to_string()
              } else if n < 100 {
                "0" + n.to_string()
              } else {
                n.to_string()
              }
            }

            fn pad4(n : Int) -> String {
              if n < 0 {
                "-" + pad4(-n)
              } else if n < 10 {
                "000" + n.to_string()
              } else if n < 100 {
                "00" + n.to_string()
              } else if n < 1000 {
                "0" + n.to_string()
              } else {
                n.to_string()
              }
            }

            String(
              pad4(year) +
              "-" +
              pad2(month + 1) +
              "-" +
              pad2(day) +
              "T" +
              pad2(hour) +
              ":" +
              pad2(minute) +
              ":" +
              pad2(second) +
              "." +
              pad3(milli) +
              "Z",
            )
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.toUTCString" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            String("Invalid Date")
          } else {
            let (year, month, day, hour, minute, second, _) = @lib.break_time(t)
            let day_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let month_names = [
              "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct",
              "Nov", "Dec",
            ]
            let days = (t / 86400000.0).floor().to_int()
            let day_of_week = (days % 7 + 4) % 7
            let day_name = day_names[day_of_week]
            let month_name = month_names[month]
            let day_str = if day < 10 {
              "0" + day.to_string()
            } else {
              day.to_string()
            }
            let hour_str = if hour < 10 {
              "0" + hour.to_string()
            } else {
              hour.to_string()
            }
            let min_str = if minute < 10 {
              "0" + minute.to_string()
            } else {
              minute.to_string()
            }
            let sec_str = if second < 10 {
              "0" + second.to_string()
            } else {
              second.to_string()
            }
            String(
              day_name +
              ", " +
              day_str +
              " " +
              month_name +
              " " +
              year.to_string() +
              " " +
              hour_str +
              ":" +
              min_str +
              ":" +
              sec_str +
              " GMT",
            )
          }
        None => self.error_or_undefined()
      }
    "Date.prototype.toJSON" =>
      match self.date_time_value(this_arg) {
        Some(t) =>
          if t.is_nan() {
            Null
          } else {
            // toJSON returns the ISO string
            let (year, month, day, hour, minute, second, milli) = @lib.break_time(
              t,
            )
            fn pad2_json(n : Int) -> String {
              if n < 10 {
                "0" + n.to_string()
              } else {
                n.to_string()
              }
            }

            fn pad3_json(n : Int) -> String {
              if n < 10 {
                "00" + n.to_string()
              } else if n < 100 {
                "0" + n.to_string()
              } else {
                n.to_string()
              }
            }

            fn pad4_json(n : Int) -> String {
              if n < 0 {
                "-" + pad4_json(-n)
              } else if n < 10 {
                "000" + n.to_string()
              } else if n < 100 {
                "00" + n.to_string()
              } else if n < 1000 {
                "0" + n.to_string()
              } else {
                n.to_string()
              }
            }

            String(
              pad4_json(year) +
              "-" +
              pad2_json(month + 1) +
              "-" +
              pad2_json(day) +
              "T" +
              pad2_json(hour) +
              ":" +
              pad2_json(minute) +
              ":" +
              pad2_json(second) +
              "." +
              pad3_json(milli) +
              "Z",
            )
          }
        None => self.error_or_undefined()
      }
    "Symbol" => {
      let id = self.symbol_counter
      self.symbol_counter += 1
      // Symbol() vs Symbol("") vs Symbol("desc")
      // - Symbol() or Symbol(undefined): description is undefined -> format: Symbol()#id
      // - Symbol(""): description is "" -> format: Symbol([empty])#id
      // - Symbol("desc"): description is "desc" -> format: Symbol(desc)#id
      if args.length() == 0 || args[0].is_undefined() {
        String("Symbol()#" + id.to_string())
      } else {
        let desc = args[0].to_js_string()
        if desc == "" {
          // Special marker for empty string description
          String("Symbol([empty])#" + id.to_string())
        } else {
          String("Symbol(" + desc + ")#" + id.to_string())
        }
      }
    }
    "Symbol.for" => {
      let key = if args.length() > 0 {
        args[0].to_js_string()
      } else {
        "undefined"
      }
      match self.symbol_registry.get(key) {
        Some(sym) => String(sym)
        None => {
          // Global symbols use format "@@global:key"
          let sym = "@@global:" + key
          self.symbol_registry.set(key, sym)
          String(sym)
        }
      }
    }
    "Symbol.keyFor" => {
      let arg = if args.length() > 0 { args[0] } else { Undefined }
      match arg {
        String(s) =>
          if s.has_prefix("@@global:") {
            // Extract key from "@@global:key"
            String(s[9:].to_string() catch { _ => "" })
          } else if s.has_prefix("Symbol(") || s.has_prefix("@@") {
            // Non-global symbol
            Undefined
          } else {
            self.set_error_kind("TypeError", "Symbol.keyFor requires a symbol")
          }
        _ => self.set_error_kind("TypeError", "Symbol.keyFor requires a symbol")
      }
    }
    "Symbol.prototype.description" => {
      let sym = self.get_symbol_value(this_arg)
      match sym {
        String(s) =>
          if s.has_prefix("@@global:") {
            // Global symbol - description is the key
            String(s[9:].to_string() catch { _ => "" })
          } else if s.has_prefix("@@") {
            // Well-known symbol - description is "Symbol." + name
            String("Symbol." + (s[2:].to_string() catch { _ => "" }))
          } else if s.has_prefix("Symbol([empty])") {
            // Symbol("") - empty string description
            String("")
          } else if s.has_prefix("Symbol(") {
            // Regular symbol - extract description from Symbol(desc)#id or Symbol()#id
            // Find index of ")" in the string
            let mut end_idx = -1
            let chars : Array[Char] = s.iter().collect()
            for i, ch in chars {
              if ch == ')' {
                end_idx = i
                break
              }
            }
            if end_idx > 7 {
              String(s[7:end_idx].to_string() catch { _ => "" })
            } else if end_idx == 7 {
              // Symbol()#id - no description
              Undefined
            } else {
              Undefined
            }
          } else {
            Undefined
          }
        _ =>
          self.set_error_kind(
            "TypeError", "Symbol.prototype.description requires a symbol",
          )
      }
    }
    "Symbol.prototype.toString" => {
      let sym = self.get_symbol_value(this_arg)
      match sym {
        String(s) =>
          if s.has_prefix("@@global:") {
            // Global symbol - format as Symbol(key)
            String("Symbol(" + (s[9:].to_string() catch { _ => "" }) + ")")
          } else if s.has_prefix("@@") {
            // Well-known symbol - format as Symbol(Symbol.name)
            String(
              "Symbol(Symbol." + (s[2:].to_string() catch { _ => "" }) + ")",
            )
          } else if s.has_prefix("Symbol([empty])") {
            // Symbol("") - empty string description -> "Symbol()"
            String("Symbol()")
          } else if s.has_prefix("Symbol(") {
            // Regular symbol - strip #id suffix
            // Find last index of "#" in the string
            let mut hash_idx = -1
            let chars : Array[Char] = s.iter().collect()
            for i, ch in chars {
              if ch == '#' {
                hash_idx = i
              }
            }
            if hash_idx > 0 {
              String(s[:hash_idx].to_string() catch { _ => s })
            } else {
              String(s)
            }
          } else {
            String(s)
          }
        _ =>
          self.set_error_kind(
            "TypeError", "Symbol.prototype.toString requires a symbol",
          )
      }
    }
    "Symbol.prototype.valueOf" => {
      let sym = self.get_symbol_value(this_arg)
      match sym {
        String(s) if s.has_prefix("Symbol(") || s.has_prefix("@@") => sym
        _ =>
          self.set_error_kind(
            "TypeError", "Symbol.prototype.valueOf requires a symbol",
          )
      }
    }
    "Symbol.prototype[@@toPrimitive]" => {
      let sym = self.get_symbol_value(this_arg)
      match sym {
        String(s) if s.has_prefix("Symbol(") || s.has_prefix("@@") => sym
        _ =>
          self.set_error_kind(
            "TypeError", "Symbol.prototype[@@toPrimitive] requires a symbol",
          )
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
    "BigInt" => {
      // BigInt() cannot be called with new - it's not a constructor
      if args.length() == 0 {
        return self.set_error_kind(
          "TypeError", "Cannot convert undefined to a BigInt",
        )
      }
      let arg = args[0]
      match arg {
        BigInt(n) => BigInt(n)
        Number(n) => {
          if n.is_nan() || n.is_inf() || n != n.trunc() {
            return self.set_error_kind(
              "RangeError", "Cannot convert non-integer to BigInt",
            )
          }
          BigInt(BigInt::from_int64(n.to_int64()))
        }
        String(s) => {
          // Try to parse as BigInt
          let n = BigInt::from_string(s)
          // Normalize -0 to 0 (MoonBit BigInt may have -0 != 0 issue)
          if n.to_string() == "0" || n.to_string() == "-0" {
            BigInt(0N)
          } else {
            BigInt(n)
          }
        }
        Bool(b) => BigInt(BigInt::from_int(if b { 1 } else { 0 }))
        _ => self.set_error_kind("TypeError", "Cannot convert to a BigInt")
      }
    }
    "BigInt.prototype.valueOf" =>
      match this_arg {
        BigInt(n) => BigInt(n)
        _ =>
          self.set_error_kind(
            "TypeError", "BigInt.prototype.valueOf requires that 'this' be a BigInt",
          )
      }
    "BigInt.prototype.toString" =>
      match this_arg {
        BigInt(n) => {
          let radix = if args.length() > 0 {
            args[0].to_number().to_int()
          } else {
            10
          }
          if radix < 2 || radix > 36 {
            return self.set_error_kind(
              "RangeError", "toString() radix must be between 2 and 36",
            )
          }
          if radix == 10 {
            String(n.to_string())
          } else if radix == 16 {
            String(n.to_hex())
          } else {
            // For other radixes, fall back to decimal for now
            String(n.to_string())
          }
        }
        _ =>
          self.set_error_kind(
            "TypeError", "BigInt.prototype.toString requires that 'this' be a BigInt",
          )
      }
    "BigInt.prototype.toLocaleString" =>
      match this_arg {
        BigInt(n) => String(n.to_string())
        _ =>
          self.set_error_kind(
            "TypeError", "BigInt.prototype.toLocaleString requires that 'this' be a BigInt",
          )
      }
    "BigInt.asIntN" => {
      if args.length() < 2 {
        return Undefined
      }
      let bits = args[0].to_number().to_int()
      if bits < 0 {
        return self.set_error_kind("RangeError", "Invalid bits value")
      }
      // ToBigInt conversion
      let n : BigInt = match args[1] {
        BigInt(v) => v
        Number(v) => {
          if v.is_nan() || v.is_inf() || v != v.trunc() {
            return self.set_error_kind(
              "RangeError", "Cannot convert non-integer to BigInt",
            )
          }
          BigInt::from_int64(v.to_int64())
        }
        String(s) => BigInt::from_string(s)
        Bool(b) => BigInt::from_int(if b { 1 } else { 0 })
        Null | Undefined =>
          return self.set_error_kind("TypeError", "Cannot convert to a BigInt")
        _ =>
          return self.set_error_kind("TypeError", "Cannot convert to a BigInt")
      }
      if bits == 0 {
        return BigInt(BigInt::from_int(0))
      }
      // Truncate to bits using modular arithmetic
      let max = BigInt::from_int(1) << bits
      let modded = if n >= BigInt::from_int(0) {
        n % max
      } else {
        (n % max + max) % max
      }
      // Sign extend if needed
      let half = max >> 1
      if modded >= half {
        BigInt(modded - max)
      } else {
        BigInt(modded)
      }
    }
    "BigInt.asUintN" => {
      if args.length() < 2 {
        return Undefined
      }
      let bits = args[0].to_number().to_int()
      if bits < 0 {
        return self.set_error_kind("RangeError", "Invalid bits value")
      }
      // ToBigInt conversion
      let n : BigInt = match args[1] {
        BigInt(v) => v
        Number(v) => {
          if v.is_nan() || v.is_inf() || v != v.trunc() {
            return self.set_error_kind(
              "RangeError", "Cannot convert non-integer to BigInt",
            )
          }
          BigInt::from_int64(v.to_int64())
        }
        String(s) => BigInt::from_string(s)
        Bool(b) => BigInt::from_int(if b { 1 } else { 0 })
        Null | Undefined =>
          return self.set_error_kind("TypeError", "Cannot convert to a BigInt")
        _ =>
          return self.set_error_kind("TypeError", "Cannot convert to a BigInt")
      }
      if bits == 0 {
        return BigInt(BigInt::from_int(0))
      }
      let max = BigInt::from_int(1) << bits
      let modded = n % max
      // Ensure non-negative
      if modded < BigInt::from_int(0) {
        BigInt(modded + max)
      } else {
        BigInt(modded)
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
        return self.set_error_kind(
          "TypeError", "RegExp.prototype.exec called on non-RegExp",
        )
      }
      let input = if args.length() > 0 {
        self.to_string_value(args[0])
      } else {
        ""
      }
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
        return self.set_error_kind(
          "TypeError", "RegExp.prototype.compile called on non-RegExp",
        )
      }
      let pattern_val = if args.length() > 0 { args[0] } else { String("") }
      let flags_val = if args.length() > 1 { args[1] } else { Undefined }
      let (pattern, flags) = if is_regexp(pattern_val) && flags_val is Undefined {
        (regexp_source(pattern_val), regexp_flags(pattern_val))
      } else {
        let p = pattern_val.to_js_string()
        let f = if flags_val is Undefined {
          ""
        } else {
          flags_val.to_js_string()
        }
        (p, f)
      }
      match regexp_compile(pattern, flags) {
        None =>
          return self.set_error_kind(
            "SyntaxError", "Invalid regular expression",
          )
        Some(_) => ()
      }
      let norm_flags = normalize_regexp_flags(flags)
      let _ = js_set_prop(this_arg, "source", String(pattern))
      let _ = js_set_prop(this_arg, "flags", String(norm_flags))
      let _ = js_set_prop(
        this_arg,
        "global",
        Bool(regexp_has_global(norm_flags)),
      )
      let _ = js_set_prop(this_arg, "lastIndex", Number(0.0))
      this_arg
    }
    "RegExp.prototype.test" => {
      if not(is_regexp(this_arg)) {
        return self.set_error_kind(
          "TypeError", "RegExp.prototype.test called on non-RegExp",
        )
      }
      let input = if args.length() > 0 {
        self.to_string_value(args[0])
      } else {
        ""
      }
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
    "Reflect.construct" =>
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
              Native("Function") =>
                self.call_native("Function", Undefined, call_args)
              _ => self.construct_with(target, new_target, call_args)
            }
          _ => Undefined
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
      } else if self.is_proxy(receiver) {
        let desc = self.proxy_get_own_property_descriptor(receiver, key)
        match self.peek_error() {
          Some(_) => return Bool(false)
          None => ()
        }
        let new_desc = match desc {
          Undefined => self.make_data_descriptor(value, true, true, true)
          _ => {
            let has_enum = self.has_own_prop(desc, "enumerable")
            let enumerable = if has_enum {
              self.get_prop_value(desc, "enumerable").to_boolean()
            } else {
              true
            }
            let has_config = self.has_own_prop(desc, "configurable")
            let configurable = if has_config {
              self.get_prop_value(desc, "configurable").to_boolean()
            } else {
              true
            }
            let has_value = self.has_own_prop(desc, "value")
            if has_value {
              let _ = self.get_prop_value(desc, "value")

            }
            let has_writable = self.has_own_prop(desc, "writable")
            let writable = if has_writable {
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
    "Reflect.has" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let key_val = if args.length() > 1 { args[1] } else { Undefined }
      let key = self.normalize_prop_key(self.to_property_key(key_val))
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
      let key = self.normalize_prop_key(self.to_property_key(key_val))
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
          Object(map) =>
            match map.prototype {
              Some(p) => p
              None => Null
            }
          Function(closure) =>
            match closure.object_proto {
              Some(p) => p
              None => Null
            }
          Array(arr) =>
            match arr.prototype {
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
    // test262 harness functions
    "print" => {
      let parts : Array[String] = []
      for arg in args {
        // Strip symbol IDs for display
        parts.push(strip_symbol_id(arg.to_js_string()))
      }
      println(parts.join(" "))
      Undefined
    }
    "gc" => {
      // Run VM-level garbage collection
      // Collect roots from global env and current scope
      let roots : Array[JSValue] = []
      // Add global object as root
      let global_obj = self.global_env.get("globalThis")
      roots.push(global_obj)
      // Run GC
      let collected = vm_gc_collect(roots, Some(self.global_env))
      // Clean up weak collections
      vm_gc_cleanup_weak_refs(collected)
      vm_gc_cleanup_weak_maps(collected)
      vm_gc_cleanup_weak_sets(collected)
      // Get and run finalization callbacks
      let callbacks = vm_gc_get_finalization_callbacks(collected)
      for pair in callbacks {
        let (callback, held_value) = pair
        let _ = self.call_function(callback, Undefined, [held_value])

      }
      // Return number of collected objects
      Number(collected.length().to_double())
    }
    "$enterScope" => {
      // Enter a new Perceus scope
      let scope_id = perceus_enter_scope()
      Number(scope_id.to_double())
    }
    "$exitScope" => {
      // Exit current scope and cleanup unreachable objects
      let cleaned = perceus_exit_scope_with_cleanup()
      Number(cleaned.to_double())
    }
    "$markEscaped" => {
      // Mark an object as escaped from current scope
      let obj = if args.length() > 0 { args[0] } else { Undefined }
      perceus_mark_value_escaped(obj)
      obj
    }
    "escape" => {
      let input = if args.length() > 0 {
        self.to_string_value(args[0])
      } else {
        "undefined"
      }
      match self.peek_error() {
        Some(err) => err
        None => String(@lib.escape_string(input))
      }
    }
    "unescape" => {
      let input = if args.length() > 0 {
        self.to_string_value(args[0])
      } else {
        "undefined"
      }
      match self.peek_error() {
        Some(err) => err
        None => String(@lib.unescape_string(input))
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
        if r == 0 {
          10
        } else {
          r
        }
      } else {
        10
      }
      // Handle hex prefix
      let trimmed = input_str.trim_start().to_string()
      let (actual_str, actual_radix) : (String, Int) = if radix == 16 ||
        radix == 0 {
        if trimmed.has_prefix("0x") || trimmed.has_prefix("0X") {
          ((trimmed[2:] catch { _ => trimmed }).to_string(), 16)
        } else {
          (trimmed, if radix == 0 { 10 } else { radix })
        }
      } else {
        (trimmed, radix)
      }
      if actual_radix < 2 || actual_radix > 36 {
        Number(0.0 / 0.0) // NaN
      } else {
        let result : Int = @strconv.parse_int(actual_str, base=actual_radix) catch {
          _ =>
            // Try without base if it fails
            @strconv.parse_int(actual_str) catch {
              _ => 0
            }
        }
        Number(
          // If parsing fails completely, return NaN
          // For simplicity, just return the parsed value or 0
          result.to_double(),
        )
      }
    }
    "parseFloat" => {
      let input_str = if args.length() > 0 {
        args[0].to_js_string()
      } else {
        "NaN"
      }
      let trimmed = input_str.trim_start().to_string()
      let result : Double = @strconv.parse_double(trimmed) catch {
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
          if args.length() > 2 {
            Some(args[2].to_js_string())
          } else {
            None
          },
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
          if args.length() > 2 {
            Some(args[2].to_js_string())
          } else {
            None
          },
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
          if args.length() > 2 {
            Some(args[2].to_js_string())
          } else {
            None
          },
        )
        match result {
          Success => Undefined
          Failure(msg) => self.set_error(msg)
        }
      } else {
        Undefined
      }
    "compareArray" =>
      if args.length() >= 2 {
        let actual = args[0]
        let expected = args[1]
        let result = compare_array(actual, expected, None)
        match result {
          Success => Bool(true)
          Failure(_) => Bool(false)
        }
      } else {
        Bool(false)
      }
    "assert.throws" => {
      if args.length() < 2 {
        return self.set_error("assert.throws requires 2 args")
      }
      let expected = args[0]
      let thunk = args[1]
      match thunk {
        Function(_) => ()
        _ =>
          return self.set_error_kind(
            "TypeError", "assert.throws requires a function",
          )
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
    "$DONOTEVALUATE" =>
      // This function should never be called in a passing test
      self.set_error("$DONOTEVALUATE was called")
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
      let msg = if args.length() > 0 {
        args[0].to_js_string()
      } else {
        "Test262Error"
      }
      self.set_error_kind("Test262Error", msg)
    }
    "$262.evalScript" =>
      if args.length() > 0 {
        let code = args[0].to_js_string()
        self.eval_script_source(code)
      } else {
        Undefined
      }
    "$262.detachArrayBuffer" =>
      if args.length() > 0 {
        match get_arraybuffer_data(args[0]) {
          Some(buf) => {
            detach_bytebuffer(buf.id)
            Undefined
          }
          None => self.set_error_kind("TypeError", "Expected ArrayBuffer")
        }
      } else {
        self.set_error_kind("TypeError", "Expected ArrayBuffer")
      }
    "$262.createRealm" => {
      let realm = self.new_object()
      let other = JSInterpreter::new()
      let other_global = other.global_env.get("globalThis")
      let _ = js_set_prop(realm, "global", other_global)
      let current_array_proto = js_get_prop(
        self.global_env.get("Array"),
        "prototype",
      )
      match current_array_proto {
        Object(_) | Function(_) | Array(_) =>
          js_set_default_array_proto(current_array_proto)
        _ => ()
      }
      realm
    }
    // testTypedArray.js harness functions
    "testWithTypedArrayConstructors" => {
      if args.length() == 0 {
        return Undefined
      }
      let callback = args[0]
      let constructors = if args.length() > 1 && not(args[1].is_undefined()) {
        args[1]
      } else {
        self.global_env.get("typedArrayConstructors")
      }
      match constructors {
        Array(arr) =>
          for i = 0; i < arr.items.length(); i = i + 1 {
            let ctor = arr.items[i]
            let result = self.call_function(callback, Undefined, [ctor])
            match self.peek_error() {
              Some(e) => {
                // Append constructor name to error message
                let ctor_name = js_get_prop(ctor, "name").to_js_string()
                let msg = js_get_prop(e, "message").to_js_string()
                let new_msg = msg + " (Testing with " + ctor_name + ".)"
                let _ = js_set_prop(e, "message", String(new_msg))
                return result
              }
              None => ()
            }
          }
        _ => ()
      }
      Undefined
    }
    "testWithAtomicsFriendlyTypedArrayConstructors" => {
      if args.length() == 0 {
        return Undefined
      }
      let callback = args[0]
      // Atomics-friendly: Int32Array, Int16Array, Int8Array, Uint32Array, Uint16Array, Uint8Array
      let atomics_ctors = [
        self.global_env.get("Int32Array"),
        self.global_env.get("Int16Array"),
        self.global_env.get("Int8Array"),
        self.global_env.get("Uint32Array"),
        self.global_env.get("Uint16Array"),
        self.global_env.get("Uint8Array"),
      ]
      for ctor in atomics_ctors {
        let result = self.call_function(callback, Undefined, [ctor])
        match self.peek_error() {
          Some(e) => {
            let ctor_name = js_get_prop(ctor, "name").to_js_string()
            let msg = js_get_prop(e, "message").to_js_string()
            let new_msg = msg + " (Testing with " + ctor_name + ".)"
            let _ = js_set_prop(e, "message", String(new_msg))
            return result
          }
          None => ()
        }
      }
      Undefined
    }
    "testWithNonAtomicsFriendlyTypedArrayConstructors" => {
      if args.length() == 0 {
        return Undefined
      }
      let callback = args[0]
      // Non-atomics-friendly: Float64Array, Float32Array, Uint8ClampedArray
      let non_atomics_ctors = [
        self.global_env.get("Float64Array"),
        self.global_env.get("Float32Array"),
        self.global_env.get("Uint8ClampedArray"),
      ]
      for ctor in non_atomics_ctors {
        let result = self.call_function(callback, Undefined, [ctor])
        match self.peek_error() {
          Some(e) => {
            let ctor_name = js_get_prop(ctor, "name").to_js_string()
            let msg = js_get_prop(e, "message").to_js_string()
            let new_msg = msg + " (Testing with " + ctor_name + ".)"
            let _ = js_set_prop(e, "message", String(new_msg))
            return result
          }
          None => ()
        }
      }
      Undefined
    }
    "testWithBigIntTypedArrayConstructors" => {
      if args.length() == 0 {
        return Undefined
      }
      let callback = args[0]
      // BigInt TypedArrays: BigInt64Array, BigUint64Array
      let bigint_ctors = [
        self.global_env.get("BigInt64Array"),
        self.global_env.get("BigUint64Array"),
      ]
      for ctor in bigint_ctors {
        let result = self.call_function(callback, Undefined, [ctor])
        match self.peek_error() {
          Some(e) => {
            let ctor_name = js_get_prop(ctor, "name").to_js_string()
            let msg = js_get_prop(e, "message").to_js_string()
            let new_msg = msg + " (Testing with " + ctor_name + ".)"
            let _ = js_set_prop(e, "message", String(new_msg))
            return result
          }
          None => ()
        }
      }
      Undefined
    }
    "$DETACHBUFFER" =>
      if args.length() > 0 {
        match get_arraybuffer_data(args[0]) {
          Some(buf) => {
            detach_bytebuffer(buf.id)
            Undefined
          }
          None => self.set_error_kind("TypeError", "Expected ArrayBuffer")
        }
      } else {
        self.set_error_kind("TypeError", "Expected ArrayBuffer")
      }
    // Map constructor
    "Map" => {
      let map_obj = self.new_object()
      let map_proto = js_get_prop(self.global_env.get("Map"), "prototype")
      let _ = js_set_prop(map_obj, "__proto__", map_proto)
      let _ = js_set_prop(map_obj, "__class", String("Map"))
      let entries : Array[JSValue] = []
      let _ = js_set_prop(map_obj, "__map_entries", js_array_from(entries))
      // Initialize from iterable if provided
      if args.length() > 0 && !args[0].is_nullish() {
        let iterable = args[0]
        let iter_fn = js_get_prop(iterable, "@@iterator")
        match iter_fn {
          Function(_) => {
            let iter = self.call_function(iter_fn, iterable, [])
            let next_method = js_get_prop(iter, "next")
            while true {
              let next_result = self.call_function(next_method, iter, [])
              match js_get_prop(next_result, "done") {
                Bool(true) => break
                _ => {
                  let val = js_get_prop(next_result, "value")
                  // Each item should be [key, value]
                  let key = js_get_prop(val, "0")
                  let value = js_get_prop(val, "1")
                  let _ = self.map_set_entry(map_obj, key, value)

                }
              }
            }
          }
          _ => ()
        }
      }
      map_obj
    }
    // Map.prototype methods
    "Map.prototype.get" => {
      let key = if args.length() > 0 { args[0] } else { Undefined }
      self.map_get_entry(this_arg, key)
    }
    "Map.prototype.set" => {
      let key = if args.length() > 0 { args[0] } else { Undefined }
      let value = if args.length() > 1 { args[1] } else { Undefined }
      let _ = self.map_set_entry(this_arg, key, value)
      this_arg
    }
    "Map.prototype.has" => {
      let key = if args.length() > 0 { args[0] } else { Undefined }
      Bool(self.map_has_entry(this_arg, key))
    }
    "Map.prototype.delete" => {
      let key = if args.length() > 0 { args[0] } else { Undefined }
      Bool(self.map_delete_entry(this_arg, key))
    }
    "Map.prototype.clear" => {
      let entries : Array[JSValue] = []
      let _ = js_set_prop(this_arg, "__map_entries", js_array_from(entries))
      Undefined
    }
    "Map.prototype.keys" => self.new_map_key_iterator(this_arg)
    "Map.prototype.values" => self.new_map_value_iterator(this_arg)
    "Map.prototype.entries" => self.new_map_entry_iterator(this_arg)
    "Map.prototype.forEach" => {
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      let this_for_callback = if args.length() > 1 {
        args[1]
      } else {
        Undefined
      }
      match js_get_prop(this_arg, "__map_entries") {
        JSValue::Array(arr) =>
          for i = 0; i < arr.length; i = i + 1 {
            match arr.items[i] {
              JSValue::Array(pair) if pair.length >= 2 => {
                let key = pair.items[0]
                let value = pair.items[1]
                let _ = self.call_function(callback, this_for_callback, [
                  value, key, this_arg,
                ])

              }
              _ => ()
            }
          }
        _ => ()
      }
      Undefined
    }
    // Set constructor
    "Set" => {
      let set_obj = self.new_object()
      let set_proto = js_get_prop(self.global_env.get("Set"), "prototype")
      let _ = js_set_prop(set_obj, "__proto__", set_proto)
      let _ = js_set_prop(set_obj, "__class", String("Set"))
      let entries : Array[JSValue] = []
      let _ = js_set_prop(set_obj, "__set_entries", js_array_from(entries))
      // Initialize from iterable if provided
      if args.length() > 0 && !args[0].is_nullish() {
        let iterable = args[0]
        let iter_fn = js_get_prop(iterable, "@@iterator")
        match iter_fn {
          Function(_) => {
            let iter = self.call_function(iter_fn, iterable, [])
            let next_method = js_get_prop(iter, "next")
            while true {
              let next_result = self.call_function(next_method, iter, [])
              match js_get_prop(next_result, "done") {
                Bool(true) => break
                _ => {
                  let val = js_get_prop(next_result, "value")
                  let _ = self.set_add_entry(set_obj, val)

                }
              }
            }
          }
          _ => ()
        }
      }
      set_obj
    }
    // Set.prototype methods
    "Set.prototype.add" => {
      let value = if args.length() > 0 { args[0] } else { Undefined }
      let _ = self.set_add_entry(this_arg, value)
      this_arg
    }
    "Set.prototype.has" => {
      let value = if args.length() > 0 { args[0] } else { Undefined }
      Bool(self.set_has_entry(this_arg, value))
    }
    "Set.prototype.delete" => {
      let value = if args.length() > 0 { args[0] } else { Undefined }
      Bool(self.set_delete_entry(this_arg, value))
    }
    "Set.prototype.clear" => {
      let entries : Array[JSValue] = []
      let _ = js_set_prop(this_arg, "__set_entries", js_array_from(entries))
      Undefined
    }
    "Set.prototype.values" => self.new_set_value_iterator(this_arg)
    "Set.prototype.entries" => self.new_set_entry_iterator(this_arg)
    "Set.prototype.forEach" => {
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      let this_for_callback = if args.length() > 1 {
        args[1]
      } else {
        Undefined
      }
      match js_get_prop(this_arg, "__set_entries") {
        JSValue::Array(arr) =>
          for i = 0; i < arr.length; i = i + 1 {
            let value = arr.items[i]
            let _ = self.call_function(callback, this_for_callback, [
              value, value, this_arg,
            ])

          }
        _ => ()
      }
      Undefined
    }
    // WeakMap
    "WeakMap" => {
      let wm_obj = self.new_object()
      let wm_proto = js_get_prop(self.global_env.get("WeakMap"), "prototype")
      let _ = js_set_prop(wm_obj, "__proto__", wm_proto)
      let _ = js_set_prop(wm_obj, "__class", String("WeakMap"))
      let entries : Array[JSValue] = []
      let _ = js_set_prop(wm_obj, "__weakmap_entries", js_array_from(entries))
      // Register with VM GC
      vm_gc_register_weak_map(wm_obj)
      // Initialize from iterable if provided
      if args.length() > 0 && not(args[0].is_nullish()) {
        let iterable = args[0]
        let iter_fn = js_get_prop(iterable, "@@iterator")
        match iter_fn {
          Function(_) => {
            let iter = self.call_function(iter_fn, iterable, [])
            let next_method = js_get_prop(iter, "next")
            while true {
              let next_result = self.call_function(next_method, iter, [])
              match js_get_prop(next_result, "done") {
                Bool(true) => break
                _ => {
                  let val = js_get_prop(next_result, "value")
                  let key = js_get_prop(val, "0")
                  let value = js_get_prop(val, "1")
                  // Register key with VM GC
                  vm_gc_register_object(key)
                  let _ = self.weakmap_set_entry(wm_obj, key, value)

                }
              }
            }
          }
          _ => ()
        }
      }
      wm_obj
    }
    "WeakMap.prototype.get" => {
      let key = if args.length() > 0 { args[0] } else { Undefined }
      self.weakmap_get_entry(this_arg, key)
    }
    "WeakMap.prototype.set" => {
      let key = if args.length() > 0 { args[0] } else { Undefined }
      let value = if args.length() > 1 { args[1] } else { Undefined }
      // Register key with VM GC and Perceus scope tracking
      vm_gc_register_object(key)
      perceus_track_object(key)
      self.weakmap_set_entry(this_arg, key, value)
    }
    "WeakMap.prototype.has" => {
      let key = if args.length() > 0 { args[0] } else { Undefined }
      Bool(self.weakmap_has_entry(this_arg, key))
    }
    "WeakMap.prototype.delete" => {
      let key = if args.length() > 0 { args[0] } else { Undefined }
      Bool(self.weakmap_delete_entry(this_arg, key))
    }
    // WeakSet
    "WeakSet" => {
      let ws_obj = self.new_object()
      let ws_proto = js_get_prop(self.global_env.get("WeakSet"), "prototype")
      let _ = js_set_prop(ws_obj, "__proto__", ws_proto)
      let _ = js_set_prop(ws_obj, "__class", String("WeakSet"))
      let entries : Array[JSValue] = []
      let _ = js_set_prop(ws_obj, "__weakset_entries", js_array_from(entries))
      // Register with VM GC
      vm_gc_register_weak_set(ws_obj)
      // Initialize from iterable if provided
      if args.length() > 0 && not(args[0].is_nullish()) {
        let iterable = args[0]
        let iter_fn = js_get_prop(iterable, "@@iterator")
        match iter_fn {
          Function(_) => {
            let iter = self.call_function(iter_fn, iterable, [])
            let next_method = js_get_prop(iter, "next")
            while true {
              let next_result = self.call_function(next_method, iter, [])
              match js_get_prop(next_result, "done") {
                Bool(true) => break
                _ => {
                  let val = js_get_prop(next_result, "value")
                  // Register value with VM GC
                  vm_gc_register_object(val)
                  let _ = self.weakset_add_entry(ws_obj, val)

                }
              }
            }
          }
          _ => ()
        }
      }
      ws_obj
    }
    "WeakSet.prototype.add" => {
      let value = if args.length() > 0 { args[0] } else { Undefined }
      // Register value with VM GC and Perceus scope tracking
      vm_gc_register_object(value)
      perceus_track_object(value)
      self.weakset_add_entry(this_arg, value)
    }
    "WeakSet.prototype.has" => {
      let value = if args.length() > 0 { args[0] } else { Undefined }
      Bool(self.weakset_has_entry(this_arg, value))
    }
    "WeakSet.prototype.delete" => {
      let value = if args.length() > 0 { args[0] } else { Undefined }
      Bool(self.weakset_delete_entry(this_arg, value))
    }
    // WeakRef
    "WeakRef" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let wr_obj = self.new_object()
      let wr_proto = js_get_prop(self.global_env.get("WeakRef"), "prototype")
      let _ = js_set_prop(wr_obj, "__proto__", wr_proto)
      let _ = js_set_prop(wr_obj, "__class", String("WeakRef"))
      let _ = js_set_prop(wr_obj, "__weakref_target", target)
      // Register target with VM GC
      vm_gc_register_object(target)
      vm_gc_register_weak_ref(wr_obj)
      wr_obj
    }
    "WeakRef.prototype.deref" => js_get_prop(this_arg, "__weakref_target")
    // FinalizationRegistry
    "FinalizationRegistry" => {
      let callback = if args.length() > 0 { args[0] } else { Undefined }
      let fr_obj = self.new_object()
      let fr_proto = js_get_prop(
        self.global_env.get("FinalizationRegistry"),
        "prototype",
      )
      let _ = js_set_prop(fr_obj, "__proto__", fr_proto)
      let _ = js_set_prop(fr_obj, "__class", String("FinalizationRegistry"))
      let _ = js_set_prop(fr_obj, "__fr_callback", callback)
      let registrations : Array[JSValue] = []
      let _ = js_set_prop(
        fr_obj,
        "__fr_registrations",
        js_array_from(registrations),
      )
      // Register with VM GC
      vm_gc_register_finalization_registry(fr_obj)
      fr_obj
    }
    "FinalizationRegistry.prototype.register" => {
      let target = if args.length() > 0 { args[0] } else { Undefined }
      let held_value = if args.length() > 1 { args[1] } else { Undefined }
      // Register target with VM GC
      vm_gc_register_object(target)
      let unregister_token = if args.length() > 2 { args[2] } else { Undefined }
      self.fr_register(this_arg, target, held_value, unregister_token)
      Undefined
    }
    "FinalizationRegistry.prototype.unregister" => {
      let unregister_token = if args.length() > 0 { args[0] } else { Undefined }
      Bool(self.fr_unregister(this_arg, unregister_token))
    }
    "FinalizationRegistry.prototype.cleanupSome" => {
      // Run VM-level garbage collection and call this registry's callbacks
      let roots : Array[JSValue] = []
      let global_obj = self.global_env.get("globalThis")
      roots.push(global_obj)
      let collected = vm_gc_collect(roots, Some(self.global_env))
      // Clean up weak collections
      vm_gc_cleanup_weak_refs(collected)
      vm_gc_cleanup_weak_maps(collected)
      vm_gc_cleanup_weak_sets(collected)
      // Get and run finalization callbacks (only for this registry)
      let callback = js_get_prop(this_arg, "__fr_callback")
      match js_get_prop(this_arg, "__fr_registrations") {
        JSValue::Array(arr) => {
          let mut i = 0
          while i < arr.length {
            match arr.items[i] {
              JSValue::Array(entry) if entry.length >= 3 =>
                match entry.items[0] {
                  Number(target_id) if collected.contains(target_id.to_int()) => {
                    let held_value = entry.items[1]
                    let _ = self.call_function(callback, Undefined, [held_value])
                    let _ = arr.items.remove(i)
                    arr.length = arr.length - 1
                    continue
                  }
                  _ => ()
                }
              _ => ()
            }
            i = i + 1
          }
        }
        _ => ()
      }
      Undefined
    }
    // ArrayBuffer constructor
    "ArrayBuffer" => {
      let length_f = if args.length() > 0 {
        let n = args[0].to_number()
        if n.is_nan() {
          0.0
        } else {
          n
        }
      } else {
        0.0
      }
      // Check for excessively large values (>= 2^53) or negative values
      if length_f >= 9007199254740992.0 || length_f < 0.0 {
        return self.set_error_kind("RangeError", "Invalid array buffer length")
      }
      let length = length_f.to_int()
      // Practical limit to prevent memory issues
      if length > 1073741824 { // 1GB limit
        return self.set_error_kind("RangeError", "Invalid array buffer length")
      }
      let buf = js_new_bytebuffer(length)
      let buf_id = store_bytebuffer(buf)
      let ab_obj = self.new_object()
      let ab_proto = js_get_prop(
        self.global_env.get("ArrayBuffer"),
        "prototype",
      )
      let _ = js_set_prop(ab_obj, "__proto__", ab_proto)
      let _ = js_set_prop(ab_obj, "__class", String("ArrayBuffer"))
      let _ = js_set_prop(ab_obj, "__ab_id", Number(buf_id.to_double()))
      ab_obj
    }
    // ArrayBuffer.prototype getters
    "ArrayBuffer.prototype.byteLength" =>
      match get_arraybuffer_data(this_arg) {
        Some(buf) => {
          if buf.detached {
            return self.set_error_kind(
              "TypeError", "Cannot read byteLength of detached ArrayBuffer",
            )
          }
          Number(buf.data.length().to_double())
        }
        None =>
          self.set_error_kind(
            "TypeError", "ArrayBuffer.prototype.byteLength requires that 'this' be an ArrayBuffer",
          )
      }
    "ArrayBuffer.prototype.maxByteLength" =>
      match get_arraybuffer_data(this_arg) {
        Some(buf) => {
          if buf.detached {
            return self.set_error_kind(
              "TypeError", "Cannot read maxByteLength of detached ArrayBuffer",
            )
          }
          // Non-resizable ArrayBuffer: maxByteLength equals byteLength
          Number(buf.data.length().to_double())
        }
        None =>
          self.set_error_kind(
            "TypeError", "ArrayBuffer.prototype.maxByteLength requires that 'this' be an ArrayBuffer",
          )
      }
    "ArrayBuffer.prototype.resizable" =>
      match get_arraybuffer_data(this_arg) {
        Some(_) => Bool(false) // We don't support resizable ArrayBuffers yet
        None =>
          self.set_error_kind(
            "TypeError", "ArrayBuffer.prototype.resizable requires that 'this' be an ArrayBuffer",
          )
      }
    "ArrayBuffer.prototype.detached" =>
      match get_arraybuffer_data(this_arg) {
        Some(buf) => Bool(buf.detached)
        None =>
          self.set_error_kind(
            "TypeError", "ArrayBuffer.prototype.detached requires that 'this' be an ArrayBuffer",
          )
      }
    "ArrayBuffer.prototype.resize" =>
      // We don't support resizable ArrayBuffers yet
      self.set_error_kind("TypeError", "ArrayBuffer is not resizable")
    "ArrayBuffer.prototype.transfer" =>
      match get_arraybuffer_data(this_arg) {
        Some(buf) => {
          if buf.detached {
            return self.set_error_kind(
              "TypeError", "Cannot transfer a detached ArrayBuffer",
            )
          }
          let new_length_f = if args.length() > 0 && not(args[0].is_undefined()) {
            let n = args[0].to_number()
            if n.is_nan() {
              0.0
            } else {
              n
            }
          } else {
            buf.data.length().to_double()
          }
          // Check for excessively large values (>= 2^53)
          if new_length_f >= 9007199254740992.0 || new_length_f < 0.0 {
            return self.set_error_kind(
              "RangeError", "Invalid array buffer length",
            )
          }
          let new_length = new_length_f.to_int()
          // Practical limit to prevent memory issues
          if new_length > 1073741824 { // 1GB limit
            return self.set_error_kind(
              "RangeError", "Invalid array buffer length",
            )
          }
          // Create new buffer with new length
          let new_buf = js_new_bytebuffer(new_length)
          let copy_len = if new_length < buf.data.length() {
            new_length
          } else {
            buf.data.length()
          }
          for i = 0; i < copy_len; i = i + 1 {
            new_buf.data[i] = buf.data[i]
          }
          // Detach the original buffer
          detach_bytebuffer(buf.id)
          let new_buf_id = store_bytebuffer(new_buf)
          let new_ab = self.new_object()
          let ab_proto = js_get_prop(
            self.global_env.get("ArrayBuffer"),
            "prototype",
          )
          let _ = js_set_prop(new_ab, "__proto__", ab_proto)
          let _ = js_set_prop(new_ab, "__class", String("ArrayBuffer"))
          let _ = js_set_prop(new_ab, "__ab_id", Number(new_buf_id.to_double()))
          new_ab
        }
        None =>
          self.set_error_kind(
            "TypeError", "ArrayBuffer.prototype.transfer requires that 'this' be an ArrayBuffer",
          )
      }
    "ArrayBuffer.prototype.transferToFixedLength" =>
      match get_arraybuffer_data(this_arg) {
        Some(buf) => {
          if buf.detached {
            return self.set_error_kind(
              "TypeError", "Cannot transfer a detached ArrayBuffer",
            )
          }
          let new_length_f = if args.length() > 0 && not(args[0].is_undefined()) {
            let n = args[0].to_number()
            if n.is_nan() {
              0.0
            } else {
              n
            }
          } else {
            buf.data.length().to_double()
          }
          // Check for excessively large values (>= 2^53)
          if new_length_f >= 9007199254740992.0 || new_length_f < 0.0 {
            return self.set_error_kind(
              "RangeError", "Invalid array buffer length",
            )
          }
          let new_length = new_length_f.to_int()
          // Practical limit to prevent memory issues
          if new_length > 1073741824 { // 1GB limit
            return self.set_error_kind(
              "RangeError", "Invalid array buffer length",
            )
          }
          // Create new buffer with new length
          let new_buf = js_new_bytebuffer(new_length)
          let copy_len = if new_length < buf.data.length() {
            new_length
          } else {
            buf.data.length()
          }
          for i = 0; i < copy_len; i = i + 1 {
            new_buf.data[i] = buf.data[i]
          }
          // Detach the original buffer
          detach_bytebuffer(buf.id)
          let new_buf_id = store_bytebuffer(new_buf)
          let new_ab = self.new_object()
          let ab_proto = js_get_prop(
            self.global_env.get("ArrayBuffer"),
            "prototype",
          )
          let _ = js_set_prop(new_ab, "__proto__", ab_proto)
          let _ = js_set_prop(new_ab, "__class", String("ArrayBuffer"))
          let _ = js_set_prop(new_ab, "__ab_id", Number(new_buf_id.to_double()))
          new_ab
        }
        None =>
          self.set_error_kind(
            "TypeError", "ArrayBuffer.prototype.transferToFixedLength requires that 'this' be an ArrayBuffer",
          )
      }
    "ArrayBuffer.prototype.slice" =>
      match get_arraybuffer_data(this_arg) {
        Some(buf) => {
          if buf.detached {
            return self.set_error_kind("TypeError", "ArrayBuffer is detached")
          }
          let byte_length = buf.data.length()
          let start_arg = if args.length() > 0 {
            args[0].to_number().to_int()
          } else {
            0
          }
          let end_arg = if args.length() > 1 && not(args[1].is_undefined()) {
            args[1].to_number().to_int()
          } else {
            byte_length
          }
          // Resolve relative indices
          let start = if start_arg < 0 {
            let s = byte_length + start_arg
            if s < 0 {
              0
            } else {
              s
            }
          } else if start_arg > byte_length {
            byte_length
          } else {
            start_arg
          }
          let end = if end_arg < 0 {
            let e = byte_length + end_arg
            if e < 0 {
              0
            } else {
              e
            }
          } else if end_arg > byte_length {
            byte_length
          } else {
            end_arg
          }
          let new_len = if end > start { end - start } else { 0 }
          // Create new ArrayBuffer
          let new_buf = js_new_bytebuffer(new_len)
          for i = 0; i < new_len; i = i + 1 {
            new_buf.data[i] = buf.data[start + i]
          }
          let new_buf_id = store_bytebuffer(new_buf)
          let new_ab = self.new_object()
          let ab_proto = js_get_prop(
            self.global_env.get("ArrayBuffer"),
            "prototype",
          )
          let _ = js_set_prop(new_ab, "__proto__", ab_proto)
          let _ = js_set_prop(new_ab, "__class", String("ArrayBuffer"))
          let _ = js_set_prop(new_ab, "__ab_id", Number(new_buf_id.to_double()))
          new_ab
        }
        None => self.set_error_kind("TypeError", "Not an ArrayBuffer")
      }
    "ArrayBuffer.isView" => {
      let arg = if args.length() > 0 { args[0] } else { Undefined }
      Bool(is_typedarray(arg) || is_dataview(arg))
    }
    // TypedArray constructors
    "Int8Array" => self.create_typedarray(Int8Array, args)
    "Uint8Array" => self.create_typedarray(Uint8Array, args)
    "Uint8ClampedArray" => self.create_typedarray(Uint8ClampedArray, args)
    "Int16Array" => self.create_typedarray(Int16Array, args)
    "Uint16Array" => self.create_typedarray(Uint16Array, args)
    "Int32Array" => self.create_typedarray(Int32Array, args)
    "Uint32Array" => self.create_typedarray(Uint32Array, args)
    "Float32Array" => self.create_typedarray(Float32Array, args)
    "Float64Array" => self.create_typedarray(Float64Array, args)
    "BigInt64Array" => self.create_typedarray(BigInt64Array, args)
    "BigUint64Array" => self.create_typedarray(BigUint64Array, args)
    // TypedArray.prototype methods
    "TypedArray.prototype.set" => self.typedarray_set(this_arg, args)
    "TypedArray.prototype.subarray" => self.typedarray_subarray(this_arg, args)
    "TypedArray.prototype.slice" => self.typedarray_slice(this_arg, args)
    "TypedArray.prototype.fill" => self.typedarray_fill(this_arg, args)
    "TypedArray.prototype.copyWithin" =>
      self.typedarray_copy_within(this_arg, args)
    "TypedArray.prototype.forEach" => self.typedarray_foreach(this_arg, args)
    "TypedArray.prototype.map" => self.typedarray_map(this_arg, args)
    "TypedArray.prototype.filter" => self.typedarray_filter(this_arg, args)
    "TypedArray.prototype.reduce" => self.typedarray_reduce(this_arg, args)
    "TypedArray.prototype.reduceRight" =>
      self.typedarray_reduce_right(this_arg, args)
    "TypedArray.prototype.every" => self.typedarray_every(this_arg, args)
    "TypedArray.prototype.some" => self.typedarray_some(this_arg, args)
    "TypedArray.prototype.find" => self.typedarray_find(this_arg, args)
    "TypedArray.prototype.findIndex" =>
      self.typedarray_find_index(this_arg, args)
    "TypedArray.prototype.indexOf" => self.typedarray_index_of(this_arg, args)
    "TypedArray.prototype.lastIndexOf" =>
      self.typedarray_last_index_of(this_arg, args)
    "TypedArray.prototype.includes" => self.typedarray_includes(this_arg, args)
    "TypedArray.prototype.join" => self.typedarray_join(this_arg, args)
    "TypedArray.prototype.reverse" => self.typedarray_reverse(this_arg, args)
    "TypedArray.prototype.sort" => self.typedarray_sort(this_arg, args)
    "TypedArray.prototype.at" => self.typedarray_at(this_arg, args)
    "TypedArray.prototype.toLocaleString" =>
      self.typedarray_to_locale_string(this_arg, args)
    "TypedArray.prototype.findLast" => self.typedarray_find_last(this_arg, args)
    "TypedArray.prototype.findLastIndex" =>
      self.typedarray_find_last_index(this_arg, args)
    "TypedArray.prototype.with" => self.typedarray_with(this_arg, args)
    "TypedArray.prototype.toReversed" =>
      self.typedarray_to_reversed(this_arg, args)
    "TypedArray.prototype.toSorted" => self.typedarray_to_sorted(this_arg, args)
    "TypedArray.prototype.keys" => self.typedarray_keys(this_arg)
    "TypedArray.prototype.values" => self.typedarray_values(this_arg)
    "TypedArray.prototype.entries" => self.typedarray_entries(this_arg)
    // TypedArray.prototype getters
    "TypedArray.prototype.length" =>
      match get_typedarray_data(this_arg) {
        Some(data) => {
          if data.buffer.detached {
            return Number(0.0)
          }
          Number(data.length.to_double())
        }
        None =>
          self.set_error_kind(
            "TypeError", "TypedArray.prototype.length requires that 'this' be a TypedArray",
          )
      }
    "TypedArray.prototype.byteLength" =>
      match get_typedarray_data(this_arg) {
        Some(data) => {
          if data.buffer.detached {
            return Number(0.0)
          }
          Number(data.byte_length.to_double())
        }
        None =>
          self.set_error_kind(
            "TypeError", "TypedArray.prototype.byteLength requires that 'this' be a TypedArray",
          )
      }
    "TypedArray.prototype.byteOffset" =>
      match get_typedarray_data(this_arg) {
        Some(data) => {
          if data.buffer.detached {
            return Number(0.0)
          }
          Number(data.byte_offset.to_double())
        }
        None =>
          self.set_error_kind(
            "TypeError", "TypedArray.prototype.byteOffset requires that 'this' be a TypedArray",
          )
      }
    "TypedArray.prototype.buffer" =>
      match get_typedarray_data(this_arg) {
        Some(_) => js_get_prop(this_arg, "buffer")
        None =>
          self.set_error_kind(
            "TypeError", "TypedArray.prototype.buffer requires that 'this' be a TypedArray",
          )
      }
    "TypedArray.prototype.@@toStringTag" =>
      match js_get_prop(this_arg, "__ta_type_tag") {
        String(name) => String(name)
        _ => Undefined
      }
    // TypedArray static methods
    "TypedArray.@@species" => this_arg // get [Symbol.species] returns `this`
    "TypedArray.from" => {
      // TypedArray.from(source [, mapfn [, thisArg]])
      // `this` should be a TypedArray constructor (Int8Array, etc.)
      if args.length() == 0 {
        return self.set_error_kind(
          "TypeError", "Cannot convert undefined or null to object",
        )
      }
      let source = args[0]
      let mapfn : JSValue? = if args.length() > 1 {
        Some(args[1])
      } else {
        None
      }
      let this_arg_for_map = if args.length() > 2 { args[2] } else { Undefined }
      // Get source as array-like
      let source_len = js_get_prop(source, "length").to_number().to_int()
      // Create new typed array with the constructor
      let new_ta = self.call_function(this_arg, Undefined, [
        Number(source_len.to_double()),
      ])
      // Copy elements
      for i = 0; i < source_len; i = i + 1 {
        let elem = js_get_prop(source, i.to_string())
        let mapped = match mapfn {
          Some(map_func) =>
            self.call_function(map_func, this_arg_for_map, [
              elem,
              Number(i.to_double()),
            ])
          None => elem
        }
        let _ = js_set_prop(new_ta, i.to_string(), mapped)

      }
      new_ta
    }
    "TypedArray.of" => {
      // TypedArray.of(element0, element1, ...)
      // `this` should be a TypedArray constructor
      let len = args.length()
      let new_ta = self.call_function(this_arg, Undefined, [
        Number(len.to_double()),
      ])
      for i = 0; i < len; i = i + 1 {
        let _ = js_set_prop(new_ta, i.to_string(), args[i])

      }
      new_ta
    }
    "TypedArray" =>
      self.set_error_kind(
        "TypeError", "Abstract class TypedArray not directly constructable",
      )
    // DataView
    "DataView" => self.create_dataview(args)
    // DataView.prototype getters
    "DataView.prototype.buffer" =>
      match js_get_prop(this_arg, "__class") {
        String("DataView") => js_get_prop(this_arg, "buffer")
        _ =>
          self.set_error_kind(
            "TypeError", "DataView.prototype.buffer requires that 'this' be a DataView",
          )
      }
    "DataView.prototype.byteLength" =>
      match js_get_prop(this_arg, "__class") {
        String("DataView") => {
          let buf_id = js_get_prop(this_arg, "__dv_buffer_id")
            .to_number()
            .to_int()
          match get_bytebuffer(buf_id) {
            Some(buf) => {
              if buf.detached {
                return self.set_error_kind(
                  "TypeError", "Cannot read byteLength of DataView with detached buffer",
                )
              }
              js_get_prop(this_arg, "byteLength")
            }
            None => Undefined
          }
        }
        _ =>
          self.set_error_kind(
            "TypeError", "DataView.prototype.byteLength requires that 'this' be a DataView",
          )
      }
    "DataView.prototype.byteOffset" =>
      match js_get_prop(this_arg, "__class") {
        String("DataView") => {
          let buf_id = js_get_prop(this_arg, "__dv_buffer_id")
            .to_number()
            .to_int()
          match get_bytebuffer(buf_id) {
            Some(buf) => {
              if buf.detached {
                return self.set_error_kind(
                  "TypeError", "Cannot read byteOffset of DataView with detached buffer",
                )
              }
              js_get_prop(this_arg, "byteOffset")
            }
            None => Undefined
          }
        }
        _ =>
          self.set_error_kind(
            "TypeError", "DataView.prototype.byteOffset requires that 'this' be a DataView",
          )
      }
    // DataView.prototype methods
    "DataView.prototype.getInt8" => self.dataview_get(this_arg, args, "Int8")
    "DataView.prototype.getUint8" => self.dataview_get(this_arg, args, "Uint8")
    "DataView.prototype.getInt16" => self.dataview_get(this_arg, args, "Int16")
    "DataView.prototype.getUint16" =>
      self.dataview_get(this_arg, args, "Uint16")
    "DataView.prototype.getInt32" => self.dataview_get(this_arg, args, "Int32")
    "DataView.prototype.getUint32" =>
      self.dataview_get(this_arg, args, "Uint32")
    "DataView.prototype.getFloat32" =>
      self.dataview_get(this_arg, args, "Float32")
    "DataView.prototype.getFloat64" =>
      self.dataview_get(this_arg, args, "Float64")
    "DataView.prototype.setInt8" => self.dataview_set(this_arg, args, "Int8")
    "DataView.prototype.setUint8" => self.dataview_set(this_arg, args, "Uint8")
    "DataView.prototype.setInt16" => self.dataview_set(this_arg, args, "Int16")
    "DataView.prototype.setUint16" =>
      self.dataview_set(this_arg, args, "Uint16")
    "DataView.prototype.setInt32" => self.dataview_set(this_arg, args, "Int32")
    "DataView.prototype.setUint32" =>
      self.dataview_set(this_arg, args, "Uint32")
    "DataView.prototype.setFloat32" =>
      self.dataview_set(this_arg, args, "Float32")
    "DataView.prototype.setFloat64" =>
      self.dataview_set(this_arg, args, "Float64")
    // TypedArray iterator
    "TypedArrayIterator.next" => {
      let iter_type = match js_get_prop(this_arg, "__iter_type") {
        String(t) => t
        _ => return Undefined
      }
      let index = match js_get_prop(this_arg, "__iter_index") {
        Number(n) => n.to_int()
        _ => return Undefined
      }
      let length = match js_get_prop(this_arg, "__iter_length") {
        Number(n) => n.to_int()
        _ => return Undefined
      }
      if index >= length {
        let result = self.new_object()
        let _ = js_set_prop(result, "done", Bool(true))
        let _ = js_set_prop(result, "value", Undefined)
        return result
      }
      let source = js_get_prop(this_arg, "__iter_source")
      let value = match get_typedarray_data(source) {
        Some(data) => {
          let val = typedarray_get_element_jsvalue(data, index)
          match iter_type {
            "TypedArrayKeys" => JSValue::Number(index.to_double())
            "TypedArrayValues" => val
            "TypedArrayEntries" =>
              js_array_from([JSValue::Number(index.to_double()), val])
            _ => Undefined
          }
        }
        None => Undefined
      }
      let _ = js_set_prop(
        this_arg,
        "__iter_index",
        Number((index + 1).to_double()),
      )
      let result = self.new_object()
      let _ = js_set_prop(result, "done", Bool(false))
      let _ = js_set_prop(result, "value", value)
      result
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
      let msg = if args.length() > 0 { args[0].to_js_string() } else { "" }
      let obj = self.new_object()
      let _ = js_set_prop(obj, "name", JSValue::String("Test262Error"))
      let _ = js_set_prop(obj, "message", JSValue::String(msg))
      obj
    }
    "Function" => self.call_native("Function", Undefined, args)
    "Boolean" => {
      let val = if args.length() > 0 {
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
      let val = if args.length() > 0 {
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
      let val = if args.length() > 0 {
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
