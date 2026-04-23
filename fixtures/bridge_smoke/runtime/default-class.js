export default class Counter {
  constructor(initial) {
    this.count = initial;
  }

  inc(delta) {
    return this.count + delta;
  }

  static from(seed) {
    return new Counter(seed);
  }
}
