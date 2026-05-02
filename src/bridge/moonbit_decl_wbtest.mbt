///|
fn count_occurrences_in_decl_output(haystack : String, needle : String) -> Int {
  let mut count = 0
  for _ in haystack.split(needle) {
    count += 1
  }
  count - 1
}

///|
test "bridge: specialize TypeScript AST ergonomic API types" {
  assert_eq(
    decl_specialize_generated_api_param_type(
      "createSourceFile",
      "languageVersionOrOptions",
      2,
      @ast.TsType::Union([
        @ast.TsType::Named("ScriptTarget"),
        @ast.TsType::Named("CreateSourceFileOptions"),
      ]),
    ),
    @ast.TsType::Named("ScriptTarget"),
  )
  assert_eq(
    decl_specialize_generated_api_param_type(
      "transform",
      "source",
      0,
      @ast.TsType::Union([
        @ast.TsType::Named("Node"),
        @ast.TsType::Array(@ast.TsType::Named("Node")),
      ]),
    ),
    @ast.TsType::Named("SourceFile"),
  )
  assert_eq(
    decl_specialize_generated_api_param_type(
      "visitEachChild",
      "visitor",
      1,
      @ast.TsType::Named("Visitor"),
    ),
    @ast.TsType::Func([@ast.TsType::Named("Node")], @ast.TsType::Named("Node")),
  )
  assert_eq(
    decl_specialize_generated_api_param_type(
      "transform",
      "transformers",
      1,
      @ast.TsType::Array(@ast.TsType::Named("TransformerFactory")),
    ),
    @ast.TsType::Array(
      @ast.TsType::Func(
        [@ast.TsType::Named("TransformationContext")],
        @ast.TsType::Func(
          [@ast.TsType::Named("SourceFile")],
          @ast.TsType::Named("SourceFile"),
        ),
      ),
    ),
  )
  assert_eq(
    decl_specialize_generated_api_return_type(
      "visitEachChild",
      @ast.TsType::Any,
    ),
    @ast.TsType::Named("Node"),
  )
  assert_eq(
    decl_specialize_generated_api_param_type(
      "writeFileSync",
      "data",
      1,
      @ast.TsType::Union([
        @ast.TsType::String_,
        @ast.TsType::Named("NodeJS_ArrayBufferView"),
      ]),
    ),
    @ast.TsType::String_,
  )
  assert_eq(
    decl_specialize_generated_api_param_type(
      "writeFile.__promisify__",
      "data",
      1,
      @ast.TsType::Union([
        @ast.TsType::String_,
        @ast.TsType::Named("NonSharedBuffer"),
      ]),
    ),
    @ast.TsType::String_,
  )
  assert_eq(
    decl_specialize_generated_api_param_type(
      "cp",
      "source",
      0,
      @ast.TsType::Union([@ast.TsType::String_, @ast.TsType::Named("URL")]),
    ),
    @ast.TsType::String_,
  )
  assert_eq(
    decl_specialize_generated_api_param_type(
      "globSync",
      "pattern",
      0,
      @ast.TsType::Union([
        @ast.TsType::String_,
        @ast.TsType::Array(@ast.TsType::String_),
      ]),
    ),
    @ast.TsType::String_,
  )
  assert_eq(
    decl_specialize_generated_api_param_type(
      "createReadStream",
      "options",
      1,
      @ast.TsType::Union([
        @ast.TsType::Named("BufferEncoding"),
        @ast.TsType::Named("ReadStreamOptions"),
        @ast.TsType::Undefined,
      ]),
    ),
    @ast.TsType::Named("ReadStreamOptions"),
  )
  assert_eq(
    decl_specialize_generated_class_property_type(
      "ReadStream",
      "path",
      @ast.TsType::Union([@ast.TsType::String_, @ast.TsType::Named("Buffer")]),
    ),
    @ast.TsType::Named("PathLike"),
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "StatSyncFn",
      "<call>",
      @ast.TsType::Func(
        [@ast.TsType::Named("PathLike"), @ast.TsType::Any],
        @ast.TsType::Named("Stats"),
      ),
    ),
    @ast.TsType::Func(
      [
        @ast.TsType::Named("PathLike"),
        @ast.TsType::Union([
          @ast.TsType::Named("StatSyncOptions"),
          @ast.TsType::Undefined,
        ]),
      ],
      @ast.TsType::Named("Stats"),
    ),
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "ReadStreamEventMap",
      "data",
      @ast.TsType::Tuple([@ast.TsType::Any]),
    ),
    @ast.TsType::Array(@ast.TsType::Named("ReadStreamEventPayload")),
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "FSWatcherEventMap",
      "change",
      @ast.TsType::Tuple([
        @ast.TsType::String_,
        @ast.TsType::Union([
          @ast.TsType::String_,
          @ast.TsType::Named("NonSharedBuffer"),
        ]),
      ]),
    ),
    @ast.TsType::Array(@ast.TsType::Named("FSWatcherChangeEventPayload")),
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "WatchOptions",
      "encoding",
      @ast.TsType::Union([
        @ast.TsType::Named("BufferEncoding"),
        @ast.TsType::Literal("buffer"),
        @ast.TsType::Undefined,
      ]),
    ),
    @ast.TsType::Union([@ast.TsType::String_, @ast.TsType::Undefined]),
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "UserInfo",
      "username",
      @ast.TsType::Any,
    ),
    @ast.TsType::String_,
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "UserInfo",
      "shell",
      @ast.TsType::Union([@ast.TsType::Any, @ast.TsType::Null]),
    ),
    @ast.TsType::Union([@ast.TsType::String_, @ast.TsType::Undefined]),
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "UserInfoOptions",
      "encoding",
      @ast.TsType::Any,
    ),
    @ast.TsType::Union([
      @ast.TsType::Named("BufferEncoding"),
      @ast.TsType::Undefined,
    ]),
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "UrlObject",
      "port",
      @ast.TsType::Any,
    ),
    @ast.TsType::Union([@ast.TsType::String_, @ast.TsType::Undefined]),
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "URLPattern",
      "exec",
      @ast.TsType::Func(
        [@ast.TsType::Named("URLPatternInput"), @ast.TsType::Any],
        @ast.TsType::Named("URLPatternResult"),
      ),
    ),
    @ast.TsType::Func(
      [
        @ast.TsType::Named("URLPatternInput"),
        @ast.TsType::Union([@ast.TsType::String_, @ast.TsType::Undefined]),
      ],
      @ast.TsType::Named("URLPatternResult"),
    ),
  )
  assert_eq(
    decl_specialize_generated_class_method_param_type(
      "ReadStream",
      "on",
      "listener",
      1,
      @ast.TsType::Func([@ast.TsType::Any], @ast.TsType::Void),
    ),
    @ast.TsType::Func(
      [@ast.TsType::Named("ReadStreamEventPayload")],
      @ast.TsType::Void,
    ),
  )
  assert_eq(
    decl_specialize_generated_class_method_param_type(
      "URLPattern",
      "exec",
      "baseURL",
      1,
      @ast.TsType::Any,
    ),
    @ast.TsType::Union([@ast.TsType::String_, @ast.TsType::Undefined]),
  )
  assert_eq(
    decl_specialize_generated_api_param_type(
      "fileURLToPath",
      "url",
      0,
      @ast.TsType::Any,
    ),
    @ast.TsType::String_,
  )
  assert_eq(
    decl_specialize_generated_api_param_type(
      "isUtf8",
      "input",
      0,
      @ast.TsType::Any,
    ),
    @ast.TsType::Named("Uint8Array"),
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "CipherGCM",
      "setAAD",
      @ast.TsType::Func(
        [@ast.TsType::Named("NodeJS_ArrayBufferView"), @ast.TsType::Any],
        @ast.TsType::Named("This"),
      ),
    ),
    @ast.TsType::Func(
      [
        @ast.TsType::Named("NodeJS_ArrayBufferView"),
        @ast.TsType::Union([
          @ast.TsType::Named("CipherAADOptions"),
          @ast.TsType::Undefined,
        ]),
      ],
      @ast.TsType::Named("This"),
    ),
  )
  assert_eq(
    decl_specialize_generated_api_param_type(
      "createHmac",
      "key",
      1,
      @ast.TsType::Any,
    ),
    @ast.TsType::Named("CipherKey"),
  )
  assert_eq(
    decl_specialize_generated_api_param_type(
      "hash",
      "options",
      2,
      @ast.TsType::Any,
    ),
    @ast.TsType::Union([
      @ast.TsType::Named("OneShotDigestOptionsWithStringEncoding"),
      @ast.TsType::Undefined,
    ]),
  )
  assert_eq(
    decl_specialize_generated_class_method_param_type(
      "SubtleCrypto",
      "digest",
      "algorithm",
      0,
      @ast.TsType::Any,
    ),
    @ast.TsType::Named("AlgorithmIdentifier"),
  )
  assert_eq(
    decl_specialize_generated_class_method_param_type(
      "Sign",
      "sign",
      "privateKey",
      0,
      @ast.TsType::Any,
    ),
    @ast.TsType::Named("KeyLike"),
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "PrivateKeyExportOptions",
      "passphrase",
      @ast.TsType::Any,
    ),
    @ast.TsType::Union([
      @ast.TsType::Named("BinaryLike"),
      @ast.TsType::Undefined,
    ]),
  )
  assert_eq(
    decl_specialize_generated_api_param_type(
      "generateKeyPair",
      "callback",
      2,
      @ast.TsType::Func(
        [
          @ast.TsType::Union([
            @ast.TsType::Named("Error_"),
            @ast.TsType::Undefined,
          ]),
          @ast.TsType::Any,
          @ast.TsType::Any,
        ],
        @ast.TsType::Void,
      ),
    ),
    @ast.TsType::Func(
      [
        @ast.TsType::Union([
          @ast.TsType::Named("Error_"),
          @ast.TsType::Undefined,
        ]),
        @ast.TsType::Named("KeyObject"),
        @ast.TsType::Named("KeyObject"),
      ],
      @ast.TsType::Void,
    ),
  )
  assert_true(
    decl_func_should_skip_broad_node_wrapper({
      name: "generatePrimeSync_number_generate_prime_options",
      params: [],
      return_type: @ast.TsType::Any,
      body: { stmts: [] },
      is_generator: false,
      is_async: false,
    }),
  )
  assert_eq(
    decl_specialize_generated_class_method_param_type(
      "Hono",
      "get",
      "arg0",
      0,
      @ast.TsType::Any,
    ),
    @ast.TsType::String_,
  )
  assert_eq(
    decl_specialize_generated_class_method_param_type(
      "Hono",
      "get",
      "arg1",
      1,
      @ast.TsType::Any,
    ),
    @ast.TsType::Func(
      [@ast.TsType::Named("Context")],
      @ast.TsType::Named("Response"),
    ),
  )
  assert_eq(
    decl_specialize_generated_class_method_param_type(
      "Context",
      "text",
      "arg0",
      0,
      @ast.TsType::Any,
    ),
    @ast.TsType::String_,
  )
  assert_eq(
    decl_specialize_generated_class_method_return_type(
      "Context",
      "text",
      @ast.TsType::Any,
    ),
    @ast.TsType::Named("Response"),
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "Environment",
      "viteEnvironment",
      @ast.TsType::Any,
    ),
    @ast.TsType::Union([@ast.TsType::String_, @ast.TsType::Undefined]),
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "Environment",
      "setup",
      @ast.TsType::Func(
        [@ast.TsType::Any, @ast.TsType::Named("StringRecordOfAny")],
        @ast.TsType::Named("Awaitable"),
      ),
    ),
    @ast.TsType::Func(
      [@ast.TsType::Any, @ast.TsType::Named("StringRecordOfAny")],
      @ast.TsType::Applied("Promise", [@ast.TsType::Named("EnvironmentReturn")]),
    ),
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "Environment",
      "setupVM",
      @ast.TsType::Func(
        [@ast.TsType::Named("StringRecordOfAny")],
        @ast.TsType::Named("Awaitable"),
      ),
    ),
    @ast.TsType::Union([
      @ast.TsType::Func(
        [@ast.TsType::Named("StringRecordOfAny")],
        @ast.TsType::Applied("Promise", [
          @ast.TsType::Named("VmEnvironmentReturn"),
        ]),
      ),
      @ast.TsType::Undefined,
    ]),
  )
  assert_eq(
    decl_specialize_generated_interface_field_type(
      "VmEnvironmentReturn",
      "getVmContext",
      @ast.TsType::Func([], @ast.TsType::Any),
    ),
    @ast.TsType::Func([], @ast.TsType::Named("StringRecordOfAny")),
  )
  assert_eq(
    decl_specialize_generated_value_type(
      "builtinEnvironments",
      @ast.TsType::Any,
    ),
    @ast.TsType::Named("BuiltinEnvironments"),
  )
  assert_eq(
    decl_specialize_generated_value_type("encode", @ast.TsType::Any),
    @ast.TsType::Func(
      [
        @ast.TsType::Union([
          @ast.TsType::Named("ParsedUrlQueryInput"),
          @ast.TsType::Undefined,
        ]),
        @ast.TsType::Union([@ast.TsType::String_, @ast.TsType::Undefined]),
        @ast.TsType::Union([@ast.TsType::String_, @ast.TsType::Undefined]),
        @ast.TsType::Union([
          @ast.TsType::Named("StringifyOptions"),
          @ast.TsType::Undefined,
        ]),
      ],
      @ast.TsType::String_,
    ),
  )
  assert_eq(
    decl_specialize_generated_value_type(
      "constants",
      @ast.TsType::Object([
        (@ast.TsType::Literal("MAX_LENGTH"), @ast.TsType::Number),
      ]),
    ),
    @ast.TsType::Named("Constants"),
  )
  assert_eq(
    decl_specialize_generated_class_method_return_type(
      "WriteStream",
      "rawListeners",
      @ast.TsType::Array(
        @ast.TsType::Func([@ast.TsType::Any], @ast.TsType::Void),
      ),
    ),
    @ast.TsType::Array(
      @ast.TsType::Func(
        [@ast.TsType::Named("WriteStreamEventPayload")],
        @ast.TsType::Void,
      ),
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations specializes node fs residual payloads" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/node-fs-specialization-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("/// atimeNs : Int64"))
  assert_true(actual.contains("/// mtimeNs : Int64"))
  assert_true(actual.contains("/// ctimeNs : Int64"))
  assert_true(actual.contains("/// birthtimeNs : Int64"))
  assert_false(actual.contains("atimeNs : JSValue"))
  assert_true(actual.contains("declare pub type FSWatcherChangeEventPayload"))
  assert_true(
    actual.contains("/// change : Array[FSWatcherChangeEventPayload]"),
  )
  assert_false(actual.contains("/// change : Array[JSValue]"))
  assert_true(actual.contains("/// encoding : String?"))
  assert_false(actual.contains("/// encoding : JSValue?"))
}

///|
async test "bridge: emit MoonBit declarations names inline object promise results" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/inline-object-promise-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type ReadPromisifyResult"))
  assert_true(actual.contains("bytesRead : Double"))
  assert_true(actual.contains("buffer : NodeJS_ArrayBufferView"))
  assert_true(
    actual.contains(
      "declare pub fn readPromisify(fd : Double, buffer : NodeJS_ArrayBufferView) -> @js.Promise[ReadPromisifyResult]",
    ),
  )
  assert_false(
    actual.contains(
      "readPromisify(fd : Double, buffer : NodeJS_ArrayBufferView) -> @js.Promise[JSValue]",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations from type export surface" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  let expected =
    #|///|
    #|/// Generated from TypeScript declarations by mizchi/ts/parser.
    #|/// Complex or unsupported TypeScript types are widened to JSValue.
    #|
    #|///|
    #|/// TS interface PublicPoint
    #|/// x : Double
    #|/// y : Double
    #|declare pub type PublicPoint
    #|
    #|///|
    #|declare pub fn render(point : PublicPoint) -> PublicPoint
  assert_eq(actual, expected)
}

///|
async test "bridge: emit MoonBit declarations resolves local import reexports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/import-reexport-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type PublicPoint"))
  assert_true(
    actual.contains("declare pub fn render(point : PublicPoint) -> PublicPoint"),
  )
}

///|
async test "bridge: emit MoonBit declarations keeps namespace exports as JSValue notes" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/ns-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type JSValue"))
  assert_true(
    actual.contains(
      "Unsupported export shapes: namespace export is widened to JSValue.",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations keeps ambiguous exports as JSValue notes" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/ambiguous-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type JSValue"))
  assert_true(
    actual.contains(
      "Unsupported export Shared: ambiguous re-export surface is widened to JSValue",
    ),
  )
  assert_true(
    actual.contains("fixtures/resolver/project/types/ambiguous-a.d.ts"),
  )
  assert_true(
    actual.contains("fixtures/resolver/project/types/ambiguous-b.d.ts"),
  )
}

///|
async test "bridge: emit MoonBit declarations diagnoses unsupported enum-like exports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/unsupported-enum-like-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_false(actual.contains("declare pub type JSValue"))
  assert_true(
    actual.contains(
      "Unsupported export MixedMode: mixed string/number enum cannot be lowered safely.",
    ),
  )
  assert_true(
    actual.contains(
      "Unsupported export ComputedKind: enum member Dynamic has a non-literal computed value.",
    ),
  )
  assert_true(
    actual.contains(
      "Unsupported export DuplicateMode: duplicate enum literal values cannot be converted back safely.",
    ),
  )
  assert_true(
    actual.contains(
      "Unsupported export MixedAlias: mixed string/number literal union cannot be lowered safely.",
    ),
  )
  assert_true(
    actual.contains(
      "Unsupported export FloatAlias: numeric literal union contains a non-integer literal.",
    ),
  )
  assert_true(
    actual.contains(
      "Unsupported export BigAlias: bigint literal union cannot be lowered safely.",
    ),
  )
  assert_false(actual.contains("enum MixedMode"))
  assert_false(actual.contains("enum ComputedKind"))
  assert_false(actual.contains("enum DuplicateMode"))
}

///|
async test "bridge: emit MoonBit declarations names anonymous literal unions" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/anonymous-literal-union-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("pub(all) enum ButtonOptionsVariant {"))
  assert_true(actual.contains("pub(all) enum RenderButtonVariant {"))
  assert_true(actual.contains("pub(all) enum RenderButtonReturn {"))
  assert_true(actual.contains("declare pub type ButtonOptions"))
  assert_true(actual.contains("/// variant : ButtonOptionsVariant"))
  assert_true(
    actual.contains(
      "declare pub fn renderButton(variant : RenderButtonVariant) -> RenderButtonReturn",
    ),
  )
  assert_false(actual.contains("anonymous literal union in public surface"))
}

///|
async test "bridge: emit MoonBit declarations names anonymous string literal unions with unsafe case names" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/anonymous-string-literal-union-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("pub(all) enum OrderedListPropsType {"))
  assert_true(actual.contains("pub(all) enum OrderedListPropsSetModeArg0 {"))
  assert_true(actual.contains("pub(all) enum SetListTypeType {"))
  assert_true(actual.contains("pub(all) enum SetListTypeReturn {"))
  assert_true(actual.contains("/// type : OrderedListPropsType?"))
  assert_true(
    actual.contains("/// setMode : (OrderedListPropsSetModeArg0) -> Unit"),
  )
  assert_true(
    actual.contains(
      "declare pub fn setListType(type_ : SetListTypeType) -> SetListTypeReturn",
    ),
  )
  assert_false(actual.contains("anonymous literal union in public surface"))
}

///|
async test "bridge: emit MoonBit declarations for exported classes" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/class-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type Counter"))
  assert_true(
    actual.contains("declare pub fn new_counter(initial : Double) -> Counter"),
  )
  assert_true(
    actual.contains(
      "declare pub fn counter_inc(self : Counter, delta : Double) -> Double",
    ),
  )
  assert_true(
    actual.contains("declare pub fn counter_from(seed : Double) -> Counter"),
  )
}

///|
async test "bridge: emit MoonBit declarations for abstract exported classes without constructor" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/abstract-class-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type Shape"))
  assert_true(
    actual.contains("declare pub fn shape_area(self : Shape) -> Double"),
  )
  assert_false(actual.contains("declare pub fn new_shape("))
}

///|
async test "bridge: emit MoonBit declarations for exported class properties" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/class-property-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    actual.contains(
      "declare pub fn get_counter_state_current(self : CounterState) -> Double",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn get_counter_state_label(self : CounterState) -> String",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn set_counter_state_label(self : CounterState, value : String) -> Unit",
    ),
  )
  assert_true(
    actual.contains("declare pub fn get_counter_state_version() -> String"),
  )
  assert_true(
    actual.contains("declare pub fn get_counter_state_step() -> Double"),
  )
  assert_true(
    actual.contains(
      "declare pub fn set_counter_state_step(value : Double) -> Unit",
    ),
  )
  assert_false(actual.contains("set_counter_state_current"))
  assert_false(actual.contains("set_counter_state_version"))
}

///|
async test "bridge: emit MoonBit declarations with unresolved external library types as opaque types" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/external-lib-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type User"))
  assert_true(actual.contains("declare pub type Result"))
  assert_true(actual.contains("declare pub type ResultAsync"))
  assert_true(
    actual.contains("declare pub fn parseUser(input : String) -> Result"),
  )
  assert_true(
    actual.contains("declare pub fn fetchUser(id : String) -> ResultAsync"),
  )
}

///|
async test "bridge: emit MoonBit declarations with resolved bare-package types as opaque types" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/resolved-lib-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type User"))
  assert_true(actual.contains("declare pub type PkgTypesValue"))
  assert_true(
    actual.contains("declare pub fn parseUser(input : String) -> PkgTypesValue"),
  )
}

///|
async test "bridge: emit MoonBit declarations with minimal opaque bare-package imports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/opaque-package-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type PkgTypesValue"))
  assert_true(
    actual.contains(
      "declare pub fn parseValue(input : String) -> PkgTypesValue",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations with resolved mixed imports as opaque types" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/resolved-mixed-lib-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type User"))
  assert_true(actual.contains("declare pub type PkgResult"))
  assert_true(actual.contains("declare pub type PkgResultAsync"))
  assert_true(
    actual.contains("declare pub fn parseUser(input : String) -> PkgResult"),
  )
  assert_true(
    actual.contains("declare pub fn fetchUser(id : String) -> PkgResultAsync"),
  )
}

///|
async test "bridge: emit MoonBit declarations with resolved generic library imports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/resolved-generic-lib-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type User"))
  assert_true(actual.contains("declare pub type PkgResult"))
  assert_true(actual.contains("declare pub type PkgResultAsync"))
  assert_true(
    actual.contains("declare pub fn parseUser(input : String) -> PkgResult"),
  )
  assert_true(
    actual.contains("declare pub fn fetchUser(id : String) -> PkgResultAsync"),
  )
}

///|
async test "bridge: emit MoonBit declarations with resolved symlinked library imports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/resolved-symlink-lib-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type User"))
  assert_true(actual.contains("declare pub type PkgSymlinkResult"))
  assert_true(actual.contains("declare pub type PkgSymlinkResultAsync"))
  assert_true(
    actual.contains(
      "declare pub fn parseUser(input : String) -> PkgSymlinkResult",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn fetchUser(id : String) -> PkgSymlinkResultAsync",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations with neverthrow-like package imports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/neverthrow-like-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type User"))
  assert_true(actual.contains("declare pub type Result"))
  assert_true(actual.contains("declare pub type ResultAsync"))
  assert_true(
    actual.contains("declare pub fn parseUser(input : String) -> Result"),
  )
  assert_true(
    actual.contains("declare pub fn fetchUser(id : String) -> ResultAsync"),
  )
}

///|
async test "bridge: emit MoonBit declarations through package exports subpath" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/subpath-package-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type FeatureOptions"))
  assert_true(actual.contains("declare pub type FeatureResult"))
  assert_true(
    actual.contains(
      "declare pub fn executeFeature(options : FeatureOptions) -> FeatureResult",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations through package exports wildcard subpath" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/pattern-package-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type PatternOptions"))
  assert_true(actual.contains("declare pub type PatternResult"))
  assert_true(
    actual.contains(
      "declare pub fn createPattern(options : PatternOptions) -> PatternResult",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations through package exports array fallback wildcard subpath" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/pattern-array-package-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type ArrayPatternOptions"))
  assert_true(actual.contains("declare pub type ArrayPatternResult"))
  assert_true(
    actual.contains(
      "declare pub fn createArrayPattern(options : ArrayPatternOptions) -> ArrayPatternResult",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations through package barrel reexports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/barrel-package-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type BarrelOptions"))
  assert_true(actual.contains("declare pub type BarrelResult"))
  assert_true(
    actual.contains(
      "declare pub fn createBarrel(options : BarrelOptions) -> BarrelResult",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations with node-like ambient qualified types" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/node-like-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type RuntimeConfig"))
  assert_true(actual.contains("declare pub type NodeRunner"))
  assert_true(actual.contains("declare pub type NodeJS_ProcessEnv"))
  assert_true(
    actual.contains(
      "declare pub fn hasEnv(env : NodeJS_ProcessEnv, key : String) -> Bool",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations collapse overloads by generated binding name" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/overload-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_eq(
    count_occurrences_in_decl_output(actual, "declare pub fn makeCounter("),
    1,
  )
  assert_true(
    actual.contains(
      "declare pub fn makeCounter_number(value : Double) -> Counter",
    ),
  )
  assert_eq(
    count_occurrences_in_decl_output(actual, "declare pub fn counter_value"),
    1,
  )
  assert_eq(
    count_occurrences_in_decl_output(actual, "declare pub fn chooseConcrete"),
    1,
  )
  assert_true(
    actual.contains("declare pub fn chooseConcrete(value : String) -> Double"),
  )
  assert_false(
    actual.contains("declare pub fn chooseConcrete(value : JSValue) -> JSValue"),
  )
}

///|
async test "bridge: emit MoonBit declarations skip wider same-param overload wrappers" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/encoding-overload-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    actual.contains(
      "declare pub fn readlinkSync(path : String, options : EncodingOption?) -> String",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn readlinkSync_string_buffer_encoding_option(path : String, options : BufferEncodingOption) -> NonSharedBuffer",
    ),
  )
  assert_false(
    actual.contains(
      "declare pub fn readlinkSync_string_encoding_option_optional(path : String, options : EncodingOption?) -> JSValue",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations keeps narrow overload per arity" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/overload-arity-prune-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub fn fstatSync(fd : Double) -> Stats"))
  assert_true(
    actual.contains(
      "declare pub fn fstatSync_number_stat_options_optional(fd : Double, options : StatOptions?) -> Stats",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn fstatSync_number_stat_options(fd : Double, options : StatOptions) -> BigIntStats",
    ),
  )
  assert_false(
    actual.contains(
      "declare pub fn fstatSync_number_stat_options_optional(fd : Double, options : StatOptions?) -> JSValue",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations specializes node fs readFile and glob overloads" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/node-fs-readfile-glob-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type ReadFileBufferOptions"))
  assert_true(
    actual.contains(
      "declare pub fn readFileSync(path : PathOrFileDescriptor, options : ReadFileBufferOptions?) -> NonSharedBuffer",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn readFileSync_path_or_file_descriptor_buffer_encoding(path : PathOrFileDescriptor, options : BufferEncoding) -> String",
    ),
  )
  assert_false(
    actual.contains(
      "declare pub fn readFileSync(path : PathOrFileDescriptor, options : JSValue?) -> NonSharedBuffer",
    ),
  )
  assert_false(
    actual.contains(
      "declare pub fn readFileSync_path_or_file_descriptor_buffer_encoding_optional",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn readFilePromisify(path : PathOrFileDescriptor, options : ReadFileBufferOptions?) -> @js.Promise[NonSharedBuffer]",
    ),
  )
  assert_false(
    actual.contains(
      "declare pub fn readFilePromisify(path : PathOrFileDescriptor, options : JSValue?) -> @js.Promise[NonSharedBuffer]",
    ),
  )
  assert_true(actual.contains("/// filter : ((String, String) -> Bool)?"))
  assert_false(actual.contains("/// filter : ((String, String) -> JSValue)?"))
  assert_true(actual.contains("/// cwd : String?"))
  assert_true(actual.contains("/// exclude : Array[String]?"))
  assert_false(actual.contains("/// cwd : JSValue?"))
  assert_false(actual.contains("/// exclude : JSValue?"))
  assert_true(
    actual.contains(
      "declare pub fn globSync(pattern : String) -> Array[String]",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn globSync_string_glob_options_with_file_types(pattern : String, options : GlobOptionsWithFileTypes) -> Array[Dirent]",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn globSync_string_glob_options_without_file_types(pattern : String, options : GlobOptionsWithoutFileTypes) -> Array[String]",
    ),
  )
  assert_false(
    actual.contains(
      "declare pub fn globSync_string_glob_options(pattern : String, options : GlobOptions) -> JSValue",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations ignore unresolved bare-package reexports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/unresolved-bare-reexport-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type LocalOptions"))
  assert_true(
    actual.contains(
      "declare pub fn createOptions(value : String) -> LocalOptions",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations tolerate transitive ts implementation modules" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/transitive-impl-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type PublicStyle"))
  assert_true(actual.contains("declare pub type WebviewConfig"))
  assert_true(
    actual.contains("declare pub fn createStyle(id : String) -> PublicStyle"),
  )
}

///|
async test "bridge: emit MoonBit declarations from runtime ts exported functions" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-function-entry.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type RuntimePoint"))
  assert_true(
    actual.contains(
      "declare pub fn scalePoint(point : RuntimePoint, factor : Double) -> RuntimePoint",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations from runtime tsx exported functions" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-component-entry.tsx",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type BadgeProps"))
  assert_true(actual.contains("declare pub type JSX_Element"))
  assert_true(
    actual.contains(
      "declare pub fn renderBadge(props : BadgeProps) -> JSX_Element",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations from runtime ts exported const arrow functions" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-arrow-entry.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type RuntimeArrowPoint"))
  assert_true(
    actual.contains(
      "declare pub fn scaleArrowPoint(point : RuntimeArrowPoint, factor : Double) -> RuntimeArrowPoint",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations from runtime ts exported untyped const arrow functions" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-untyped-arrow-entry.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    actual.contains("declare pub fn doubleValue(value : Double) -> Double"),
  )
  assert_true(
    actual.contains("declare pub fn greetValue(name : String) -> String"),
  )
}

///|
async test "bridge: emit MoonBit declarations from runtime ts function reexports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-function-reexport-entry.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type RuntimePoint"))
  assert_true(
    actual.contains(
      "declare pub fn scalePoint(point : RuntimePoint, factor : Double) -> RuntimePoint",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations from runtime imported class exports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-import-reexport-class-entry.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type RuntimeImported"))
  assert_true(
    actual.contains(
      "declare pub fn new_runtime_imported(_options : RuntimeImportedOptions) -> RuntimeImported",
    ),
  )
  assert_true(actual.contains("declare pub type RuntimeImportedOptions"))
}

///|
async test "bridge: emit MoonBit declarations from runtime imported class barrel exports" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-import-reexport-class-barrel-entry.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type RuntimeImported"))
  assert_true(
    actual.contains(
      "declare pub fn new_runtime_imported(_options : RuntimeImportedOptions) -> RuntimeImported",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations from semicolonless runtime export type alias entry" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-semicolonless-export-type-alias-entry.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub fn greet(name : Name) -> Name"))
}

///|
async test "bridge: emit MoonBit declarations from runtime default exported functions" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-default-function-entry.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    actual.contains("declare pub fn default(label : String) -> String"),
  )
}

///|
async test "bridge: emit MoonBit declarations from runtime default exported classes" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/runtime-default-class-entry.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type Default"))
  assert_true(
    actual.contains("declare pub fn new_default(initial : Double) -> Default"),
  )
  assert_true(
    actual.contains(
      "declare pub fn default_inc(self : Default, delta : Double) -> Double",
    ),
  )
  assert_true(
    actual.contains("declare pub fn default_from(seed : Double) -> Default"),
  )
}

///|
async test "bridge: emit MoonBit declarations from namespace export assignment" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/export-equals-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type JSValue"))
  assert_true(actual.contains("declare pub fn get_default() -> JSValue"))
}

///|
async test "bridge: emit MoonBit declarations from CJS export-equals namespace members" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/cjs-export-equals-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub fn get_version() -> String"))
  assert_true(
    actual.contains("declare pub fn format(label : String) -> String"),
  )
  assert_true(actual.contains("declare pub fn get_default() -> JSValue"))
  assert_false(actual.contains("Unsupported export toolkit"))
}

///|
async test "bridge: emit MoonBit declarations from export-as-namespace assignment" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type Context"))
  assert_true(
    actual.contains(
      "declare pub fn createContext(defaultValue : JSValue) -> Context",
    ),
  )
  assert_true(actual.contains("declare pub fn get_default() -> JSValue"))
}

///|
async test "bridge: emit MoonBit declarations from export-as-namespace ambient members" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-ambient-members-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub fn get_version() -> String"))
  assert_true(actual.contains("declare pub type Component"))
  assert_true(
    actual.contains("declare pub fn useContext(context : Context) -> JSValue"),
  )
}

///|
async test "bridge: omit unique symbol marker value exports from MoonBit declarations" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/unique-symbol-runtime-export-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub fn ok(value : Bool) -> Unit"))
  assert_false(actual.contains("kOptions"))
  assert_false(actual.contains("get_k_options"))
}

///|
async test "bridge: emit MoonBit declarations from exported runtime namespace members" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/exported-runtime-namespace-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type TaskOptions"))
  assert_true(actual.contains("declare pub fn task(input : String) -> String"))
  assert_true(
    actual.contains("declare pub fn taskExtra(input : String) -> String"),
  )
  assert_true(actual.contains("declare pub fn get_constants_read() -> Double"))
  assert_false(actual.contains("Unsupported export task"))
  assert_false(actual.contains("Unsupported export constants"))
}

///|
async test "bridge: emit MoonBit declarations from declaration-merged namespaces" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/declaration-merge-namespace-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub fn make(input : String) -> String"))
  assert_true(actual.contains("declare pub type MakeOptions"))
  assert_false(actual.contains("declare pub type Options"))
  assert_true(actual.contains("declare pub fn get_make_version() -> String"))
  assert_true(
    actual.contains(
      "declare pub fn makeWithOptions(input : String, options : MakeOptions) -> String",
    ),
  )
  assert_true(actual.contains("declare pub type Tool"))
  assert_true(actual.contains("declare pub type ToolConfig"))
  assert_true(actual.contains("declare pub fn get_tool_version() -> String"))
  assert_true(
    actual.contains("declare pub fn toolParse(input : String) -> Tool"),
  )
  assert_true(actual.contains("declare pub type Settings"))
  assert_true(actual.contains("declare pub fn get_settings() -> Settings"))
  assert_true(actual.contains("declare pub type SettingsMeta"))
  assert_true(
    actual.contains("declare pub fn get_settings_default_mode() -> String"),
  )
  assert_true(
    actual.contains(
      "declare pub fn settingsNormalize(input : String) -> String",
    ),
  )
  assert_false(actual.contains("Unsupported export make"))
  assert_false(actual.contains("Unsupported export Tool"))
  assert_false(actual.contains("Unsupported export settings"))
}

///|
async test "bridge: emit MoonBit declarations from Promise-returning APIs" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/promise-return-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    actual.contains(
      "declare pub fn fetchLabel(id : String) -> @js.Promise[String]",
    ),
  )
  assert_true(
    actual.contains("declare pub fn fetchCount() -> @js.Promise[Double]"),
  )
  assert_false(actual.contains("declare pub type Promise"))
}

///|
async test "bridge: emit MoonBit declarations from callback APIs with synthetic callback types" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/callback-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type EmitEventListenerCallback"))
  assert_true(actual.contains("declare pub type MaybeEmitListenerCallback"))
  assert_true(
    actual.contains(
      "declare pub fn emitEvent(label : String, count : Double, listener : EmitEventListenerCallback) -> String",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn maybeEmit(label : String, listener : MaybeEmitListenerCallback?) -> String",
    ),
  )
  assert_false(actual.contains("declare pub type JSValue"))
  assert_false(actual.contains("Unsupported export emitEvent"))
  assert_false(actual.contains("Unsupported export maybeEmit"))
}

///|
async test "bridge: emit MoonBit declarations from export-as-namespace hook tuple members" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-hook-tuple-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type UseStateResult"))
  assert_true(actual.contains("/// state : JSValue"))
  assert_true(actual.contains("/// setState : Dispatch"))
  assert_true(actual.contains("declare pub type UseReducerResult"))
  assert_true(actual.contains("/// dispatch : ActionDispatch"))
  assert_true(actual.contains("declare pub type UseTransitionResult"))
  assert_true(actual.contains("/// isPending : Bool"))
  assert_true(actual.contains("/// startTransition : TransitionFunction"))
  assert_true(actual.contains("declare pub type UseOptimisticResult"))
  assert_true(actual.contains("/// state : State"))
  assert_true(actual.contains("declare pub type UseActionStateResult"))
  assert_true(actual.contains("/// isPending : Bool"))
  assert_true(
    actual.contains(
      "declare pub fn useState(initialState : JSValue) -> UseStateResult",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn useReducer(reducer : UseReducerReducerCallback, initialState : JSValue) -> UseReducerResult",
    ),
  )
  assert_true(
    actual.contains("declare pub fn useTransition() -> UseTransitionResult"),
  )
  assert_true(
    actual.contains(
      "declare pub fn useOptimistic(passthrough : State) -> UseOptimisticResult",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn useActionState(action : UseActionStateActionCallback, initialState : State, permalink : String?) -> UseActionStateResult",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations from export-as-namespace JSX namespace members" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-jsx-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type BadgeProps"))
  assert_true(actual.contains("declare pub type JsxElement"))
  assert_true(actual.contains("declare pub type JsxIntrinsicElements"))
  assert_true(actual.contains("declare pub type JsxLibraryManagedAttributes"))
  assert_true(
    actual.contains("declare pub fn createElement(tag : String) -> JsxElement"),
  )
}

///|
async test "bridge: emit MoonBit declarations from exported JSX namespace members" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/exported-jsx-namespace-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type BadgeProps"))
  assert_true(actual.contains("declare pub type JsxElement"))
  assert_true(actual.contains("declare pub type JsxIntrinsicElements"))
  assert_true(actual.contains("declare pub type JsxLibraryManagedAttributes"))
  assert_true(
    actual.contains(
      "declare pub fn jsx(tag : String, props : BadgeProps) -> JsxElement",
    ),
  )
  assert_false(actual.contains("declare pub fn get_jsx() ->"))
}

///|
async test "bridge: emit MoonBit declarations from export-as-namespace PropsWithChildren members" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-props-with-children-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_false(actual.contains("declare pub type ReactNode"))
  assert_true(actual.contains("declare pub type BadgePropsWithChildren"))
  assert_true(actual.contains("/// children : JSValue"))
  assert_true(
    actual.contains(
      "declare pub fn createBadge(props : BadgePropsWithChildren) -> BadgePropsWithChildren",
    ),
  )
  assert_false(actual.contains("declare pub type PropsWithChildren"))
}

///|
async test "bridge: emit MoonBit declarations from export-as-namespace ComponentProps members" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-component-props-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type BadgeProps"))
  assert_true(
    actual.contains(
      "declare pub fn createBadge(props : BadgeProps) -> BadgeProps",
    ),
  )
  assert_false(actual.contains("declare pub type ComponentProps"))
}

///|
async test "bridge: emit MoonBit declarations lowers Pick and Omit utility types" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/utility-pick-omit-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type User"))
  assert_true(actual.contains("/// readonly createdAt : String"))
  assert_true(actual.contains("declare pub type InlineMapped"))
  assert_true(actual.contains("/// id : String?"))
  assert_true(actual.contains("/// name : String?"))
  assert_true(actual.contains("declare pub type UserPickIdName"))
  assert_true(actual.contains("/// id : String"))
  assert_true(actual.contains("/// name : String"))
  assert_true(actual.contains("declare pub type UserPickIdActive"))
  assert_true(actual.contains("/// active : Bool?"))
  assert_true(actual.contains("declare pub type UserOmitAge"))
  assert_true(actual.contains("declare pub type UserOmitActive"))
  assert_true(actual.contains("declare pub type UserPartial"))
  assert_true(actual.contains("/// age : Double?"))
  assert_true(actual.contains("declare pub type UserReadonly"))
  assert_true(actual.contains("/// readonly name : String"))
  assert_true(actual.contains("declare pub type UserRequired"))
  assert_true(actual.contains("/// active : Bool"))
  assert_true(
    actual.contains(
      "declare pub fn pickUser(user : UserPickIdName) -> UserPickIdActive",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn omitUser(user : UserOmitAge) -> UserOmitActive",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn patchUser(user : UserPartial) -> UserPartial",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn readonlyUser(user : UserReadonly) -> UserReadonly",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn requiredUser(user : UserRequired) -> UserRequired",
    ),
  )
  assert_true(
    actual.contains("declare pub fn requireUser(id : String) -> User"),
  )
  assert_true(
    actual.contains("declare pub fn extractUser(user : User) -> User"),
  )
  assert_true(actual.contains("declare pub fn getCount() -> Double"))
  assert_true(actual.contains("/// TS interface GetArgsResult"))
  assert_true(actual.contains("/// _0 : String"))
  assert_true(actual.contains("/// _1 : Bool"))
  assert_true(actual.contains("declare pub fn getArgs() -> GetArgsResult"))
  assert_true(
    actual.contains("declare pub fn getStaticConditionalTrue() -> Double"),
  )
  assert_true(
    actual.contains("declare pub fn getStaticConditionalFalse() -> Bool"),
  )
  assert_true(actual.contains("declare pub fn getAwaitedName() -> String"))
  assert_true(
    actual.contains("declare pub fn getInferredPromiseName() -> String"),
  )
  assert_true(
    actual.contains("declare pub fn getGenericInferredPromiseName() -> String"),
  )
  assert_true(
    actual.contains("declare pub fn getInlineMapped() -> InlineMapped"),
  )
  assert_true(actual.contains("declare pub type StringRecordOfString"))
  assert_true(actual.contains("declare pub type StringRecordOfStringOrDouble"))
  assert_true(actual.contains("declare pub type StringRecordOfUser"))
  assert_true(
    actual.contains("declare pub fn getLabels() -> StringRecordOfString"),
  )
  assert_true(
    actual.contains(
      "declare pub fn setLabels(labels : StringRecordOfStringOrDouble) -> Unit",
    ),
  )
  assert_true(
    actual.contains("declare pub fn getUsersById() -> StringRecordOfUser"),
  )
  assert_true(actual.contains("declare pub type UtilityError"))
  assert_true(
    actual.contains(
      "declare pub fn new_utility_error(issues : Array[User]) -> UtilityError",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn get_utility_error_issues(self : UtilityError) -> Array[User]",
    ),
  )
  assert_false(actual.contains("declare pub type JSValue"))
  assert_false(actual.contains("declare pub type Pick"))
  assert_false(actual.contains("declare pub type Omit"))
  assert_false(actual.contains("declare pub type Record"))
  assert_false(actual.contains("declare pub type NonNullable"))
  assert_false(actual.contains("declare pub type Extract"))
  assert_false(actual.contains("declare pub type Exclude"))
  assert_false(actual.contains("declare pub type ReturnType"))
  assert_false(actual.contains("declare pub type Parameters"))
  assert_false(actual.contains("declare pub type Partial"))
  assert_false(actual.contains("declare pub type Readonly"))
  assert_false(actual.contains("declare pub type Required"))
  assert_false(actual.contains("declare pub type Awaited"))
  assert_false(actual.contains("declare pub type Promise"))
  assert_false(actual.contains("declare pub type UnwrapPromise"))
}

///|
async test "bridge: emit MoonBit declarations from export-as-namespace ComponentPropsWithoutRef members" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-component-props-without-ref-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type BadgeProps"))
  assert_true(
    actual.contains(
      "declare pub fn createBadge(props : BadgeProps) -> BadgeProps",
    ),
  )
  assert_false(actual.contains("declare pub type ComponentPropsWithoutRef"))
}

///|
async test "bridge: emit MoonBit declarations from export-as-namespace ComponentPropsWithRef members" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-component-props-with-ref-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type BadgePropsWithRef"))
  assert_true(actual.contains("declare pub type Ref"))
  assert_true(
    actual.contains(
      "declare pub fn createBadge(props : BadgePropsWithRef) -> BadgePropsWithRef",
    ),
  )
  assert_false(actual.contains("declare pub type ComponentPropsWithRef"))
}

///|
async test "bridge: emit MoonBit declarations from export-as-namespace nested PropsWithChildren members" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-nested-props-with-children-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type BadgePropsWithChildren"))
  assert_true(
    actual.contains(
      "declare pub fn createBadge(props : BadgePropsWithChildren) -> BadgePropsWithChildren",
    ),
  )
  assert_false(actual.contains("declare pub type PropsWithChildren"))
  assert_false(actual.contains("declare pub type ComponentPropsWithoutRef"))
}

///|
async test "bridge: emit MoonBit declarations from export-as-namespace PropsWithoutRef and PropsWithRef members" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-props-ref-alias-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type BadgeProps"))
  assert_true(actual.contains("declare pub type BadgePropsWithChildren"))
  assert_true(
    actual.contains("declare pub fn stripRef(props : BadgeProps) -> BadgeProps"),
  )
  assert_true(
    actual.contains("declare pub fn keepRef(props : BadgeProps) -> BadgeProps"),
  )
  assert_true(
    actual.contains(
      "declare pub fn nested(props : BadgePropsWithChildren) -> BadgePropsWithChildren",
    ),
  )
  assert_false(actual.contains("declare pub type PropsWithoutRef"))
  assert_false(actual.contains("declare pub type PropsWithRef"))
}

///|
async test "bridge: emit MoonBit declarations from export-as-namespace optional React-like fields" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-optional-react-fields-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type BadgeProps"))
  assert_true(actual.contains("/// label : String?"))
  assert_true(actual.contains("/// children : JSValue?"))
  assert_true(actual.contains("/// ref : Ref?"))
  assert_true(
    actual.contains(
      "declare pub fn renderBadge(props : BadgeProps) -> BadgeProps",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations from exported jsx-dev-runtime signatures" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/exported-jsx-dev-runtime-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type JSXSource"))
  assert_true(actual.contains("/// fileName : String?"))
  assert_true(actual.contains("/// lineNumber : Double?"))
  assert_true(actual.contains("/// columnNumber : Double?"))
  assert_true(
    actual.contains(
      "declare pub fn jsxDEV(type_ : ElementType, props : JSValue, key : Key?, isStatic : Bool, source : JSXSource?, self : JSValue?) -> ReactElement",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations from export-as-namespace inline PropsWithChildren members" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-inline-props-with-children-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type LabelCountPropsWithChildren"))
  assert_true(actual.contains("/// children : JSValue"))
  assert_true(
    actual.contains(
      "declare pub fn createBadge(props : LabelCountPropsWithChildren) -> LabelCountPropsWithChildren",
    ),
  )
  assert_false(actual.contains("declare pub type PropsWithChildren"))
}

///|
async test "bridge: emit MoonBit declarations sanitizes reserved exported function and parameter names" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/export-as-namespace-sanitize-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    actual.contains(
      "declare pub fn jsx(type_ : String, props : Props) -> ReactElement",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn use_(promise : @js.Promise[String]) -> String",
    ),
  )
  assert_true(
    actual.contains("declare pub fn forwardRef(component : JSValue) -> JSValue"),
  )
  assert_true(
    actual.contains(
      "declare pub fn useActionState(fn_ : JSValue, initialState : String, permalink : String) -> String",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn fragment(children : String) -> ReactElement",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn strictMode(children : String) -> ReactElement",
    ),
  )
  assert_false(actual.contains("declare pub fn Fragment("))
  assert_false(actual.contains("declare pub fn use("))
}

///|
async test "bridge: emit MoonBit declarations from imported object type alias members" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/hono-options-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type HonoOptions"))
  assert_true(actual.contains("/// strict : Bool?"))
  assert_true(actual.contains("/// bindings : JSValue?"))
  assert_true(actual.contains("declare pub type Hono"))
  assert_true(
    actual.contains("declare pub fn new_hono(options : HonoOptions?) -> Hono"),
  )
  assert_true(
    actual.contains("declare pub fn createApp(options : HonoOptions) -> Hono"),
  )
}

///|
async test "bridge: emit MoonBit declarations names literal unions" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/literal-union-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_false(actual.contains("declare pub type JSValue"))
  assert_true(actual.contains("pub(all) enum ButtonOptionsVariant"))
  assert_true(actual.contains("pub(all) enum RenderButtonVariant"))
  assert_true(actual.contains("pub(all) enum RenderButtonReturn"))
  assert_true(actual.contains("/// variant : ButtonOptionsVariant?"))
  assert_true(actual.contains("/// disabled : Bool?"))
  assert_true(
    actual.contains(
      "declare pub fn renderButton(variant : RenderButtonVariant, options : ButtonOptions?) -> RenderButtonReturn",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations from fixture React package surface" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/node_modules/react/index.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type FunctionComponent"))
  assert_true(actual.contains("declare pub type NamedExoticComponent"))
  assert_true(actual.contains("declare pub type ForwardRefExoticComponent"))
  assert_true(actual.contains("declare pub type MemoExoticComponent"))
  assert_true(
    actual.contains(
      "declare pub fn createElement(type_ : String, props : DOMAttributes?, children : Array[JSValue]) -> ReactElement",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn cloneElement(element : ReactElement, props : DOMAttributesPartial?, children : Array[JSValue]) -> ReactElement",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn forwardRef(render : ForwardRefRenderCallback) -> ForwardRefExoticComponent",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn memo(component : FunctionComponent, propsAreEqual : MemoPropsAreEqualCallback?) -> MemoExoticComponent",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn normalizeProps(props : ButtonHTMLAttributes) -> ButtonHTMLAttributes",
    ),
  )
  assert_true(
    actual.contains("declare pub fn useComponentRef(ref_ : Ref) -> Ref"),
  )
  assert_false(actual.contains("declare pub type ReactNode"))
  assert_false(actual.contains("props : JSValue?"))
}

///|
async test "bridge: emit MoonBit declarations from fixture React JSX runtime subpaths" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/node_modules/react/jsx-runtime.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type JsxElement"))
  assert_true(
    actual.contains(
      "declare pub fn jsx(type_ : String, props : ButtonHTMLAttributes, key : Key?) -> ReactElement",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn jsxs(type_ : String, props : ButtonHTMLAttributes, key : Key?) -> ReactElement",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations from fixture React JSX dev runtime subpath" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/node_modules/react/jsx-dev-runtime.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type JSXSource"))
  assert_true(
    actual.contains(
      "declare pub fn jsxDEV(type_ : ElementType, props : JSValue, key : Key?, isStatic : Bool, source : JSXSource?, self : JSValue?) -> ReactElement",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations from fixture Hono JSX package subpath" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/node_modules/hono/dist/types/jsx/index.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type JsxElement"))
  assert_true(actual.contains("declare pub type ButtonAttributes"))
  assert_true(
    actual.contains(
      "declare pub fn jsx(tag : String, props : ButtonAttributes) -> JsxElement",
    ),
  )
  assert_true(
    actual.contains(
      "declare pub fn memo(component : MemoComponentCallback) -> (JSValue) -> JsxElement",
    ),
  )
}

///|
async test "bridge: emit MoonBit declarations from import-equals export assignment" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/import-equals-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("declare pub type JSValue"))
  assert_true(actual.contains("declare pub fn get_default() -> JSValue"))
}

///|
async test "bridge: recursive type alias overload wrappers do not overflow" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/recursive-overload-alias-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(
    actual.contains("declare pub fn format(value : JSValue) -> Format"),
  )
  assert_true(
    actual.contains(
      "declare pub fn format_t_string_optional(value : JSValue, fallback : String?) -> Format",
    ),
  )
}

///|
async test "bridge: qualified React.ReactNode renders as opaque ReactNode in mbti" {
  let actual = emit_moonbit_decl_from_entry_path(
    "fixtures/resolver/project/types/qualified-react-node-entry.d.ts",
  ) catch {
    e => {
      match e {
        ReadError(msg) | ParseError(msg) | ResolveError(msg) =>
          fail("Emit error: \{msg}")
      }
      return
    }
  }
  assert_true(actual.contains("element : ReactNode?"))
  assert_true(actual.contains("errorElement : ReactNode?"))
  assert_false(actual.contains("element : JSValue?"))
  assert_false(actual.contains("element : @js.Any?"))
}
