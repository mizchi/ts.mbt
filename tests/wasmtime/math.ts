// Math function tests for wasm-gc

export function testSqrt(x: number): number {
  return Math.sqrt(x);
}

export function testAbs(x: number): number {
  return Math.abs(x);
}

export function testFloor(x: number): number {
  return Math.floor(x);
}

export function testCeil(x: number): number {
  return Math.ceil(x);
}

export function testRound(x: number): number {
  return Math.round(x);
}

export function testMin(a: number, b: number): number {
  return Math.min(a, b);
}

export function testMax(a: number, b: number): number {
  return Math.max(a, b);
}

export function testPow(base: number, exp: number): number {
  return Math.pow(base, exp);
}

// Combined pure function
export function distance(x1: number, y1: number, x2: number, y2: number): number {
  let dx: number = x2 - x1;
  let dy: number = y2 - y1;
  return Math.sqrt(dx * dx + dy * dy);
}
