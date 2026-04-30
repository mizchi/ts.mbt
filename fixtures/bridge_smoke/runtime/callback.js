export function emitEvent(label, count, listener) {
  listener(label, count);
  return `${label}:${count}`;
}

export function maybeEmit(label, listener) {
  if (listener) {
    listener(label, 1);
    return `${label}:called`;
  }
  return `${label}:none`;
}
