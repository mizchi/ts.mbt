// @strict: true
// @target: esnext

// A `for` loop's `let` head declares its own binding, so assignments to it in
// the body say nothing about an outer binding of the same name after the
// loop. An outer binding the body assigns does take the assigned type.

declare const flag: boolean;
export function okShadowed() {
    let x: string = "outer";
    for (let x: string | number = ""; flag;) { x = 1; }
    const after: string = x;
    return after;
}
export function badOuterAssigned() {
    let y: string | number = "outer";
    for (let i = 0; flag; i++) { y = 1; }
    const after: string = y;
    return after;
}
