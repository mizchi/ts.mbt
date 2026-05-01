export function flipFlag(flag) {
  return !flag;
}

export function maybeAlways(flag) {
  if (flag == null) return undefined;
  return true;
}
