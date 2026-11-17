// @strict: true
// @target: esnext

// A `Record` over a closed key set (an enum, a literal union) has exactly
// those keys, so in `Record<E, boolean> & { ruleId?: string }` the
// `ruleId` member is the object type's `string`, not `boolean`. An open
// key type answers for any name. `xs.flat()` removes one level of nesting.

enum UnitAction { View = "view", Edit = "edit" }
type ICellPermission = Record<UnitAction, boolean> & { ruleId?: string };
declare const p: ICellPermission;
declare const openRecord: Record<string, number> & { label?: string };
declare const rows: number[][];

function okIntersectionMember() { const s: string | undefined = p.ruleId; }
function okRecordKey() { const b: boolean = p.view; }
function okOpenRecordAndMember() { const n: number = openRecord.anything; const l: string | undefined = openRecord.label; }
function okFlatOneLevel() { const n: number = rows.flat()[0]; }
function badRecordKeyType() { const s: string = p.edit; }
function badFlatElementType() { const s: string = rows.flat()[0]; }
