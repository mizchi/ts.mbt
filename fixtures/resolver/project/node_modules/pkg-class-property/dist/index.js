export class CounterState {
  static version = "v1";
  static step = 1;

  constructor() {
    this.current = 7;
    this.label = "start";
  }
}
