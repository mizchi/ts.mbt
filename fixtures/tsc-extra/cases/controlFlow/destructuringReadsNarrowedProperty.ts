// @strict: true
// @target: esnext

// Destructuring a reference reads each property through what control flow
// knows about it. After `if (!body.tables) body.tables = []`, or inside
// `if (body.tables)`, `const { tables } = body` is the narrowed array,
// renamed or not. A sibling property the flow said nothing about keeps its
// declared optional type, and so does an unguarded read.

interface B { tables?: number[]; other?: number[] }

function okAssignedThenDestructured(body: B) { if (!body.tables) { body.tables = []; } const { tables } = body; tables.push(1); }
function okGuardedThenDestructured(body: B) { if (body.tables) { const { tables } = body; tables.push(1); } }
function okRenamedDestructure(body: B) { if (!body.tables) { body.tables = []; } const { tables: t } = body; t.push(1); }
function badSiblingProperty(body: B) { if (!body.tables) { body.tables = []; } const { other } = body; other.push(1); }
function badUnnarrowed(body: B) { const { tables } = body; tables.push(1); }
function badAfterReassignment(body: B, next: B) { if (body.tables) { body = next; const { tables } = body; tables.push(1); } }
