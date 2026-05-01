export declare enum Mode {
  Read = "read",
  Write = "write",
}

export declare function recordMode(mode: Mode): string;
export declare function nextMode(mode: Mode): Mode;
export declare function echo(mode: Mode): Mode;
