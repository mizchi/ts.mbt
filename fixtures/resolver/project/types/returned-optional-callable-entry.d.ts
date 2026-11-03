// nanoid's `customAlphabet`: returns a function whose parameter is
// OPTIONAL, so the returned type is wrapped in `CallableMeta`.
export declare function customAlphabet(alphabet: string, defaultSize?: number): (size?: number) => string;
export interface Factory {
  make(alphabet: string): (size?: number) => string;
}
export declare function factory(): Factory;
