// @strict: true
// @target: esnext

// `Array.isArray(p.body?.textRuns)` being true means the optional chain did
// not short-circuit, because `undefined` is not an array, so `p.body` is
// non-nullish inside the branch, also after an `&&` that guards `p` first.
// The false branch says nothing about `p.body`: the chain may have
// short-circuited.

interface Body { textRuns?: number[] }
interface Doc { body?: Body }
declare function use(b: Body): void;

export function okIsArrayChain(p: Doc) { if (Array.isArray(p.body?.textRuns)) { use(p.body); } }
export function okIsArrayChainAfterGuard(p: Doc | undefined) { if (p && Array.isArray(p.body?.textRuns) && p.body.textRuns.length > 0) { use(p.body); } }
export function okIsArrayPathNarrowed(p: Doc) { if (Array.isArray(p.body?.textRuns)) { return p.body.textRuns.length; } return 0; }

export function badIsArrayNegated(p: Doc) { if (!Array.isArray(p.body?.textRuns)) { use(p.body); } }
export function badIsArrayElseBranch(p: Doc) { if (Array.isArray(p.body?.textRuns)) { return 0; } else { use(p.body); return 1; } }
