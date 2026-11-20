// @strict: true
// @target: esnext

// A primitive is assignable to an object type whose members it has
// (`"abc"` has `length`), and so to an intersection of object types when it
// fits every part, an optional member included. A primitive that lacks a
// required member fits none. An index signature is a member too: a
// string's numeric slots are `string`, and a primitive has no string index.

declare const s: string;

export const okStringIntoMixedIntersection: { length: number } & { x?: number } = s;
export const okLiteralIntoMixedIntersection: { length: number } & { x?: number } = "abc";
export const okStringIntoObject: { length: number } = s;
export const badNumberIntoMixedIntersection: { length: number } & { x?: number } = 5;
export const badStringMissingMember: { length: number } & { size: number } = s;
export const okStringNumericSlots: { length: number; [n: number]: string } & { charAt: any } = "abc";
export const badStringNumericSlots: { length: number; [n: number]: number } & { charAt: any } = "abc";
export const badStringIndexOnPrimitive: { length: number; [k: string]: any } & { charAt: any } = s;
