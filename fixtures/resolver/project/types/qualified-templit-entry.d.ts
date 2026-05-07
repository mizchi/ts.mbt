// `import * as util from "./qualified-templit-source"` exposes the
// sub-module under a qualified namespace alias. Template literals here
// must reach across modules to inline `util.HashAlgorithm` /
// `util.HashEncoding` before the cartesian expansion.
import * as util from "./qualified-templit-source";

export type HashFormat = `${util.HashAlgorithm}_${util.HashEncoding}`;

export declare function pickFormat(format: HashFormat): void;
