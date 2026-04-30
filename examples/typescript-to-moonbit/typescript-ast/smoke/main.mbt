extern "js" fn latest_script_target() -> @sut.JSValue =
  #| () => globalThis.__tsmbt_ast_adapter.latestScriptTarget()

extern "js" fn make_moonbit_transformer(
  visit : (@sut.Node, @sut.TransformationContext) -> @sut.Node
) -> @sut.TransformerFactory =
  #| (visit) => globalThis.__tsmbt_ast_adapter.makeMoonBitTransformer(visit)

extern "js" fn node_to_t(node : @sut.Node) -> @sut.T =
  #| (node) => node

extern "js" fn t_to_node(node : @sut.T) -> @sut.Node =
  #| (node) => node

extern "js" fn node_to_identifier(node : @sut.Node) -> @sut.Identifier =
  #| (node) => node

extern "js" fn identifier_to_node(identifier : @sut.Identifier) -> @sut.Node =
  #| (identifier) => identifier

extern "js" fn visitor_from_moonbit(visit : (@sut.Node) -> @sut.Node) -> @sut.Visitor =
  #| (visit) => visit

extern "js" fn identifier_text(identifier : @sut.Identifier) -> String =
  #| (identifier) => globalThis.__tsmbt_ast_adapter.identifierText(identifier)

extern "js" fn create_identifier(text : String) -> @sut.Identifier =
  #| (text) => globalThis.__tsmbt_ast_adapter.createIdentifier(text)

extern "js" fn source_file_as_js_value(source_file : @sut.SourceFile) -> @sut.JSValue =
  #| (sourceFile) => globalThis.__tsmbt_ast_adapter.sourceFileAsJsValue(sourceFile)

extern "js" fn first_transformed_source_file(
  result : @sut.TransformationResult
) -> @sut.SourceFile =
  #| (result) => globalThis.__tsmbt_ast_adapter.firstTransformedSourceFile(result)

extern "js" fn print_source_file(source_file : @sut.SourceFile) -> String =
  #| (sourceFile) => globalThis.__tsmbt_ast_adapter.printSourceFile(sourceFile)

fn rename_identifier(identifier : @sut.Identifier) -> @sut.Identifier {
  if identifier_text(identifier) == "value" {
    create_identifier("renamed")
  } else {
    identifier
  }
}

fn visit_node(node : @sut.Node, context : @sut.TransformationContext) -> @sut.Node {
  if @sut.isIdentifier(node) {
    identifier_to_node(rename_identifier(node_to_identifier(node)))
  } else {
    t_to_node(
      @sut.visitEachChild(
        node_to_t(node),
        visitor_from_moonbit(fn(child) { visit_node(child, context) }),
        Some(context),
      ),
    )
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
    source_file_as_js_value(source),
    [make_moonbit_transformer(visit_node)],
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
