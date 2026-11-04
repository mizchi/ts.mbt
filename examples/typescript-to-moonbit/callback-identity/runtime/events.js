export class EventSource {
  constructor() {
    this.listeners = new Set();
  }
  addListener(listener) {
    this.listeners.add(listener);
  }
  removeListener(listener) {
    this.listeners.delete(listener);
  }
  hasListener(listener) {
    return this.listeners.has(listener);
  }
  listenerCount() {
    return this.listeners.size;
  }
  dispatch(items) {
    if (!Array.isArray(items)) throw new TypeError("dispatch expects a JS array");
    for (const listener of this.listeners) listener(items);
  }
  firstListener() {
    return [...this.listeners][0];
  }
}
