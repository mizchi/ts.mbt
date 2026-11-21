// @strict: true
// @target: esnext

// An object type is assignable to an interface that declares only index
// signatures when every member fits every signature that applies to it: a
// `string` signature applies to every member, and a `number` signature to a
// numeric-named property and to a `string` or `number` signature. So a
// `string` signature also fits a `number` one when its value does. A value
// that does not fit is an error, also when it fits another signature.

interface IListData { listType: string }
interface ILists { [listType: string]: IListData }
interface NumIdx { [i: number]: string }
declare const anyValues: { [k: string]: any };
declare const listValues: { [k: string]: IListData };
declare const numberValues: { [k: string]: number };
declare const property: { a: number };
declare const stringIdx: { [k: string]: string };
declare const numIdxNumber: { [k: number]: number };
declare const snap: { lists?: ILists };
declare const presets: Record<string, IListData>;
export const okAnyValues: ILists = anyValues;
export const okListValues: ILists = listValues;
export const okSpread: ILists = { ...presets, ...(snap.lists ?? {}) };
export const okStringCoversNumber: NumIdx = stringIdx;
export const badIndexValue: ILists = numberValues;
export const badProperty: ILists = property;
export const badNumberValue: NumIdx = numIdxNumber;
interface Both { [k: string]: string; [k: number]: "ok" }
declare const zeroString: { "0": string };
declare const zeroOk: { "0": "ok" };
declare const strIdx: { [k: string]: string };
declare const strIdxOk: { [k: string]: "ok" };
declare const named: { a: string };
export const okZero: Both = zeroOk;
export const okStrIdx: Both = strIdxOk;
export const okNamed: Both = named;
export const badZero: Both = zeroString;
export const badStrIdx: Both = strIdx;
