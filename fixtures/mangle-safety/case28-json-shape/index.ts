// `JSON.parse` is name-blind on the way in and completely host-shaped
// on the way out: the keys of the result come from a string produced at
// runtime, so every name read off it has to survive. The allowlist
// exempts the call's ARGUMENT from escaping without laundering the
// provenance of its RESULT.
export function load(text: string): number {
  const cfg = JSON.parse(text) as { retryCount: number; timeoutMs: number };
  return cfg.retryCount * cfg.timeoutMs;
}
