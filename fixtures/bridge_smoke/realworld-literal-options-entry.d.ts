export type NodeEncoding = "utf8" | "buffer";
export type NodeFlag = "r" | "w" | "a";

export interface NodeReadOptions {
  encoding?: NodeEncoding | undefined;
  flag?: NodeFlag | undefined;
}

export declare function describeRead(
  path: string,
  options: NodeReadOptions,
): NodeEncoding;

export declare function nextFlag(flag: NodeFlag): NodeFlag;

export type ReactButtonType = "button" | "submit" | "reset";

export interface ReactButtonProps {
  type?: ReactButtonType | undefined;
}

export declare function renderReactButton(
  props: ReactButtonProps,
): ReactButtonType;

export type HonoMode = "strict" | "loose";

export interface HonoProbeOptions {
  mode?: HonoMode | undefined;
}

export declare function createHonoProbe(options: HonoProbeOptions): HonoMode;

export declare class FlagMachine {
  constructor();
  readonly mode: HonoMode;
  advance(): NodeFlag;
  peek(): NodeFlag | undefined;
}

export interface FlagTable {
  [key: string]: NodeFlag;
}

export declare function flagTable(): FlagTable;
