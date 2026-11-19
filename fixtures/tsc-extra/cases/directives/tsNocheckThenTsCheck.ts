// @ts-nocheck
// @ts-check

// When the leading comments carry both `@ts-nocheck` and `@ts-check`, the
// LAST one decides, in either order. Here it is `@ts-check`.

export const badLastPragmaWins: number = "s";
