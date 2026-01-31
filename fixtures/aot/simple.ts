// Simple AOT-compatible functions

function add(a: number, b: number): number {
  return a + b;
}

function factorial(n: number): number {
  let result = 1;
  for (let i = 1; i <= n; i = i + 1) {
    result = result * i;
  }
  return result;
}

function fibonacci(n: number): number {
  if (n <= 1) {
    return n;
  }
  let a = 0;
  let b = 1;
  for (let i = 2; i <= n; i = i + 1) {
    let tmp = a + b;
    a = b;
    b = tmp;
  }
  return b;
}

function max(a: number, b: number): number {
  return a > b ? a : b;
}

function abs(x: number): number {
  return x < 0 ? -x : x;
}
