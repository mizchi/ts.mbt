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
