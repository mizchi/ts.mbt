// @strict: true
// @target: esnext

// A primitive is assignable to an object type whose members it has
// (`"abc"` has `length`), and so to an intersection of object types when it
// fits every part, an optional member included. A primitive that lacks a
// required member fits none.

declare const s: string;

export const okStringIntoMixedIntersection: { length: number } & { x?: number } = s;
export const okLiteralIntoMixedIntersection: { length: number } & { x?: number } = "abc";
export const okStringIntoObject: { length: number } = s;
export const badNumberIntoMixedIntersection: { length: number } & { x?: number } = 5;
export const badStringMissingMember: { length: number } & { size: number } = s;
