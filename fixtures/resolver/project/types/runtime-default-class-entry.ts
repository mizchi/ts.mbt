export default class Counter {
  count: number

  constructor(initial: number) {
    this.count = initial
  }

  inc(delta: number): number {
    return this.count + delta
  }

  static from(seed: number): Counter {
    return new Counter(seed)
  }
}
