export function fetchLabel(id) {
  return Promise.resolve(`label:${id}`);
}

export function fetchCount() {
  return Promise.resolve(42);
}
