export default class Counter {
  constructor(initial) {
    this.count = initial;
  }

  inc(delta) {
    return this.count + delta;
  }
}

export const version = "v2";

export function surround(label, prefix) {
  return `${prefix}${label}${prefix}`;
}
