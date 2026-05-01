export declare enum Kind {
  Ready = 1,
}

export interface Context {
  handle(kind: Kind): void;
}

export declare function visit(context: Context): void;
