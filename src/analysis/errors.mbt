// Error types and formatting for static analysis.

///|
/// Result type for analysis operations.
pub(all) enum AnalysisResult[T] {
  Ok(T, Array[AnalysisError]) // value and warnings
  Err(Array[AnalysisError]) // errors
} derive(Debug)

///|
/// Check if result is successful.
pub fn[T] AnalysisResult::is_ok(self : AnalysisResult[T]) -> Bool {
  match self {
    Ok(_, _) => true
    Err(_) => false
  }
}

///|
/// Get value from successful result.
pub fn[T] AnalysisResult::unwrap(self : AnalysisResult[T]) -> T {
  match self {
    Ok(v, _) => v
    Err(_) => abort("unwrap called on Err")
  }
}

///|
/// Get errors from result.
pub fn[T] AnalysisResult::get_errors(
  self : AnalysisResult[T],
) -> Array[AnalysisError] {
  match self {
    Ok(_, warnings) => warnings
    Err(errors) => errors
  }
}

///|
/// Format an error with source context.
pub fn format_error(error : AnalysisError, source : String) -> String {
  let kind_str = match error.kind {
    SyntaxError => "SyntaxError"
    ReferenceError => "ReferenceError"
    TypeError => "TypeError"
    UnsupportedFeature => "UnsupportedFeature"
    Warning => "Warning"
  }
  if error.loc.line == 0 {
    return "\{kind_str}: \{error.message}"
  }

  // Get the source line
  let lines = split_lines(source)
  let line_idx = error.loc.line - 1
  let source_line = if line_idx >= 0 && line_idx < lines.length() {
    lines[line_idx]
  } else {
    ""
  }

  // Build pointer line
  let pointer = build_pointer(error.loc.column)
  "\{kind_str}: \{error.message}\n  at line \{error.loc.line}, column \{error.loc.column}\n    \{source_line}\n    \{pointer}"
}

///|
/// Format all errors from a result.
pub fn format_errors(errors : Array[AnalysisError], source : String) -> String {
  let sb = StringBuilder::new()
  for i, err in errors {
    if i > 0 {
      sb.write_string("\n\n")
    }
    sb.write_string(format_error(err, source))
  }
  sb.to_string()
}

///|
fn split_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let current = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c == '\n'.to_int().to_uint16() {
      lines.push(current.to_string())
      current.reset()
    } else {
      current.write_string(c.to_int().unsafe_to_char().to_string())
    }
  }
  // Add last line if not empty
  let last = current.to_string()
  if last.length() > 0 || lines.length() == 0 {
    lines.push(last)
  }
  lines
}

///|
fn build_pointer(column : Int) -> String {
  let sb = StringBuilder::new()
  let mut i = 1
  while i < column {
    sb.write_char(' ')
    i += 1
  }
  sb.write_char('^')
  sb.to_string()
}

///|
/// Create a reference error for undefined variable.
pub fn make_reference_error(name : String, loc : SourceLoc) -> AnalysisError {
  { kind: ReferenceError, message: "\{name} is not defined", loc }
}

///|
/// Create a syntax error for duplicate declaration.
pub fn make_duplicate_decl_error(
  name : String,
  loc : SourceLoc,
) -> AnalysisError {
  {
    kind: SyntaxError,
    message: "Identifier '\{name}' has already been declared",
    loc,
  }
}

///|
/// Create a type error for const reassignment.
pub fn make_const_assign_error(name : String, loc : SourceLoc) -> AnalysisError {
  { kind: TypeError, message: "Assignment to constant variable '\{name}'", loc }
}

///|
/// Create a reference error for TDZ violation.
pub fn make_tdz_error(name : String, loc : SourceLoc) -> AnalysisError {
  {
    kind: ReferenceError,
    message: "Cannot access '\{name}' before initialization",
    loc,
  }
}
