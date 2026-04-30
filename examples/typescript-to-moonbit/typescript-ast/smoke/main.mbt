extern "js" fn latest_script_target() -> @sut.JSValue =
  #| () => globalThis.__tsmbt_ast_adapter.latestScriptTarget()

extern "js" fn identifier_text(identifier : @sut.Identifier) -> String =
  #| (identifier) => globalThis.__tsmbt_ast_adapter.identifierText(identifier)

extern "js" fn create_identifier(text : String) -> @sut.Identifier =
  #| (text) => globalThis.__tsmbt_ast_adapter.createIdentifier(text)

extern "js" fn first_transformed_source_file(
  result : @sut.TransformationResult
) -> @sut.SourceFile =
  #| (result) => globalThis.__tsmbt_ast_adapter.firstTransformedSourceFile(result)

extern "js" fn print_source_file(source_file : @sut.SourceFile) -> String =
  #| (sourceFile) => globalThis.__tsmbt_ast_adapter.printSourceFile(sourceFile)

fn rename_identifier(identifier : @sut.Identifier) -> @sut.Node {
  if identifier_text(identifier) == "value" {
    @sut.unsafeCast(create_identifier("renamed"))
  } else {
    @sut.unsafeCast(identifier)
  }
}

fn visit_node(node : @sut.Node, context : @sut.TransformationContext) -> @sut.Node {
  match node.asIdentifier() {
    Some(identifier) => rename_identifier(identifier)
    None => {
      let visitor : @sut.Visitor = @sut.unsafeCast(fn(child : @sut.Node) {
        visit_node(child, context)
      })
      @sut.unsafeCast(
        @sut.visitEachChild(
          @sut.unsafeCast(node),
          visitor,
          Some(context),
        ),
      )
    }
  }
}

fn transformer_factory(
  context : @sut.TransformationContext
) -> (@sut.SourceFile) -> @sut.SourceFile {
  fn(source_file) {
    @sut.unsafeCast(visit_node(@sut.unsafeCast(source_file), context))
  }
}

fn main {
  let source = @sut.createSourceFile(
    "input.ts",
    "const value = 1; console.log(value);",
    latest_script_target(),
    Some(true),
    None,
  )
  let transformed = @sut.transform(
    @sut.unsafeCast(source),
    [@sut.unsafeCast(transformer_factory)],
    None,
  )
  let printed = print_source_file(first_transformed_source_file(transformed))
  if !printed.contains("const renamed = 1") {
    abort("expected MoonBit transformer to rename declaration identifier")
  }
  if !printed.contains("console.log(renamed)") {
    abort("expected MoonBit transformer to rename identifier usage")
  }
  if printed.contains("value") {
    abort("unexpected old identifier in transformed output")
  }
}
