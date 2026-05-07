// Verbatim mini-extract from zod/v4/core/util.d.ts. The bridge expands
// `${HashAlgorithm}_${HashEncoding}` to a 15-member string enum
// (5 algorithms × 3 encodings). Zod's full bridge keeps the alias
// behind generics (`$ZodCustomStringFormat<util.HashFormat>`), so this
// surface only fires for consumers that name `HashFormat` directly,
// but the cartesian itself is a real-world shape.

export type HashAlgorithm = "md5" | "sha1" | "sha256" | "sha384" | "sha512";
export type HashEncoding = "hex" | "base64" | "base64url";
export type HashFormat = `${HashAlgorithm}_${HashEncoding}`;

export declare function pickFormat(format: HashFormat): void;
