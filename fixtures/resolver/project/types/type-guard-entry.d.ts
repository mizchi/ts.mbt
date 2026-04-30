export interface Node {
  kind: number;
}

export interface Identifier {
  text: string;
}

export type Visitor = (node: Node) => Node;

export declare function isIdentifier(node: Node): node is Identifier;
export declare function visitEachChild(node: Node, visitor: Visitor): Node;
