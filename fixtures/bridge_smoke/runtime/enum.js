export function recordMode(mode) {
  return mode;
}

export function nextMode(mode) {
  return mode === "read" ? "write" : "read";
}

export function echo(mode) {
  return mode;
}
