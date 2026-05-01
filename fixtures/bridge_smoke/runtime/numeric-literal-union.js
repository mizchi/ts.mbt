export function nextStatus(code) {
  return code === 200 ? 404 : 200;
}

export function maybeStatus(code) {
  if (code === undefined) return undefined;
  return nextStatus(code);
}
