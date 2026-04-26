export class Hono {
  constructor(options) {
    this.options = options;
  }
}

export function createApp(options) {
  return new Hono(options);
}
