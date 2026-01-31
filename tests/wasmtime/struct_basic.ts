// Basic struct test for wasm-gc

interface Point {
  x: number;
  y: number;
}

export function createPoint(): number {
  let p: Point = new Point();
  p.x = 10.0;
  p.y = 20.0;
  return p.x + p.y;
}
