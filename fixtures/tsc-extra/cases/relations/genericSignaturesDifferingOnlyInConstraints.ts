// @strict: true
// @target: esnext

// Assignability between generic signatures that are identical up to their
// type parameters' constraints, including a recursive constraint
// (`<T extends I2<T>>`).

interface NMap { 1: 'A'; 2: 'B'; 3: 'C'; 4: 'D' }
declare const g: <T extends 1 | 2 | 3>(x: `${T}`) => NMap[T];
type G2 = <T extends 1 | 2 | 3 | 4>(x: `${T}`) => NMap[T];
type G3 = <T extends 1 | 2>(x: `${T}`) => NMap[T];
function badWiderTarget() { const g2: G2 = g; }
function okNarrowerTarget() { const g3: G3 = g; }
interface I2<T> { p: T }
declare var x: <T extends I2<T>>(z: T) => void;
declare var y: <T extends I2<I2<T>>>(z: T) => void;
function okRecursive() { x = y; }
function badRecursive() { y = x; }
declare const s: <T extends string>(z: T) => void;
function badUnconstrainedTarget() { const u: <T>(z: T) => void = s; }
