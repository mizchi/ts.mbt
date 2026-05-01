export function nextKind(kind) {
  return kind === 80 ? 81 : 80;
}

export function maybeKind(kind) {
  if (kind === undefined) return undefined;
  return nextKind(kind);
}
