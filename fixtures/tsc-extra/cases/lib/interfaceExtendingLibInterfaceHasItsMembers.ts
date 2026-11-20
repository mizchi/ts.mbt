// @strict: true
// @target: esnext
// @lib: esnext, dom

// An interface that extends a lib interface has all of that interface's
// members, through any number of levels: `timeStamp`, `type` and
// `preventDefault` come from `Event`. A member neither declares is still
// missing, and so is one missing from an interface whose base is a type
// alias, the file's own or a lib utility.

export interface IEvent extends Event { deviceType: number; }
export interface IUIEvent extends IEvent, UIEvent {}
export interface IMouseEvent extends IUIEvent, MouseEvent { altKey: boolean; }
export interface IPointerEvent extends IMouseEvent { pointerId: number; }

export function okLibMember(e: IEvent) { return e.type; }
export function okDeepLibMember(e: IPointerEvent) { return e.timeStamp; }
export function okLibMethod(e: IPointerEvent) { e.preventDefault(); }
export function okOwnMember(e: IPointerEvent) { return e.pointerId + e.deviceType; }
export function badMissingMember(e: IEvent) { return e.nope; }

interface Base { a: number }
type Shape = { a: number };
interface OverAlias extends Shape { b: number }
interface OverUtility extends Pick<Base, "a"> { c: number }
export function okAliasMembers(o: OverAlias, u: OverUtility) { return o.a + o.b + u.a + u.c; }
export function badAliasBaseTypo(o: OverAlias) { return o.nope; }
export function badUtilityBaseTypo(o: OverUtility) { return o.nope; }
