// The controls for the purity table. Both of these look like calls on
// a "pure global", and both have effects the bundle can observe:
// `Object.assign` writes into its first argument, and `Array.from`
// invokes the mapper it is handed. Neither may be dropped, and neither
// may make `record` look pure.
const registry: { hits?: number } = {};
function record(n: number): number {
  Object.assign(registry, { hits: n });
  return n;
}
const seen: number[] = [];
const mapped = Array.from([1, 2], (n) => {
  seen.push(n);
  return n;
});
const unusedRecord = record(7);
// Report the registry through a sink, so a rename of `hits` shows up in
// the differential run rather than cancelling out between the write and
// the read. Without this the case would claim to protect a name that
// nothing outside the bundle can see.
console.log(registry);
export const out =
  (registry.hits === undefined ? 0 : registry.hits) + seen.length + mapped.length;
