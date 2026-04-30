import ts from "typescript";

export function latestScriptTarget() {
  return ts.ScriptTarget.Latest;
}

export function identifierText(identifier) {
  return identifier.text;
}

export function createIdentifier(text) {
  return ts.factory.createIdentifier(text);
}

export function firstTransformedSourceFile(result) {
  const sourceFile = result.transformed[0];
  result.dispose();
  return sourceFile;
}

export function printSourceFile(sourceFile) {
  return ts.createPrinter().printFile(sourceFile);
}
