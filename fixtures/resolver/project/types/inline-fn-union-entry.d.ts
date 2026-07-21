export interface Pair { key: string; value: string; }
export interface ParsedNode { kind: string; }

export interface CreateNodeOptions {
  uniqueKeys?: boolean | ((a: ParsedNode, b: ParsedNode) => boolean);
  sortMapEntries?: boolean | ((a: Pair, b: Pair) => number);
}

export declare function makeDoc(options?: CreateNodeOptions): string;
