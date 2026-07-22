fn script_target() -> @sut.ScriptTarget {
  @sut.ScriptTarget::ES2024
}

fn[A, B] test_unsafe_cast(value : A) -> B = "%identity"

fn rename_identifier(identifier : @sut.Identifier) -> @sut.Node {
  let text : String = test_unsafe_cast(identifier.escapedText)
  if text == "value" {
    test_unsafe_cast(@sut.get_factory().createIdentifier("renamed"))
  } else {
    test_unsafe_cast(identifier)
  }
}

fn visit_node(node : @sut.Node, context : @sut.TransformationContext) -> @sut.Node {
  match node.asIdentifier() {
    Some(identifier) => rename_identifier(identifier)
    None => {
      let visitor = fn(child : @sut.Node) {
        visit_node(child, context)
      }
      @sut.visitEachChild(node, visitor, Some(context))
    }
  }
}

fn transformer_factory(
  context : @sut.TransformationContext
) -> (@sut.SourceFile) -> @sut.SourceFile {
  fn(source_file) {
    match visit_node(test_unsafe_cast(source_file), context).asSourceFile() {
      Some(source_file) => source_file
      None => abort("expected transformer result to remain a SourceFile")
    }
  }
}

fn main {
  let source = @sut.createSourceFile(
    "input.ts",
    "const value = 1; console.log(value);",
    script_target(),
    Some(true),
    None,
  )
  let transformed = @sut.transform(
    source,
    [transformer_factory],
    None,
  )
  let source_file = match transformed.transformed[0].asSourceFile() {
    Some(source_file) => source_file
    None => abort("expected transformed node to be a SourceFile")
  }
  transformed.dispose()
  let printed = @sut.createPrinter(None, None).printFile(source_file)
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
