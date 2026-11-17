// @strict: true
// @target: esnext

// One truthy optional chain narrows both the receiver its `?.` guards and
// the member it reads: inside `if (slice?.ranges)`, `slice` and
// `slice.ranges` are both non-nullish, so the member keeps its declared
// type. The narrowing ends with the branch.

interface R { id: string }
interface Body { ranges?: R[] }

function okMemberTyped(slice: Body | undefined) { if (slice?.ranges) { const r: R[] = slice.ranges; } }
function okLengthTest(slice: Body | undefined) { if (slice?.ranges?.length) { const r: R | undefined = slice.ranges[0]; } }
function okReceiverTyped(slice: Body | undefined) { if (slice?.ranges) { const b: Body = slice; } }
function badMemberWrongType(slice: Body | undefined) { if (slice?.ranges) { const n: number = slice.ranges; } }
function badAfterBranch(slice: Body | undefined) { if (slice?.ranges) { } const r: R[] = slice.ranges; }
