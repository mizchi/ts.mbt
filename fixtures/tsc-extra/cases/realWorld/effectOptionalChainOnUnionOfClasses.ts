// @strict: true
// @target: esnext

// effect `SchemaAST`: `ast.context?.isOptional` over a union of classes whose
// shared member is `Context | undefined`.

export interface Context { readonly isOptional: boolean }
interface ASTNode { readonly context: Context | undefined; readonly _tag: string }
class A implements ASTNode { readonly _tag = "A"; readonly context: Context | undefined = undefined }
class B implements ASTNode { readonly _tag = "B"; readonly context: Context | undefined = undefined }
type AST = A | B
function okNested(ast: AST): boolean { return ast.context?.isOptional ?? false }
