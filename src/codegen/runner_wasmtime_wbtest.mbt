// Wasmtime runner using C FFI

///|
/// FFI declarations for wasmtime runner
#borrow(bytes)
extern "C" fn write_temp_wasm(bytes : Bytes, len : Int) -> Int64 = "write_temp_wasm"

#borrow(func_name, args)
extern "C" fn run_wasmtime_ffi(
  path : Int64,
  func_name : Bytes,
  args : FixedArray[Double],
  argc : Int
) -> Int64 = "run_wasmtime"

extern "C" fn cleanup_temp_wasm(path : Int64) = "cleanup_temp_wasm"

extern "C" fn free_result(result : Int64) = "free_result"

///|
/// Convert C string pointer to MoonBit String
fn cstr_to_string(ptr : Int64) -> String {
  if ptr == 0 {
    return ""
  }
  // Read bytes from C string until null terminator
  let bytes : Array[Byte] = []
  for i = 0; ; i = i + 1 {
    let b = load_byte(ptr, i)
    if b == b'\x00' {
      break
    }
    bytes.push(b)
  }
  // Convert bytes to string (assuming ASCII)
  let chars : Array[Char] = []
  for b in bytes {
    chars.push(b.to_int().unsafe_to_char())
  }
  String::from_array(chars)
}

///|
/// Load a byte from memory at ptr + offset
extern "C" fn load_byte(ptr : Int64, offset : Int) -> Byte = "moonbit_load_byte"

///|
/// Run wasm with wasmtime CLI
pub fn run_with_wasmtime(
  wasm_bytes : Bytes,
  func_name : String,
  args : Array[Double]
) -> RunResult {
  // Write wasm to temp file
  let path = write_temp_wasm(wasm_bytes, wasm_bytes.length())
  if path == 0 {
    return RunResult::Error("Failed to write temp file")
  }

  // Convert func_name to bytes
  let func_bytes = Bytes::from_iter(func_name.iter().map(fn(c) { c.to_int().to_byte() }))
  let func_with_null = Bytes::from_array(func_bytes.to_array() + [b'\x00'])

  // Convert args to fixed array
  let fixed_args : FixedArray[Double] = FixedArray::make(args.length(), 0.0)
  for i, arg in args {
    fixed_args[i] = arg
  }

  // Run wasmtime
  let result_ptr = run_wasmtime_ffi(path, func_with_null, fixed_args, args.length())

  // Cleanup temp file
  cleanup_temp_wasm(path)

  if result_ptr == 0 {
    return RunResult::Error("Wasmtime execution failed")
  }

  // Parse result
  let result_str = cstr_to_string(result_ptr)
  free_result(result_ptr)

  // Try to parse as number
  try {
    let v = @strconv.parse_double(result_str)
    RunResult::F64(v)
  } catch {
    _ => {
      // Check if it's an error message
      if result_str.contains("error") || result_str.contains("Error") {
        RunResult::Error(result_str)
      } else {
        // Try parsing as int
        try {
          let i = @strconv.parse_int(result_str)
          RunResult::I32(i)
        } catch {
          _ => RunResult::Error("Cannot parse result: \{result_str}")
        }
      }
    }
  }
}

