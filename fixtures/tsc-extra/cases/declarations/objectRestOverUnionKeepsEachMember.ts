// @strict: true
// @target: esnext

// An object rest over a union is a union of the members' rests, so it keeps
// each member's discriminant and narrows by it.

type Base = { size?: string; hidden?: boolean };
type P = (Base & { type: "button"; onClick?(): void }) | (Base & { type: "toggle"; checked: boolean });
type Q = { type: "a"; x: number; k: string } | { type: "b"; y: string; k: string };

export function okRestNarrowsByDiscriminant({ size = "m", ...props }: P) { if (props.type === "button") return props.onClick; return props.checked; }
export function badRestKeepsBothDiscriminants({ k, ...rest }: Q) { const z: "z" = rest.type; return z; }
export function badRestNarrowedMemberType({ k, ...rest }: Q) { if (rest.type === "a") { const s: string = rest.x; return s; } return ""; }
