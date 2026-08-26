// A property WRITE into an object that is later observed.
//
// `snapshot` reaches `JSON.stringify`, so its own keys stay reserved —
// but what is written INTO it is a separate question, and the analysis
// had no edge for it at all. `settings`' names arrive through a spread
// and `revision` exists only as a key in the written literal, so
// nothing else in the bundle could keep either alive: `beta` / `gamma`
// were deleted as dead and `alpha` was renamed.
//
// The string-literal computed write is the spelling that breaks — the
// dotted form happens to be covered by the `PropReceiver` use recorded
// for the target — so both are here, plus a write one level down so the
// target root has to be walked.
const settings = { alpha: 1, beta: 2, gamma: 3 };
const limits = { soft: 10, hard: 20 };
const inner = { depth: 1, width: 2 };

const snapshot: Record<string, unknown> = { meta: 0, rows: 0, deep: 0 };

snapshot["meta"] = { ...settings, revision: 7 };
snapshot.rows = { ...limits, retries: 2 };

const holder: Record<string, unknown> = { slot: 0 };
snapshot["deep"] = holder;
holder["slot"] = { ...inner, tag: "t" };

export const dump = JSON.stringify(snapshot);
console.log(dump);
