// Simple arithmetic test

export function add(a: number, b: number): number {
  return a + b;
}

export function factorial(n: number): number {
  if (n <= 1) {
    return 1;
  }
  return n * factorial(n - 1);
}
