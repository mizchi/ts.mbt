// Closures with read-only captures (Phase 2)

function makeAdder(x: number) {
  // x is captured (read-only)
  const add = (y: number) => x + y;
  return add(10);
}

function applyTwice(x: number) {
  // x is captured (read-only)
  const double = () => x * 2;
  return double() + double();
}

function nested(a: number, b: number) {
  // Both a and b are captured
  const sum = () => a + b;
  const diff = () => a - b;
  return sum() * diff();
}

function withCondition(n: number) {
  const isPositive = () => n > 0;
  const isEven = () => n % 2 === 0;
  if (isPositive()) {
    return isEven() ? 1 : 0;
  }
  return -1;
}
