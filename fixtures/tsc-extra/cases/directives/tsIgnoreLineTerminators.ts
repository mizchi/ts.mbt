// The line a directive covers is counted with every line terminator the
// lexer knows: CR, LS and PS end a line as LF does, so each directive
// below covers the declaration after its terminator. A line holding only
// a no-break space, or only an LS or PS, is not blank to the pairing, and
// the directive before it covers nothing.

// @ts-ignoreexport const okAfterCr: string = 1;
// @ts-ignore export const okAfterLs: string = 1;
// @ts-ignore export const okAfterPs: string = 1;
/* a   @ts-ignore */export const okAfterCrBlockLastLine: string = 1;
/* @ts-ignore*/ export const badCrBlockEndsBeforeCode: string = 1;

// @ts-ignore
 
export const badAfterNbspLine: string = 1;

// @ts-ignore
 
export const badAfterLsOnlyLine: string = 1;

// @ts-ignore
	 
export const okAfterTabSpaceLine: string = 1;
