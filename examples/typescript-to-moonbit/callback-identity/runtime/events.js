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
export class Emitter {
  constructor() {
    this.byEvent = new Map();
  }
  #set(event) {
    if (!this.byEvent.has(event)) this.byEvent.set(event, new Set());
    return this.byEvent.get(event);
  }
  on(event, listener) {
    this.#set(event).add(listener);
    return this;
  }
  off(event, listener) {
    this.#set(event).delete(listener);
    return this;
  }
  emit(event, items) {
    if (!Array.isArray(items)) throw new TypeError("emit expects a JS array");
    for (const listener of this.#set(event)) listener(items);
  }
  count(event) {
    return this.#set(event).size;
  }
}
