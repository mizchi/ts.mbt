///|
// fn main {
//   let args = @env.args()
//   if args.length() < 2 {
//     print_usage()
//     return
//   }

//   let command = args[1]
//   match command {
//     "run" => {
//       if args.length() < 3 {
//         println("Error: no file specified")
//         return
//       }
//       let file_path = args[2]
//       run_ts_file(file_path) @
//     }
//     "test262" => {
//       if args.length() < 3 {
//         println("Error: no test directory or file specified")
//         return
//       }
//       let test_path = args[2]
//       run_test262(test_path) @
//     }
//     _ => {
//       println("Unknown command: \{command}")
//       print_usage()
//     }
//   }
// }

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
  let interp = JSInterpreter::new()
  let result = interp.run(content) catch {
    e => {
      println("Error: \{e}")
      return
    }
  }
  println(result.to_js_string())
}

///|
async fn run_test262(test_path : String) -> Unit {
  // Check if it's a file or directory
  let content = @fs.read_file(test_path).text() catch {
    e => {
      println("Error reading test file: \{e}")
      return
    }
  }
  let interp = JSInterpreter::new()

  // TODO: Add test262 harness globals
  // $DONOTEVALUATE, $262 object, assert, etc.

  let result = interp.run(content) catch {
    e => {
      println("Error: \{e}")
      return
    }
  }

  // Test passed if no error
  println("PASS")
}
