// @strict: true
// @target: esnext

// The object literal a `map` callback returns widens member by member, as the
// same literal does at a declaration: a member asserted `as const` or read
// from a declared value keeps its type, and a member written as a plain
// literal widens.

interface Container { start: number; require: 'a-or-b' | 'a-and-b' }
declare const ranges: { s: number }[];
export function okAsConstReturned(): Container[] {
    return ranges.map((r) => {
        const start = r.s + 1;
        return { start, require: 'a-or-b' as const };
    });
}
export function okAsConstBound(): Container[] {
    const cs = ranges.map((r) => {
        const start = r.s + 1;
        return { start, require: 'a-or-b' as const };
    });
    return cs;
}
export function okExpressionBody(): Container[] {
    const cs = ranges.map((r) => ({ start: r.s, require: 'a-and-b' as const }));
    return cs;
}
export function badFreshMember(): Container[] {
    const cs = ranges.map((r) => ({ start: r.s, require: 'a-or-b' }));
    return cs;
}
