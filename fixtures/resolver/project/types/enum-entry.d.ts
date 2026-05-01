export declare enum Mode {
  Read = "read",
  Write = "write",
}

export declare function setMode(mode: Mode): Mode;
export declare function maybeMode(mode?: Mode): Mode | undefined;
