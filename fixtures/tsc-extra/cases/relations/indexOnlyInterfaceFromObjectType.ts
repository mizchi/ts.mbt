// @strict: true
// @target: esnext

// An object type is assignable to an interface that declares only index
// signatures when every member fits them: a property or a `string` index
// signature against a `string` signature, and a `string` signature also
// against a `number` one. A value that does not fit is an error.

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
