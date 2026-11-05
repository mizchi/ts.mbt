/**
 * An event source whose listeners take an array: the shape where a
 * converting wrapper must keep function identity, or `removeListener`
 * stops removing what `addListener` added.
 */
export declare class EventSource {
  constructor();
  addListener(listener: (items: string[]) => void): void;
  removeListener(listener: (items: string[]) => void): void;
  hasListener(listener: (items: string[]) => void): boolean;
  listenerCount(): number;
  dispatch(items: string[]): void;
  firstListener(): (items: string[]) => void;
}
/**
 * The `on` / `off` spelling. The owner and method together were short
 * enough (`Emitter_on`) that `on` used to take an opaque callback type
 * nothing could construct, while `off` took a closure.
 */
export declare class Emitter {
  constructor();
  on(event: string, listener: (items: string[]) => void): this;
  off(event: string, listener: (items: string[]) => void): this;
  emit(event: string, items: string[]): void;
  count(event: string): number;
}
