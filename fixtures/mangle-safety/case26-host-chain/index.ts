// The sink is two links down the host chain. `HostBridge.post(...)`
// was recognised; `HostBridge.channel.post(...)` was not, because the
// old rule only looked at a bare identifier receiver.
export const report = (n: number): number => {
  const record = { tickKind: "tick", tickAmount: n };
  const ret = HostBridge.channel.post(record);
  return ret.echoedValue;
};
