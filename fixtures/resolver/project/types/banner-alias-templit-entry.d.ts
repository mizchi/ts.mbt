// `Banner = `${Channel}-${Variant}`` — alias-indirected template literal.
// Channel and Variant should be inlined to their literal unions before
// the cartesian expansion so Banner ends up as a 4-member string enum.

export type Channel = "info" | "warn";
export type Variant = "small" | "large";
export type Banner = `${Channel}-${Variant}`;

export declare function tagBanner(b: Banner): void;
