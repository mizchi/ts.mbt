// @strict: true
// @target: esnext

// A Unicode space is whitespace, as tsc's scanner reads it
// (`isWhiteSpaceSingleLine`): U+0085, U+1680, U+2000..U+200B, U+202F,
// U+205F, U+3000 and U+FEFF, beside NBSP, VT and FF. It separates tokens, so
// a declaration preceded by one is still a declaration, and so is one
// after a comment, where NBSP, VT and FF count too.

 export const okEmSpaceBeforeDeclaration = 1;
export const　okIdeographicSpaceAfterKeyword = 2;
export const okNoBreakSpaceBeforeColon : number = 3;
export const okNoBreakSpaceEndsTheName: number = okNoBreakSpaceBeforeColon;
export function badEmSpaceDoesNotHideMismatch() { const a: number = "s"; return a; }
export const okCafé = 4;
export const okNoBreakSpaceAfterBlockComment = /**/ 1;
export const okVerticalTabAfterBlockComment = /**/2;
export const okFormFeedAfterLineComment = 3; // c
export const okReadsAfterFormFeed: number = okFormFeedAfterLineComment;
