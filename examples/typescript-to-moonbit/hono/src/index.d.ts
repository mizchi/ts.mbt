import type { HonoOptions } from "./hono-options-source";

export class Hono<E> {
  constructor(options?: HonoOptions<E>);
}

export function createApp<E>(options: HonoOptions<E>): Hono<E>;
