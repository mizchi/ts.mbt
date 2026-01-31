// Array test for wasm-gc

export function sumArray(): int {
  let arr: int[] = new Array<int>(3);
  arr[0] = 10;
  arr[1] = 20;
  arr[2] = 30;
  return arr[0] + arr[1] + arr[2];
}
