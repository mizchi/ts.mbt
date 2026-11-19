// @strict: true
// @target: esnext

// `await` on a union awaits each member, so destructuring the result of a
// `T | Promise<T>` call reads `T`'s members, not `string | undefined` off the
// promise member.

type MaybePromise<T> = T | Promise<T>;
declare function gen(): MaybePromise<{ html: string }>;
declare const mixed: { html: string } | Promise<{ html: number }>;

export async function okDestructureAwaitedUnion() { const { html } = await gen(); return html.trim(); }
export async function badDestructureAwaitedUnion() { const { html } = await gen(); const n: number = html; return n; }
export async function badAwaitedMembersDiffer() { const r = await mixed; const s: string = r.html; return s; }
