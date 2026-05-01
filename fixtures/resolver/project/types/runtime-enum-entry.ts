export enum RuntimeMode {
  Read = "read",
  Write = "write",
}

export function flipMode(mode: RuntimeMode): RuntimeMode {
  return mode === RuntimeMode.Read ? RuntimeMode.Write : RuntimeMode.Read;
}
