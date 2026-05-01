export declare enum SyntaxKind {
  Unknown = 0,
  Identifier = 80,
  PrivateIdentifier,
}

export declare function nextKind(kind: SyntaxKind): SyntaxKind;
export declare function maybeKind(kind?: SyntaxKind): SyntaxKind | undefined;
