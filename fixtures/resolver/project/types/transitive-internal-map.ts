let createdCount = 0;

class InternalMap<K, V> {
  constructor(readonly label: string = "cache") {}

  get(_key: K): V | undefined {
    createdCount = createdCount + 1;
    return undefined;
  }
}

export { InternalMap };
