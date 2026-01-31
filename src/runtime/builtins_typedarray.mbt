// TypedArray and ArrayBuffer implementation

///|
/// ByteBuffer - internal byte storage for ArrayBuffer
pub struct JSByteBuffer {
  id : Int
  data : Array[Byte]
  mut detached : Bool
} derive(Show)

///|
/// ByteBuffer ID generator
priv struct ByteBufferIdGen {
  mut id : Int
}

///|
let bytebuffer_id_gen : ByteBufferIdGen = { id: 1 }

///|
fn fresh_bytebuffer_id() -> Int {
  let id = bytebuffer_id_gen.id
  bytebuffer_id_gen.id = id + 1
  id
}

///|
/// Create a new ByteBuffer with specified length
pub fn js_new_bytebuffer(length : Int) -> JSByteBuffer {
  let data : Array[Byte] = Array::make(length, b'\x00')
  { id: fresh_bytebuffer_id(), data, detached: false }
}

///|
/// TypedArray type tag
pub enum TypedArrayKind {
  Int8Array
  Uint8Array
  Uint8ClampedArray
  Int16Array
  Uint16Array
  Int32Array
  Uint32Array
  Float32Array
  Float64Array
  BigInt64Array
  BigUint64Array
} derive(Show, Eq)

///|
/// Get bytes per element for TypedArray type
pub fn TypedArrayKind::bytes_per_element(self : TypedArrayKind) -> Int {
  match self {
    Int8Array | Uint8Array | Uint8ClampedArray => 1
    Int16Array | Uint16Array => 2
    Int32Array | Uint32Array | Float32Array => 4
    Float64Array | BigInt64Array | BigUint64Array => 8
  }
}

///|
/// Get type name
pub fn TypedArrayKind::type_name(self : TypedArrayKind) -> String {
  match self {
    Int8Array => "Int8Array"
    Uint8Array => "Uint8Array"
    Uint8ClampedArray => "Uint8ClampedArray"
    Int16Array => "Int16Array"
    Uint16Array => "Uint16Array"
    Int32Array => "Int32Array"
    Uint32Array => "Uint32Array"
    Float32Array => "Float32Array"
    Float64Array => "Float64Array"
    BigInt64Array => "BigInt64Array"
    BigUint64Array => "BigUint64Array"
  }
}

///|
/// TypedArray internal holder - stores ArrayBuffer reference
pub struct TypedArrayData {
  kind : TypedArrayKind
  buffer : JSByteBuffer
  byte_offset : Int
  byte_length : Int
  length : Int
} derive(Show)

///|
/// Global storage for ByteBuffers (referenced by ID from Objects)
priv struct ByteBufferStorage {
  buffers : Array[(Int, JSByteBuffer)]
}

///|
let bytebuffer_storage : ByteBufferStorage = { buffers: [] }

///|
/// Store a ByteBuffer and return its ID
pub fn store_bytebuffer(buf : JSByteBuffer) -> Int {
  bytebuffer_storage.buffers.push((buf.id, buf))
  buf.id
}

///|
/// Get a ByteBuffer by ID
pub fn get_bytebuffer(id : Int) -> JSByteBuffer? {
  for pair in bytebuffer_storage.buffers {
    if pair.0 == id {
      return Some(pair.1)
    }
  }
  None
}

///|
/// Detach a ByteBuffer by ID (marks it as detached)
pub fn detach_bytebuffer(id : Int) -> Unit {
  for pair in bytebuffer_storage.buffers {
    if pair.0 == id {
      pair.1.detached = true
      return
    }
  }
}

///|
/// Global storage for TypedArrayData (referenced by ID from Objects)
priv struct TypedArrayStorage {
  arrays : Array[(Int, TypedArrayData)]
}

///|
let typedarray_storage : TypedArrayStorage = { arrays: [] }

///|
priv struct TypedArrayIdGen {
  mut id : Int
}

///|
let typedarray_id_gen : TypedArrayIdGen = { id: 1 }

///|
fn fresh_typedarray_id() -> Int {
  let id = typedarray_id_gen.id
  typedarray_id_gen.id = id + 1
  id
}

///|
/// Store TypedArrayData and return its ID
pub fn store_typedarray(data : TypedArrayData) -> Int {
  let id = fresh_typedarray_id()
  typedarray_storage.arrays.push((id, data))
  id
}

///|
/// Get TypedArrayData by ID
pub fn get_typedarray(id : Int) -> TypedArrayData? {
  for pair in typedarray_storage.arrays {
    if pair.0 == id {
      return Some(pair.1)
    }
  }
  None
}

// === Byte conversion helpers ===

///|
/// Read Int8 from buffer at offset
pub fn read_int8(buf : JSByteBuffer, offset : Int) -> Int {
  let b = buf.data[offset].to_int()
  if b >= 128 {
    b - 256
  } else {
    b
  }
}

///|
/// Read Uint8 from buffer at offset
pub fn read_uint8(buf : JSByteBuffer, offset : Int) -> Int {
  buf.data[offset].to_int()
}

///|
/// Write Int8/Uint8 to buffer at offset
pub fn write_uint8(buf : JSByteBuffer, offset : Int, value : Int) -> Unit {
  buf.data[offset] = (value & 0xFF).to_byte()
}

///|
/// Clamp value to 0-255 range for Uint8ClampedArray
pub fn clamp_uint8(value : Double) -> Int {
  if value.is_nan() {
    return 0
  }
  let rounded = value.round().to_int()
  if rounded < 0 {
    0
  } else if rounded > 255 {
    255
  } else {
    rounded
  }
}

///|
/// Read Int16 from buffer at offset (little-endian)
pub fn read_int16_le(buf : JSByteBuffer, offset : Int) -> Int {
  let lo = buf.data[offset].to_int()
  let hi = buf.data[offset + 1].to_int()
  let value = lo | (hi << 8)
  if value >= 32768 {
    value - 65536
  } else {
    value
  }
}

///|
/// Read Uint16 from buffer at offset (little-endian)
pub fn read_uint16_le(buf : JSByteBuffer, offset : Int) -> Int {
  let lo = buf.data[offset].to_int()
  let hi = buf.data[offset + 1].to_int()
  lo | (hi << 8)
}

///|
/// Read Int16 from buffer at offset (big-endian)
pub fn read_int16_be(buf : JSByteBuffer, offset : Int) -> Int {
  let hi = buf.data[offset].to_int()
  let lo = buf.data[offset + 1].to_int()
  let value = lo | (hi << 8)
  if value >= 32768 {
    value - 65536
  } else {
    value
  }
}

///|
/// Read Uint16 from buffer at offset (big-endian)
pub fn read_uint16_be(buf : JSByteBuffer, offset : Int) -> Int {
  let hi = buf.data[offset].to_int()
  let lo = buf.data[offset + 1].to_int()
  lo | (hi << 8)
}

///|
/// Write Int16/Uint16 to buffer at offset (little-endian)
pub fn write_uint16_le(buf : JSByteBuffer, offset : Int, value : Int) -> Unit {
  buf.data[offset] = (value & 0xFF).to_byte()
  buf.data[offset + 1] = ((value >> 8) & 0xFF).to_byte()
}

///|
/// Write Int16/Uint16 to buffer at offset (big-endian)
pub fn write_uint16_be(buf : JSByteBuffer, offset : Int, value : Int) -> Unit {
  buf.data[offset] = ((value >> 8) & 0xFF).to_byte()
  buf.data[offset + 1] = (value & 0xFF).to_byte()
}

///|
/// Read Int32 from buffer at offset (little-endian)
pub fn read_int32_le(buf : JSByteBuffer, offset : Int) -> Int {
  let b0 = buf.data[offset].to_int()
  let b1 = buf.data[offset + 1].to_int()
  let b2 = buf.data[offset + 2].to_int()
  let b3 = buf.data[offset + 3].to_int()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
/// Read Uint32 from buffer at offset (little-endian)
pub fn read_uint32_le(buf : JSByteBuffer, offset : Int) -> Int64 {
  let b0 = buf.data[offset].to_int().to_int64()
  let b1 = buf.data[offset + 1].to_int().to_int64()
  let b2 = buf.data[offset + 2].to_int().to_int64()
  let b3 = buf.data[offset + 3].to_int().to_int64()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
/// Read Int32 from buffer at offset (big-endian)
pub fn read_int32_be(buf : JSByteBuffer, offset : Int) -> Int {
  let b3 = buf.data[offset].to_int()
  let b2 = buf.data[offset + 1].to_int()
  let b1 = buf.data[offset + 2].to_int()
  let b0 = buf.data[offset + 3].to_int()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
/// Read Uint32 from buffer at offset (big-endian)
pub fn read_uint32_be(buf : JSByteBuffer, offset : Int) -> Int64 {
  let b3 = buf.data[offset].to_int().to_int64()
  let b2 = buf.data[offset + 1].to_int().to_int64()
  let b1 = buf.data[offset + 2].to_int().to_int64()
  let b0 = buf.data[offset + 3].to_int().to_int64()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
/// Write Int32/Uint32 to buffer at offset (little-endian)
pub fn write_uint32_le(buf : JSByteBuffer, offset : Int, value : Int) -> Unit {
  buf.data[offset] = (value & 0xFF).to_byte()
  buf.data[offset + 1] = ((value >> 8) & 0xFF).to_byte()
  buf.data[offset + 2] = ((value >> 16) & 0xFF).to_byte()
  buf.data[offset + 3] = ((value >> 24) & 0xFF).to_byte()
}

///|
/// Write Int32/Uint32 to buffer at offset (big-endian)
pub fn write_uint32_be(buf : JSByteBuffer, offset : Int, value : Int) -> Unit {
  buf.data[offset] = ((value >> 24) & 0xFF).to_byte()
  buf.data[offset + 1] = ((value >> 16) & 0xFF).to_byte()
  buf.data[offset + 2] = ((value >> 8) & 0xFF).to_byte()
  buf.data[offset + 3] = (value & 0xFF).to_byte()
}

///|
/// Read Float32 from buffer at offset (little-endian)
/// Uses IEEE 754 single precision format via Float type
pub fn read_float32_le(buf : JSByteBuffer, offset : Int) -> Double {
  let bits = read_uint32_le(buf, offset).to_int()
  Float::reinterpret_from_int(bits).to_double()
}

///|
/// Read Float32 from buffer at offset (big-endian)
pub fn read_float32_be(buf : JSByteBuffer, offset : Int) -> Double {
  let bits = read_uint32_be(buf, offset).to_int()
  Float::reinterpret_from_int(bits).to_double()
}

///|
/// Write Float32 to buffer at offset (little-endian)
pub fn write_float32_le(
  buf : JSByteBuffer,
  offset : Int,
  value : Double,
) -> Unit {
  let f = Float::from_double(value)
  let bits = f.reinterpret_as_int()
  write_uint32_le(buf, offset, bits)
}

///|
/// Write Float32 to buffer at offset (big-endian)
pub fn write_float32_be(
  buf : JSByteBuffer,
  offset : Int,
  value : Double,
) -> Unit {
  let f = Float::from_double(value)
  let bits = f.reinterpret_as_int()
  write_uint32_be(buf, offset, bits)
}

///|
/// Read Float64 from buffer at offset (little-endian)
pub fn read_float64_le(buf : JSByteBuffer, offset : Int) -> Double {
  let lo = read_uint32_le(buf, offset)
  let hi = read_uint32_le(buf, offset + 4)
  let bits = lo | (hi << 32)
  bits.reinterpret_as_double()
}

///|
/// Read Float64 from buffer at offset (big-endian)
pub fn read_float64_be(buf : JSByteBuffer, offset : Int) -> Double {
  let hi = read_uint32_be(buf, offset)
  let lo = read_uint32_be(buf, offset + 4)
  let bits = lo | (hi << 32)
  bits.reinterpret_as_double()
}

///|
/// Write Float64 to buffer at offset (little-endian)
pub fn write_float64_le(
  buf : JSByteBuffer,
  offset : Int,
  value : Double,
) -> Unit {
  let bits = value.reinterpret_as_int64()
  let lo = (bits & 0xFFFFFFFFL).to_int()
  let hi = (bits >> 32).to_int()
  write_uint32_le(buf, offset, lo)
  write_uint32_le(buf, offset + 4, hi)
}

///|
/// Write Float64 to buffer at offset (big-endian)
pub fn write_float64_be(
  buf : JSByteBuffer,
  offset : Int,
  value : Double,
) -> Unit {
  let bits = value.reinterpret_as_int64()
  let lo = (bits & 0xFFFFFFFFL).to_int()
  let hi = (bits >> 32).to_int()
  write_uint32_be(buf, offset, hi)
  write_uint32_be(buf, offset + 4, lo)
}

///|
/// Read Int64 from buffer at offset (little-endian)
pub fn read_int64_le(buf : JSByteBuffer, offset : Int) -> Int64 {
  let lo = read_uint32_le(buf, offset)
  let hi = read_uint32_le(buf, offset + 4)
  lo | (hi << 32)
}

///|
/// Write Int64 to buffer at offset (little-endian)
pub fn write_int64_le(buf : JSByteBuffer, offset : Int, value : Int64) -> Unit {
  let lo = (value & 0xFFFFFFFFL).to_int()
  let hi = (value >> 32).to_int()
  write_uint32_le(buf, offset, lo)
  write_uint32_le(buf, offset + 4, hi)
}

// === TypedArray element access ===

///|
/// Read element from TypedArray at given index
pub fn typedarray_get_element(data : TypedArrayData, index : Int) -> Double {
  if index < 0 || index >= data.length || data.buffer.detached {
    return 0.0 / 0.0 // NaN for out of bounds (will become undefined in caller)
  }
  let offset = data.byte_offset + index * data.kind.bytes_per_element()
  match data.kind {
    Int8Array => read_int8(data.buffer, offset).to_double()
    Uint8Array | Uint8ClampedArray =>
      read_uint8(data.buffer, offset).to_double()
    Int16Array => read_int16_le(data.buffer, offset).to_double()
    Uint16Array => read_uint16_le(data.buffer, offset).to_double()
    Int32Array => read_int32_le(data.buffer, offset).to_double()
    Uint32Array => read_uint32_le(data.buffer, offset).to_double()
    Float32Array => read_float32_le(data.buffer, offset)
    Float64Array => read_float64_le(data.buffer, offset)
    BigInt64Array | BigUint64Array =>
      read_int64_le(data.buffer, offset).to_double()
  }
}

///|
/// Write element to TypedArray at given index
pub fn typedarray_set_element(
  data : TypedArrayData,
  index : Int,
  value : Double,
) -> Unit {
  if index < 0 || index >= data.length || data.buffer.detached {
    return
  }
  let offset = data.byte_offset + index * data.kind.bytes_per_element()
  match data.kind {
    Int8Array | Uint8Array => write_uint8(data.buffer, offset, value.to_int())
    Uint8ClampedArray => write_uint8(data.buffer, offset, clamp_uint8(value))
    Int16Array | Uint16Array =>
      write_uint16_le(data.buffer, offset, value.to_int())
    Int32Array | Uint32Array =>
      write_uint32_le(data.buffer, offset, value.to_int())
    Float32Array => write_float32_le(data.buffer, offset, value)
    Float64Array => write_float64_le(data.buffer, offset, value)
    BigInt64Array | BigUint64Array =>
      write_int64_le(data.buffer, offset, value.to_int64())
  }
}

///|
/// Read element from TypedArray as JSValue (handles BigInt types)
pub fn typedarray_get_element_jsvalue(
  data : TypedArrayData,
  index : Int,
) -> JSValue {
  if index < 0 || index >= data.length || data.buffer.detached {
    return Undefined
  }
  let offset = data.byte_offset + index * data.kind.bytes_per_element()
  match data.kind {
    Int8Array => Number(read_int8(data.buffer, offset).to_double())
    Uint8Array | Uint8ClampedArray =>
      Number(read_uint8(data.buffer, offset).to_double())
    Int16Array => Number(read_int16_le(data.buffer, offset).to_double())
    Uint16Array => Number(read_uint16_le(data.buffer, offset).to_double())
    Int32Array => Number(read_int32_le(data.buffer, offset).to_double())
    Uint32Array => Number(read_uint32_le(data.buffer, offset).to_double())
    Float32Array => Number(read_float32_le(data.buffer, offset))
    Float64Array => Number(read_float64_le(data.buffer, offset))
    BigInt64Array =>
      BigInt(BigInt::from_int64(read_int64_le(data.buffer, offset)))
    BigUint64Array => {
      // For unsigned 64-bit, we need to handle the sign bit properly
      let val = read_int64_le(data.buffer, offset)
      BigInt(BigInt::from_int64(val)) // Will be interpreted as unsigned in BigInt context
    }
  }
}

///|
/// Write element to TypedArray from JSValue (handles BigInt types)
pub fn typedarray_set_element_jsvalue(
  data : TypedArrayData,
  index : Int,
  value : JSValue,
) -> Unit {
  if index < 0 || index >= data.length || data.buffer.detached {
    return
  }
  let offset = data.byte_offset + index * data.kind.bytes_per_element()
  match data.kind {
    Int8Array | Uint8Array => {
      let v = match value {
        BigInt(n) => n.to_int()
        _ => value.to_number().to_int()
      }
      write_uint8(data.buffer, offset, v)
    }
    Uint8ClampedArray =>
      write_uint8(data.buffer, offset, clamp_uint8(value.to_number()))
    Int16Array | Uint16Array => {
      let v = match value {
        BigInt(n) => n.to_int()
        _ => value.to_number().to_int()
      }
      write_uint16_le(data.buffer, offset, v)
    }
    Int32Array | Uint32Array => {
      let v = match value {
        BigInt(n) => n.to_int()
        _ => value.to_number().to_int()
      }
      write_uint32_le(data.buffer, offset, v)
    }
    Float32Array => write_float32_le(data.buffer, offset, value.to_number())
    Float64Array => write_float64_le(data.buffer, offset, value.to_number())
    BigInt64Array | BigUint64Array => {
      let v : Int64 = match value {
        BigInt(n) => n.to_int64()
        _ => value.to_number().to_int64()
      }
      write_int64_le(data.buffer, offset, v)
    }
  }
}

///|
/// Check if TypedArray kind is a BigInt type
pub fn TypedArrayKind::is_bigint_type(self : TypedArrayKind) -> Bool {
  match self {
    BigInt64Array | BigUint64Array => true
    _ => false
  }
}

// === Check functions ===

///|
/// Check if value is an ArrayBuffer
pub fn is_arraybuffer(value : JSValue) -> Bool {
  match value {
    Object(_) =>
      match js_get_prop(value, "__class") {
        String("ArrayBuffer") => true
        _ => false
      }
    _ => false
  }
}

///|
/// Check if value is a TypedArray view
pub fn is_typedarray(value : JSValue) -> Bool {
  match value {
    Object(_) =>
      match js_get_prop(value, "__ta_id") {
        Number(_) => true
        _ => false
      }
    _ => false
  }
}

///|
/// Check if value is a DataView
pub fn is_dataview(value : JSValue) -> Bool {
  match value {
    Object(_) =>
      match js_get_prop(value, "__class") {
        String("DataView") => true
        _ => false
      }
    _ => false
  }
}

///|
/// Get TypedArrayData from JSValue if it's a TypedArray
/// Note: This function directly accesses properties to avoid infinite recursion
/// with js_get_prop which calls this function for Object values
pub fn get_typedarray_data(value : JSValue) -> TypedArrayData? {
  match value {
    Object(map) => {
      for prop in map.props {
        if prop.key == "__ta_id" {
          match prop.value {
            Number(id) => return get_typedarray(id.to_int())
            _ => ()
          }
        }
      }
      None
    }
    _ => None
  }
}

///|
/// Get ByteBuffer from JSValue if it's an ArrayBuffer
/// Note: This function directly accesses properties to avoid infinite recursion
pub fn get_arraybuffer_data(value : JSValue) -> JSByteBuffer? {
  match value {
    Object(map) => {
      for prop in map.props {
        if prop.key == "__ab_id" {
          match prop.value {
            Number(id) => return get_bytebuffer(id.to_int())
            _ => ()
          }
        }
      }
      None
    }
    _ => None
  }
}

// === JSInterpreter TypedArray methods ===

///|
/// Create a TypedArray of the specified kind
fn JSInterpreter::create_typedarray(
  self : JSInterpreter,
  kind : TypedArrayKind,
  args : Array[JSValue],
) -> JSValue {
  let type_name = kind.type_name()
  let bytes_per_element = kind.bytes_per_element()
  let ctor = self.global_env.get(type_name)
  let proto = js_get_prop(ctor, "prototype")
  // Determine construction mode based on first argument
  if args.length() == 0 {
    // new TypedArray() - empty array with length 0
    return self.create_typedarray_from_length(kind, 0, proto)
  }
  let first_arg = args[0]
  match first_arg {
    Number(n) => {
      // new TypedArray(length)
      let length = n.to_int()
      if length < 0 {
        return self.set_error_kind("RangeError", "Invalid typed array length")
      }
      self.create_typedarray_from_length(kind, length, proto)
    }
    Object(_) =>
      // Check if ArrayBuffer
      if is_arraybuffer(first_arg) {
        // new TypedArray(buffer, byteOffset?, length?)
        let byte_offset = if args.length() > 1 {
          args[1].to_number().to_int()
        } else {
          0
        }
        match get_arraybuffer_data(first_arg) {
          Some(buf) => {
            if buf.detached {
              return self.set_error_kind("TypeError", "ArrayBuffer is detached")
            }
            let buffer_byte_length = buf.data.length()
            // Check alignment
            if byte_offset % bytes_per_element != 0 {
              return self.set_error_kind(
                "RangeError",
                "Start offset of " +
                type_name +
                " should be a multiple of " +
                bytes_per_element.to_string(),
              )
            }
            if byte_offset < 0 || byte_offset > buffer_byte_length {
              return self.set_error_kind("RangeError", "Invalid byte offset")
            }
            let length = if args.length() > 2 && not(args[2].is_undefined()) {
              let len = args[2].to_number().to_int()
              if len < 0 {
                return self.set_error_kind(
                  "RangeError", "Invalid typed array length",
                )
              }
              if byte_offset + len * bytes_per_element > buffer_byte_length {
                return self.set_error_kind(
                  "RangeError", "Invalid typed array length",
                )
              }
              len
            } else {
              let remaining = buffer_byte_length - byte_offset
              if remaining % bytes_per_element != 0 {
                return self.set_error_kind(
                  "RangeError",
                  "Byte length of " +
                  type_name +
                  " should be a multiple of " +
                  bytes_per_element.to_string(),
                )
              }
              remaining / bytes_per_element
            }
            let byte_length = length * bytes_per_element
            self.create_typedarray_from_buffer(
              kind, buf, byte_offset, byte_length, length, first_arg, proto,
            )
          }
          None =>
            self.set_error_kind("TypeError", "Expected ArrayBuffer argument")
        }
      } else if is_typedarray(first_arg) {
        // new TypedArray(typedArray) - copy from another TypedArray
        self.create_typedarray_from_typedarray(kind, first_arg, proto)
      } else {
        // new TypedArray(arrayLike) or iterable
        self.create_typedarray_from_arraylike(kind, first_arg, proto)
      }
    Array(_) =>
      // new TypedArray(array)
      self.create_typedarray_from_arraylike(kind, first_arg, proto)
    _ =>
      // Treat as length
      self.create_typedarray_from_length(
        kind,
        first_arg.to_number().to_int(),
        proto,
      )
  }
}

///|
/// Create TypedArray with new ArrayBuffer of specified length
fn JSInterpreter::create_typedarray_from_length(
  self : JSInterpreter,
  kind : TypedArrayKind,
  length : Int,
  proto : JSValue,
) -> JSValue {
  let bytes_per_element = kind.bytes_per_element()
  let byte_length = length * bytes_per_element
  let buf = js_new_bytebuffer(byte_length)
  let buf_id = store_bytebuffer(buf)
  // Create ArrayBuffer object
  let ab_obj = self.new_object()
  let ab_proto = js_get_prop(self.global_env.get("ArrayBuffer"), "prototype")
  let _ = js_set_prop(ab_obj, "__proto__", ab_proto)
  let _ = js_set_prop(ab_obj, "__class", String("ArrayBuffer"))
  let _ = js_set_prop(ab_obj, "__ab_id", Number(buf_id.to_double()))
  // Create TypedArray
  self.create_typedarray_from_buffer(
    kind, buf, 0, byte_length, length, ab_obj, proto,
  )
}

///|
/// Create TypedArray view on existing buffer
fn JSInterpreter::create_typedarray_from_buffer(
  self : JSInterpreter,
  kind : TypedArrayKind,
  buf : JSByteBuffer,
  byte_offset : Int,
  byte_length : Int,
  length : Int,
  ab_obj : JSValue,
  proto : JSValue,
) -> JSValue {
  let data : TypedArrayData = {
    kind,
    buffer: buf,
    byte_offset,
    byte_length,
    length,
  }
  let ta_id = store_typedarray(data)
  let ta_obj = self.new_object()
  let _ = js_set_prop(ta_obj, "__proto__", proto)
  let _ = js_set_prop(ta_obj, "__class", String(kind.type_name()))
  let _ = js_set_prop(ta_obj, "__ta_id", Number(ta_id.to_double()))
  let _ = js_set_prop(ta_obj, "buffer", ab_obj)
  let _ = js_set_prop(ta_obj, "byteOffset", Number(byte_offset.to_double()))
  let _ = js_set_prop(ta_obj, "byteLength", Number(byte_length.to_double()))
  let _ = js_set_prop(ta_obj, "length", Number(length.to_double()))
  let _ = js_set_prop(
    ta_obj,
    "BYTES_PER_ELEMENT",
    Number(kind.bytes_per_element().to_double()),
  )
  ta_obj
}

///|
/// Create TypedArray by copying from another TypedArray
fn JSInterpreter::create_typedarray_from_typedarray(
  self : JSInterpreter,
  kind : TypedArrayKind,
  source : JSValue,
  proto : JSValue,
) -> JSValue {
  match get_typedarray_data(source) {
    Some(src_data) => {
      if src_data.buffer.detached {
        return self.set_error_kind("TypeError", "Source buffer is detached")
      }
      let length = src_data.length
      let ta = self.create_typedarray_from_length(kind, length, proto)
      match get_typedarray_data(ta) {
        Some(dst_data) =>
          for i = 0; i < length; i = i + 1 {
            let val = typedarray_get_element(src_data, i)
            typedarray_set_element(dst_data, i, val)
          }
        None => ()
      }
      ta
    }
    None => self.set_error_kind("TypeError", "Expected TypedArray")
  }
}

///|
/// Create TypedArray from array-like object
fn JSInterpreter::create_typedarray_from_arraylike(
  self : JSInterpreter,
  kind : TypedArrayKind,
  source : JSValue,
  proto : JSValue,
) -> JSValue {
  let length = match js_get_prop(source, "length") {
    Number(n) => n.to_int()
    _ => 0
  }
  let ta = self.create_typedarray_from_length(kind, length, proto)
  match get_typedarray_data(ta) {
    Some(data) =>
      for i = 0; i < length; i = i + 1 {
        let val = js_get_prop(source, i.to_string())
        typedarray_set_element(data, i, val.to_number())
      }
    None => ()
  }
  ta
}

// === TypedArray prototype methods ===

///|
/// TypedArray.prototype.set(array, offset?)
fn JSInterpreter::typedarray_set(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      if data.buffer.detached {
        return self.set_error_kind("TypeError", "Buffer is detached")
      }
      let source = if args.length() > 0 { args[0] } else { return Undefined }
      let offset = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
      if offset < 0 {
        return self.set_error_kind("RangeError", "Offset is out of bounds")
      }
      // Get source length
      let src_length = match js_get_prop(source, "length") {
        Number(n) => n.to_int()
        _ => 0
      }
      if offset + src_length > data.length {
        return self.set_error_kind("RangeError", "Offset is out of bounds")
      }
      let is_bigint_target = data.kind.is_bigint_type()
      // Copy elements
      match get_typedarray_data(source) {
        Some(src_data) =>
          // Source is TypedArray - need to convert between BigInt and Number types
          for i = 0; i < src_length; i = i + 1 {
            let val = typedarray_get_element_jsvalue(src_data, i)
            if is_bigint_target {
              // Target is BigInt typed array, validate value
              match val {
                BigInt(_) =>
                  typedarray_set_element_jsvalue(data, offset + i, val)
                Number(n) => {
                  // Convert Number to BigInt for BigInt typed arrays
                  if n.is_nan() || n.is_inf() || n != n.trunc() {
                    return self.set_error_kind(
                      "RangeError", "Cannot convert non-integer to BigInt",
                    )
                  }
                  typedarray_set_element_jsvalue(
                    data,
                    offset + i,
                    BigInt(BigInt::from_int64(n.to_int64())),
                  )
                }
                _ =>
                  return self.set_error_kind(
                    "TypeError", "Cannot convert to BigInt",
                  )
              }
            } else {
              // Target is not BigInt typed array
              match val {
                BigInt(n) =>
                  typedarray_set_element(
                    data,
                    offset + i,
                    n.to_int64().to_double(),
                  )
                _ => typedarray_set_element_jsvalue(data, offset + i, val)
              }
            }
          }
        None =>
          // Source is array-like
          for i = 0; i < src_length; i = i + 1 {
            let val = js_get_prop(source, i.to_string())
            if is_bigint_target {
              // Target is BigInt typed array, need BigInt values
              match val {
                BigInt(_) =>
                  typedarray_set_element_jsvalue(data, offset + i, val)
                Number(n) => {
                  if n.is_nan() || n.is_inf() || n != n.trunc() {
                    return self.set_error_kind(
                      "RangeError", "Cannot convert non-integer to BigInt",
                    )
                  }
                  typedarray_set_element_jsvalue(
                    data,
                    offset + i,
                    BigInt(BigInt::from_int64(n.to_int64())),
                  )
                }
                String(s) => {
                  // Try to parse as BigInt - validate first
                  let trimmed = s.trim_start().trim_end().to_string()
                  if trimmed.is_empty() {
                    return self.set_error_kind(
                      "SyntaxError", "Cannot convert empty string to BigInt",
                    )
                  }
                  // Check if string is a valid integer
                  let start = if trimmed.length() > 0 &&
                    (trimmed[0] == '-' || trimmed[0] == '+') {
                    1
                  } else {
                    0
                  }
                  let mut valid = start < trimmed.length()
                  for i = start; i < trimmed.length(); i = i + 1 {
                    let c = trimmed[i]
                    if c < '0' || c > '9' {
                      valid = false
                      break
                    }
                  }
                  if not(valid) {
                    return self.set_error_kind(
                      "SyntaxError", "Cannot convert to BigInt",
                    )
                  }
                  typedarray_set_element_jsvalue(
                    data,
                    offset + i,
                    BigInt(BigInt::from_string(trimmed)),
                  )
                }
                Bool(b) =>
                  typedarray_set_element_jsvalue(
                    data,
                    offset + i,
                    BigInt(BigInt::from_int(if b { 1 } else { 0 })),
                  )
                Null | Undefined =>
                  return self.set_error_kind(
                    "TypeError", "Cannot convert to BigInt",
                  )
                _ =>
                  return self.set_error_kind(
                    "TypeError", "Cannot convert to BigInt",
                  )
              }
            } else {
              typedarray_set_element(data, offset + i, val.to_number())
            }
          }
      }
      Undefined
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.subarray(begin, end) - returns view of same buffer
fn JSInterpreter::typedarray_subarray(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let length = data.length
      let begin_arg = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      let end_arg = if args.length() > 1 && not(args[1].is_undefined()) {
        args[1].to_number().to_int()
      } else {
        length
      }
      // Resolve relative indices
      let begin = if begin_arg < 0 {
        let b = length + begin_arg
        if b < 0 {
          0
        } else {
          b
        }
      } else if begin_arg > length {
        length
      } else {
        begin_arg
      }
      let end = if end_arg < 0 {
        let e = length + end_arg
        if e < 0 {
          0
        } else {
          e
        }
      } else if end_arg > length {
        length
      } else {
        end_arg
      }
      let new_length = if end > begin { end - begin } else { 0 }
      let bytes_per_element = data.kind.bytes_per_element()
      let new_byte_offset = data.byte_offset + begin * bytes_per_element
      let new_byte_length = new_length * bytes_per_element
      // Get original ArrayBuffer
      let ab_obj = js_get_prop(this_arg, "buffer")
      let proto = js_get_prop(this_arg, "__proto__")
      self.create_typedarray_from_buffer(
        data.kind,
        data.buffer,
        new_byte_offset,
        new_byte_length,
        new_length,
        ab_obj,
        proto,
      )
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.slice(begin, end) - copies data to new array
fn JSInterpreter::typedarray_slice(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      if data.buffer.detached {
        return self.set_error_kind("TypeError", "Buffer is detached")
      }
      let length = data.length
      let begin_arg = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      let end_arg = if args.length() > 1 && not(args[1].is_undefined()) {
        args[1].to_number().to_int()
      } else {
        length
      }
      // Resolve relative indices
      let begin = if begin_arg < 0 {
        let b = length + begin_arg
        if b < 0 {
          0
        } else {
          b
        }
      } else if begin_arg > length {
        length
      } else {
        begin_arg
      }
      let end = if end_arg < 0 {
        let e = length + end_arg
        if e < 0 {
          0
        } else {
          e
        }
      } else if end_arg > length {
        length
      } else {
        end_arg
      }
      let new_length = if end > begin { end - begin } else { 0 }
      let proto = js_get_prop(this_arg, "__proto__")
      let result = self.create_typedarray_from_length(
        data.kind,
        new_length,
        proto,
      )
      match get_typedarray_data(result) {
        Some(dst_data) =>
          for i = 0; i < new_length; i = i + 1 {
            let val = typedarray_get_element(data, begin + i)
            typedarray_set_element(dst_data, i, val)
          }
        None => ()
      }
      result
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.fill(value, start?, end?)
fn JSInterpreter::typedarray_fill(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      if data.buffer.detached {
        return self.set_error_kind("TypeError", "Buffer is detached")
      }
      let is_bigint = data.kind.is_bigint_type()
      let raw_value = if args.length() > 0 { args[0] } else { Number(0.0) }
      // For BigInt typed arrays, convert value to BigInt first
      let fill_value : JSValue = if is_bigint {
        match raw_value {
          BigInt(_) => raw_value
          Number(n) => {
            if n.is_nan() || n.is_inf() || n != n.trunc() {
              return self.set_error_kind(
                "RangeError", "Cannot convert to BigInt",
              )
            }
            BigInt(BigInt::from_int64(n.to_int64()))
          }
          Bool(b) => BigInt(BigInt::from_int(if b { 1 } else { 0 }))
          Null | Undefined =>
            return self.set_error_kind("TypeError", "Cannot convert to BigInt")
          _ =>
            return self.set_error_kind("TypeError", "Cannot convert to BigInt")
        }
      } else {
        Number(raw_value.to_number())
      }
      let length = data.length
      let start_arg = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
      let end_arg = if args.length() > 2 && not(args[2].is_undefined()) {
        args[2].to_number().to_int()
      } else {
        length
      }
      let start = if start_arg < 0 {
        let s = length + start_arg
        if s < 0 {
          0
        } else {
          s
        }
      } else if start_arg > length {
        length
      } else {
        start_arg
      }
      let end = if end_arg < 0 {
        let e = length + end_arg
        if e < 0 {
          0
        } else {
          e
        }
      } else if end_arg > length {
        length
      } else {
        end_arg
      }
      for i = start; i < end; i = i + 1 {
        typedarray_set_element_jsvalue(data, i, fill_value)
      }
      this_arg
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.copyWithin(target, start, end?)
fn JSInterpreter::typedarray_copy_within(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      if data.buffer.detached {
        return self.set_error_kind("TypeError", "Buffer is detached")
      }
      let length = data.length
      let target_arg = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      let start_arg = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
      let end_arg = if args.length() > 2 && not(args[2].is_undefined()) {
        args[2].to_number().to_int()
      } else {
        length
      }
      // Resolve indices
      let target = if target_arg < 0 {
        let t = length + target_arg
        if t < 0 {
          0
        } else {
          t
        }
      } else if target_arg > length {
        length
      } else {
        target_arg
      }
      let start = if start_arg < 0 {
        let s = length + start_arg
        if s < 0 {
          0
        } else {
          s
        }
      } else if start_arg > length {
        length
      } else {
        start_arg
      }
      let end = if end_arg < 0 {
        let e = length + end_arg
        if e < 0 {
          0
        } else {
          e
        }
      } else if end_arg > length {
        length
      } else {
        end_arg
      }
      let count_candidate = end - start
      let count = if target + count_candidate > length {
        length - target
      } else {
        count_candidate
      }
      if count <= 0 {
        return this_arg
      }
      // Copy to temp buffer to handle overlapping
      let temp : Array[Double] = []
      for i = 0; i < count; i = i + 1 {
        temp.push(typedarray_get_element(data, start + i))
      }
      for i = 0; i < count; i = i + 1 {
        typedarray_set_element(data, target + i, temp[i])
      }
      this_arg
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.forEach(callback, thisArg?)
fn JSInterpreter::typedarray_foreach(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let callback = if args.length() > 0 { args[0] } else { return Undefined }
      let this_for_callback = if args.length() > 1 {
        args[1]
      } else {
        Undefined
      }
      for i = 0; i < data.length; i = i + 1 {
        let val = typedarray_get_element_jsvalue(data, i)
        let _ = self.call_function(callback, this_for_callback, [
          val,
          Number(i.to_double()),
          this_arg,
        ])

      }
      Undefined
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.map(callback, thisArg?)
fn JSInterpreter::typedarray_map(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let callback = if args.length() > 0 {
        args[0]
      } else {
        return self.set_error_kind("TypeError", "Callback is not a function")
      }
      let this_for_callback = if args.length() > 1 {
        args[1]
      } else {
        Undefined
      }
      let proto = js_get_prop(this_arg, "__proto__")
      let result = self.create_typedarray_from_length(
        data.kind,
        data.length,
        proto,
      )
      let is_bigint = data.kind.is_bigint_type()
      match get_typedarray_data(result) {
        Some(dst_data) =>
          for i = 0; i < data.length; i = i + 1 {
            let val = typedarray_get_element_jsvalue(data, i)
            let mapped = self.call_function(callback, this_for_callback, [
              val,
              Number(i.to_double()),
              this_arg,
            ])
            if is_bigint {
              // Validate BigInt result
              match mapped {
                BigInt(_) => typedarray_set_element_jsvalue(dst_data, i, mapped)
                Number(n) => {
                  if n.is_nan() || n.is_inf() || n != n.trunc() {
                    return self.set_error_kind(
                      "RangeError", "Cannot convert to BigInt",
                    )
                  }
                  typedarray_set_element_jsvalue(
                    dst_data,
                    i,
                    BigInt(BigInt::from_int64(n.to_int64())),
                  )
                }
                _ =>
                  return self.set_error_kind(
                    "TypeError", "Cannot convert to BigInt",
                  )
              }
            } else {
              typedarray_set_element_jsvalue(dst_data, i, mapped)
            }
          }
        None => ()
      }
      result
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.filter(callback, thisArg?)
fn JSInterpreter::typedarray_filter(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let callback = if args.length() > 0 {
        args[0]
      } else {
        return self.set_error_kind("TypeError", "Callback is not a function")
      }
      let this_for_callback = if args.length() > 1 {
        args[1]
      } else {
        Undefined
      }
      // Collect passing elements
      let kept : Array[JSValue] = []
      for i = 0; i < data.length; i = i + 1 {
        let val = typedarray_get_element_jsvalue(data, i)
        let test_result = self.call_function(callback, this_for_callback, [
          val,
          Number(i.to_double()),
          this_arg,
        ])
        if test_result.to_boolean() {
          kept.push(val)
        }
      }
      let proto = js_get_prop(this_arg, "__proto__")
      let result = self.create_typedarray_from_length(
        data.kind,
        kept.length(),
        proto,
      )
      match get_typedarray_data(result) {
        Some(dst_data) =>
          for i, val in kept {
            typedarray_set_element_jsvalue(dst_data, i, val)
          }
        None => ()
      }
      result
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.reduce(callback, initialValue?)
fn JSInterpreter::typedarray_reduce(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let callback = if args.length() > 0 {
        args[0]
      } else {
        return self.set_error_kind("TypeError", "Callback is not a function")
      }
      if data.length == 0 && args.length() < 2 {
        return self.set_error_kind(
          "TypeError", "Reduce of empty array with no initial value",
        )
      }
      let mut accumulator : JSValue = Undefined
      let mut start_idx = 0
      if args.length() > 1 {
        accumulator = args[1]
        start_idx = 0
      } else {
        accumulator = typedarray_get_element_jsvalue(data, 0)
        start_idx = 1
      }
      for i = start_idx; i < data.length; i = i + 1 {
        let val = typedarray_get_element_jsvalue(data, i)
        accumulator = self.call_function(callback, Undefined, [
          accumulator,
          val,
          JSValue::Number(i.to_double()),
          this_arg,
        ])
      }
      accumulator
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.reduceRight(callback, initialValue?)
fn JSInterpreter::typedarray_reduce_right(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let callback = if args.length() > 0 {
        args[0]
      } else {
        return self.set_error_kind("TypeError", "Callback is not a function")
      }
      if data.length == 0 && args.length() < 2 {
        return self.set_error_kind(
          "TypeError", "Reduce of empty array with no initial value",
        )
      }
      let mut accumulator : JSValue = Undefined
      let mut start_idx = 0
      if args.length() > 1 {
        accumulator = args[1]
        start_idx = data.length - 1
      } else {
        accumulator = typedarray_get_element_jsvalue(data, data.length - 1)
        start_idx = data.length - 2
      }
      for i = start_idx; i >= 0; i = i - 1 {
        let val = typedarray_get_element_jsvalue(data, i)
        accumulator = self.call_function(callback, Undefined, [
          accumulator,
          val,
          JSValue::Number(i.to_double()),
          this_arg,
        ])
      }
      accumulator
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.every(callback, thisArg?)
fn JSInterpreter::typedarray_every(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let callback = if args.length() > 0 {
        args[0]
      } else {
        return self.set_error_kind("TypeError", "Callback is not a function")
      }
      let this_for_callback = if args.length() > 1 {
        args[1]
      } else {
        Undefined
      }
      for i = 0; i < data.length; i = i + 1 {
        let val = typedarray_get_element_jsvalue(data, i)
        let result = self.call_function(callback, this_for_callback, [
          val,
          Number(i.to_double()),
          this_arg,
        ])
        if not(result.to_boolean()) {
          return Bool(false)
        }
      }
      Bool(true)
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.some(callback, thisArg?)
fn JSInterpreter::typedarray_some(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let callback = if args.length() > 0 {
        args[0]
      } else {
        return self.set_error_kind("TypeError", "Callback is not a function")
      }
      let this_for_callback = if args.length() > 1 {
        args[1]
      } else {
        Undefined
      }
      for i = 0; i < data.length; i = i + 1 {
        let val = typedarray_get_element_jsvalue(data, i)
        let result = self.call_function(callback, this_for_callback, [
          val,
          Number(i.to_double()),
          this_arg,
        ])
        if result.to_boolean() {
          return Bool(true)
        }
      }
      Bool(false)
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.find(callback, thisArg?)
fn JSInterpreter::typedarray_find(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let callback = if args.length() > 0 {
        args[0]
      } else {
        return self.set_error_kind("TypeError", "Callback is not a function")
      }
      let this_for_callback = if args.length() > 1 {
        args[1]
      } else {
        Undefined
      }
      for i = 0; i < data.length; i = i + 1 {
        let val = typedarray_get_element_jsvalue(data, i)
        let result = self.call_function(callback, this_for_callback, [
          val,
          Number(i.to_double()),
          this_arg,
        ])
        if result.to_boolean() {
          return val
        }
      }
      Undefined
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.findIndex(callback, thisArg?)
fn JSInterpreter::typedarray_find_index(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let callback = if args.length() > 0 {
        args[0]
      } else {
        return self.set_error_kind("TypeError", "Callback is not a function")
      }
      let this_for_callback = if args.length() > 1 {
        args[1]
      } else {
        Undefined
      }
      for i = 0; i < data.length; i = i + 1 {
        let val = typedarray_get_element_jsvalue(data, i)
        let result = self.call_function(callback, this_for_callback, [
          val,
          Number(i.to_double()),
          this_arg,
        ])
        if result.to_boolean() {
          return Number(i.to_double())
        }
      }
      Number(-1.0)
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.indexOf(searchElement, fromIndex?)
fn JSInterpreter::typedarray_index_of(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let search = if args.length() > 0 {
        args[0].to_number()
      } else {
        0.0 / 0.0
      }
      let from_arg = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
      let start = if from_arg < 0 {
        let s = data.length + from_arg
        if s < 0 {
          0
        } else {
          s
        }
      } else {
        from_arg
      }
      for i = start; i < data.length; i = i + 1 {
        let val = typedarray_get_element(data, i)
        if val == search {
          return Number(i.to_double())
        }
      }
      Number(-1.0)
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.lastIndexOf(searchElement, fromIndex?)
fn JSInterpreter::typedarray_last_index_of(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let search = if args.length() > 0 {
        args[0].to_number()
      } else {
        0.0 / 0.0
      }
      let from_arg = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        data.length - 1
      }
      let start = if from_arg < 0 {
        data.length + from_arg
      } else if from_arg >= data.length {
        data.length - 1
      } else {
        from_arg
      }
      for i = start; i >= 0; i = i - 1 {
        let val = typedarray_get_element(data, i)
        if val == search {
          return Number(i.to_double())
        }
      }
      Number(-1.0)
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.includes(searchElement, fromIndex?)
fn JSInterpreter::typedarray_includes(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let search = if args.length() > 0 {
        args[0].to_number()
      } else {
        0.0 / 0.0
      }
      let from_arg = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
      let start = if from_arg < 0 {
        let s = data.length + from_arg
        if s < 0 {
          0
        } else {
          s
        }
      } else {
        from_arg
      }
      for i = start; i < data.length; i = i + 1 {
        let val = typedarray_get_element(data, i)
        // includes uses SameValueZero, which treats NaN === NaN
        if val == search || (val.is_nan() && search.is_nan()) {
          return Bool(true)
        }
      }
      Bool(false)
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.join(separator?)
fn JSInterpreter::typedarray_join(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let sep = if args.length() > 0 && not(args[0].is_undefined()) {
        args[0].to_js_string()
      } else {
        ","
      }
      let parts : Array[String] = []
      for i = 0; i < data.length; i = i + 1 {
        let val = typedarray_get_element(data, i)
        parts.push(val.to_string())
      }
      String(parts.join(sep))
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.reverse()
fn JSInterpreter::typedarray_reverse(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  let _ = args
  match get_typedarray_data(this_arg) {
    Some(data) => {
      if data.buffer.detached {
        return self.set_error_kind("TypeError", "Buffer is detached")
      }
      let len = data.length
      for i = 0; i < len / 2; i = i + 1 {
        let j = len - 1 - i
        let a = typedarray_get_element(data, i)
        let b = typedarray_get_element(data, j)
        typedarray_set_element(data, i, b)
        typedarray_set_element(data, j, a)
      }
      this_arg
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.sort(compareFn?)
fn JSInterpreter::typedarray_sort(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      if data.buffer.detached {
        return self.set_error_kind("TypeError", "Buffer is detached")
      }
      let compare_fn = if args.length() > 0 && args[0].is_function() {
        Some(args[0])
      } else {
        None
      }
      // Extract to array for sorting
      let arr : Array[Double] = []
      for i = 0; i < data.length; i = i + 1 {
        arr.push(typedarray_get_element(data, i))
      }
      // Simple insertion sort (good enough for small arrays)
      for i = 1; i < arr.length(); i = i + 1 {
        let key = arr[i]
        let mut j = i - 1
        while j >= 0 {
          let cmp = match compare_fn {
            Some(fn_) => {
              let result = self.call_function(fn_, Undefined, [
                Number(arr[j]),
                Number(key),
              ])
              result.to_number()
            }
            None =>
              // Default numeric comparison
              if arr[j].is_nan() && key.is_nan() {
                0.0
              } else if arr[j].is_nan() {
                1.0 // NaN goes to end
              } else if key.is_nan() {
                -1.0
              } else {
                arr[j] - key
              }
          }
          if cmp > 0.0 {
            arr[j + 1] = arr[j]
            j = j - 1
          } else {
            break
          }
        }
        arr[j + 1] = key
      }
      // Write back
      for i = 0; i < arr.length(); i = i + 1 {
        typedarray_set_element(data, i, arr[i])
      }
      this_arg
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.at(index)
fn JSInterpreter::typedarray_at(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let index_arg = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      let index = if index_arg < 0 {
        data.length + index_arg
      } else {
        index_arg
      }
      if index < 0 || index >= data.length {
        return Undefined
      }
      Number(typedarray_get_element(data, index))
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.keys() - returns iterator over indices
fn JSInterpreter::typedarray_keys(
  self : JSInterpreter,
  this_arg : JSValue,
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let iter = self.new_object()
      let _ = js_set_prop(iter, "__iter_type", String("TypedArrayKeys"))
      let _ = js_set_prop(iter, "__iter_source", this_arg)
      let _ = js_set_prop(iter, "__iter_index", Number(0.0))
      let _ = js_set_prop(
        iter,
        "__iter_length",
        Number(data.length.to_double()),
      )
      let _ = js_set_prop(
        iter,
        "next",
        self.make_native("TypedArrayIterator.next"),
      )
      iter
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.values() - returns iterator over values
fn JSInterpreter::typedarray_values(
  self : JSInterpreter,
  this_arg : JSValue,
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let iter = self.new_object()
      let _ = js_set_prop(iter, "__iter_type", String("TypedArrayValues"))
      let _ = js_set_prop(iter, "__iter_source", this_arg)
      let _ = js_set_prop(iter, "__iter_index", Number(0.0))
      let _ = js_set_prop(
        iter,
        "__iter_length",
        Number(data.length.to_double()),
      )
      let _ = js_set_prop(
        iter,
        "next",
        self.make_native("TypedArrayIterator.next"),
      )
      iter
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.entries() - returns iterator over [index, value] pairs
fn JSInterpreter::typedarray_entries(
  self : JSInterpreter,
  this_arg : JSValue,
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let iter = self.new_object()
      let _ = js_set_prop(iter, "__iter_type", String("TypedArrayEntries"))
      let _ = js_set_prop(iter, "__iter_source", this_arg)
      let _ = js_set_prop(iter, "__iter_index", Number(0.0))
      let _ = js_set_prop(
        iter,
        "__iter_length",
        Number(data.length.to_double()),
      )
      let _ = js_set_prop(
        iter,
        "next",
        self.make_native("TypedArrayIterator.next"),
      )
      iter
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

// === DataView implementation ===

///|
/// Create a DataView
fn JSInterpreter::create_dataview(
  self : JSInterpreter,
  args : Array[JSValue],
) -> JSValue {
  if args.length() == 0 {
    return self.set_error_kind("TypeError", "DataView requires ArrayBuffer")
  }
  let buffer = args[0]
  if not(is_arraybuffer(buffer)) {
    return self.set_error_kind(
      "TypeError", "First argument must be an ArrayBuffer",
    )
  }
  match get_arraybuffer_data(buffer) {
    Some(buf) => {
      if buf.detached {
        return self.set_error_kind("TypeError", "ArrayBuffer is detached")
      }
      let buffer_byte_length = buf.data.length()
      let byte_offset = if args.length() > 1 {
        args[1].to_number().to_int()
      } else {
        0
      }
      if byte_offset < 0 || byte_offset > buffer_byte_length {
        return self.set_error_kind("RangeError", "Invalid byte offset")
      }
      let byte_length = if args.length() > 2 && not(args[2].is_undefined()) {
        let len = args[2].to_number().to_int()
        if len < 0 || byte_offset + len > buffer_byte_length {
          return self.set_error_kind("RangeError", "Invalid byte length")
        }
        len
      } else {
        buffer_byte_length - byte_offset
      }
      let dv_obj = self.new_object()
      let dv_proto = js_get_prop(self.global_env.get("DataView"), "prototype")
      let _ = js_set_prop(dv_obj, "__proto__", dv_proto)
      let _ = js_set_prop(dv_obj, "__class", String("DataView"))
      let _ = js_set_prop(dv_obj, "__dv_buffer_id", Number(buf.id.to_double()))
      let _ = js_set_prop(dv_obj, "buffer", buffer)
      let _ = js_set_prop(dv_obj, "byteOffset", Number(byte_offset.to_double()))
      let _ = js_set_prop(dv_obj, "byteLength", Number(byte_length.to_double()))
      dv_obj
    }
    None => self.set_error_kind("TypeError", "Invalid ArrayBuffer")
  }
}

///|
/// DataView getter methods
fn JSInterpreter::dataview_get(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
  type_name : String,
) -> JSValue {
  if not(is_dataview(this_arg)) {
    return self.set_error_kind("TypeError", "Not a DataView")
  }
  let buf_id = match js_get_prop(this_arg, "__dv_buffer_id") {
    Number(id) => id.to_int()
    _ => return self.set_error_kind("TypeError", "Invalid DataView")
  }
  match get_bytebuffer(buf_id) {
    Some(buf) => {
      if buf.detached {
        return self.set_error_kind("TypeError", "ArrayBuffer is detached")
      }
      let dv_offset = match js_get_prop(this_arg, "byteOffset") {
        Number(n) => n.to_int()
        _ => 0
      }
      let dv_byte_length = match js_get_prop(this_arg, "byteLength") {
        Number(n) => n.to_int()
        _ => 0
      }
      let byte_offset = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      let little_endian = if args.length() > 1 {
        args[1].to_boolean()
      } else {
        false
      }
      let element_size = match type_name {
        "Int8" | "Uint8" => 1
        "Int16" | "Uint16" => 2
        "Int32" | "Uint32" | "Float32" => 4
        "Float64" => 8
        _ => return self.set_error_kind("TypeError", "Unknown type")
      }
      if byte_offset < 0 || byte_offset + element_size > dv_byte_length {
        return self.set_error_kind("RangeError", "Offset is outside the bounds")
      }
      let abs_offset = dv_offset + byte_offset
      let value = match type_name {
        "Int8" => read_int8(buf, abs_offset).to_double()
        "Uint8" => read_uint8(buf, abs_offset).to_double()
        "Int16" =>
          if little_endian {
            read_int16_le(buf, abs_offset).to_double()
          } else {
            read_int16_be(buf, abs_offset).to_double()
          }
        "Uint16" =>
          if little_endian {
            read_uint16_le(buf, abs_offset).to_double()
          } else {
            read_uint16_be(buf, abs_offset).to_double()
          }
        "Int32" =>
          if little_endian {
            read_int32_le(buf, abs_offset).to_double()
          } else {
            read_int32_be(buf, abs_offset).to_double()
          }
        "Uint32" =>
          if little_endian {
            read_uint32_le(buf, abs_offset).to_double()
          } else {
            read_uint32_be(buf, abs_offset).to_double()
          }
        "Float32" =>
          if little_endian {
            read_float32_le(buf, abs_offset)
          } else {
            read_float32_be(buf, abs_offset)
          }
        "Float64" =>
          if little_endian {
            read_float64_le(buf, abs_offset)
          } else {
            read_float64_be(buf, abs_offset)
          }
        _ => return self.set_error_kind("TypeError", "Unknown type")
      }
      Number(value)
    }
    None => self.set_error_kind("TypeError", "Invalid ArrayBuffer")
  }
}

///|
/// DataView setter methods
fn JSInterpreter::dataview_set(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
  type_name : String,
) -> JSValue {
  if not(is_dataview(this_arg)) {
    return self.set_error_kind("TypeError", "Not a DataView")
  }
  let buf_id = match js_get_prop(this_arg, "__dv_buffer_id") {
    Number(id) => id.to_int()
    _ => return self.set_error_kind("TypeError", "Invalid DataView")
  }
  match get_bytebuffer(buf_id) {
    Some(buf) => {
      if buf.detached {
        return self.set_error_kind("TypeError", "ArrayBuffer is detached")
      }
      let dv_offset = match js_get_prop(this_arg, "byteOffset") {
        Number(n) => n.to_int()
        _ => 0
      }
      let dv_byte_length = match js_get_prop(this_arg, "byteLength") {
        Number(n) => n.to_int()
        _ => 0
      }
      let byte_offset = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      let value = if args.length() > 1 { args[1].to_number() } else { 0.0 }
      let little_endian = if args.length() > 2 {
        args[2].to_boolean()
      } else {
        false
      }
      let element_size = match type_name {
        "Int8" | "Uint8" => 1
        "Int16" | "Uint16" => 2
        "Int32" | "Uint32" | "Float32" => 4
        "Float64" => 8
        _ => return self.set_error_kind("TypeError", "Unknown type")
      }
      if byte_offset < 0 || byte_offset + element_size > dv_byte_length {
        return self.set_error_kind("RangeError", "Offset is outside the bounds")
      }
      let abs_offset = dv_offset + byte_offset
      match type_name {
        "Int8" | "Uint8" => write_uint8(buf, abs_offset, value.to_int())
        "Int16" | "Uint16" =>
          if little_endian {
            write_uint16_le(buf, abs_offset, value.to_int())
          } else {
            write_uint16_be(buf, abs_offset, value.to_int())
          }
        "Int32" | "Uint32" =>
          if little_endian {
            write_uint32_le(buf, abs_offset, value.to_int())
          } else {
            write_uint32_be(buf, abs_offset, value.to_int())
          }
        "Float32" =>
          if little_endian {
            write_float32_le(buf, abs_offset, value)
          } else {
            write_float32_be(buf, abs_offset, value)
          }
        "Float64" =>
          if little_endian {
            write_float64_le(buf, abs_offset, value)
          } else {
            write_float64_be(buf, abs_offset, value)
          }
        _ => return self.set_error_kind("TypeError", "Unknown type")
      }
      Undefined
    }
    None => self.set_error_kind("TypeError", "Invalid ArrayBuffer")
  }
}

///|
/// TypedArray.prototype.toLocaleString()
fn JSInterpreter::typedarray_to_locale_string(
  self : JSInterpreter,
  this_arg : JSValue,
  _args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      let parts : Array[String] = []
      for i = 0; i < data.length; i = i + 1 {
        let val = typedarray_get_element_jsvalue(data, i)
        // Call toLocaleString on each element
        let to_locale = js_get_prop(val, "toLocaleString")
        let str = match to_locale {
          Function(_) => self.call_function(to_locale, val, []).to_js_string()
          _ => val.to_js_string()
        }
        parts.push(str)
      }
      String(parts.join(","))
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.findLast(predicate, thisArg?)
fn JSInterpreter::typedarray_find_last(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      if args.length() == 0 {
        return self.set_error_kind("TypeError", "Missing callback function")
      }
      let callback = args[0]
      let this_for_callback = if args.length() > 1 {
        args[1]
      } else {
        Undefined
      }
      for i = data.length - 1; i >= 0; i = i - 1 {
        let val = typedarray_get_element_jsvalue(data, i)
        let result = self.call_function(callback, this_for_callback, [
          val,
          Number(i.to_double()),
          this_arg,
        ])
        if result.to_boolean() {
          return val
        }
      }
      Undefined
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.findLastIndex(predicate, thisArg?)
fn JSInterpreter::typedarray_find_last_index(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      if args.length() == 0 {
        return self.set_error_kind("TypeError", "Missing callback function")
      }
      let callback = args[0]
      let this_for_callback = if args.length() > 1 {
        args[1]
      } else {
        Undefined
      }
      for i = data.length - 1; i >= 0; i = i - 1 {
        let val = typedarray_get_element_jsvalue(data, i)
        let result = self.call_function(callback, this_for_callback, [
          val,
          Number(i.to_double()),
          this_arg,
        ])
        if result.to_boolean() {
          return Number(i.to_double())
        }
      }
      Number(-1.0)
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.with(index, value)
fn JSInterpreter::typedarray_with(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      if data.buffer.detached {
        return self.set_error_kind("TypeError", "ArrayBuffer is detached")
      }
      let index_arg = if args.length() > 0 {
        args[0].to_number().to_int()
      } else {
        0
      }
      let index = if index_arg < 0 {
        data.length + index_arg
      } else {
        index_arg
      }
      if index < 0 || index >= data.length {
        return self.set_error_kind("RangeError", "Invalid index")
      }
      let value = if args.length() > 1 { args[1] } else { Undefined }
      // Create a new TypedArray of the same type
      let ctor = js_get_prop(this_arg, "constructor")
      let new_ta = self.call_function(ctor, Undefined, [
        Number(data.length.to_double()),
      ])
      match get_typedarray_data(new_ta) {
        Some(new_data) => {
          // Copy all elements
          for i = 0; i < data.length; i = i + 1 {
            if i == index {
              typedarray_set_element_jsvalue(new_data, i, value)
            } else {
              let val = typedarray_get_element_jsvalue(data, i)
              typedarray_set_element_jsvalue(new_data, i, val)
            }
          }
          new_ta
        }
        None => self.set_error_kind("TypeError", "Failed to create TypedArray")
      }
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.toReversed()
fn JSInterpreter::typedarray_to_reversed(
  self : JSInterpreter,
  this_arg : JSValue,
  _args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      if data.buffer.detached {
        return self.set_error_kind("TypeError", "ArrayBuffer is detached")
      }
      // Create a new TypedArray of the same type
      let ctor = js_get_prop(this_arg, "constructor")
      let new_ta = self.call_function(ctor, Undefined, [
        Number(data.length.to_double()),
      ])
      match get_typedarray_data(new_ta) {
        Some(new_data) => {
          // Copy in reverse order
          for i = 0; i < data.length; i = i + 1 {
            let val = typedarray_get_element_jsvalue(data, data.length - 1 - i)
            typedarray_set_element_jsvalue(new_data, i, val)
          }
          new_ta
        }
        None => self.set_error_kind("TypeError", "Failed to create TypedArray")
      }
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}

///|
/// TypedArray.prototype.toSorted(compareFn?)
fn JSInterpreter::typedarray_to_sorted(
  self : JSInterpreter,
  this_arg : JSValue,
  args : Array[JSValue],
) -> JSValue {
  match get_typedarray_data(this_arg) {
    Some(data) => {
      if data.buffer.detached {
        return self.set_error_kind("TypeError", "ArrayBuffer is detached")
      }
      // Create a new TypedArray of the same type
      let ctor = js_get_prop(this_arg, "constructor")
      let new_ta = self.call_function(ctor, Undefined, [
        Number(data.length.to_double()),
      ])
      match get_typedarray_data(new_ta) {
        Some(new_data) => {
          // Copy elements
          for i = 0; i < data.length; i = i + 1 {
            let val = typedarray_get_element_jsvalue(data, i)
            typedarray_set_element_jsvalue(new_data, i, val)
          }
          // Sort the new array
          self.typedarray_sort(new_ta, args)
        }
        None => self.set_error_kind("TypeError", "Failed to create TypedArray")
      }
    }
    None => self.set_error_kind("TypeError", "Not a TypedArray")
  }
}
