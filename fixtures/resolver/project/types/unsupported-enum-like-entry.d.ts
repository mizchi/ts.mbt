export declare enum MixedMode {
  Text = "text",
  Code = 1,
}

export declare enum ComputedKind {
  Dynamic = getKind(),
  Static = 1,
}

export declare enum DuplicateMode {
  A = "same",
  B = "same",
}

export type MixedAlias = "text" | 1;
export type FloatAlias = 1.5 | 2;
export type BigAlias = 1n | 2n;
