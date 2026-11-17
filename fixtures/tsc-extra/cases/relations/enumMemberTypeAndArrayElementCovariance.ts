// @strict: true
// @target: esnext

// An enum member type (`CommandType.MUTATION`) is assignable to its enum, so
// an interface narrowing `type?: CommandType` to one member is assignable to
// the wider interface, and arrays are covariant in their element. A
// different member is not assignable, and a `readonly` array does not
// assign to a mutable one.

enum CommandType { COMMAND = 0, OPERATION = 1, MUTATION = 2 }
interface ICommandInfo<T extends object = object> { id: string; type?: CommandType; params?: T }
interface IMutationInfo<T extends object = object> { id: string; type?: CommandType.MUTATION; params: T }
declare function run(tasks: ICommandInfo[]): void;
declare const ms: IMutationInfo[];
declare const m: IMutationInfo;
interface X { t: CommandType.COMMAND }
interface Y { t: CommandType.MUTATION }
interface Bad { id: number }

function okMemberToEnumProperty() { const c: ICommandInfo = m; }
function okArrayOfNarrowerElements() { run(ms); }
function okReadonlyToReadonly(xs: readonly IMutationInfo[]) { const ys: readonly ICommandInfo[] = xs; }
function badOtherMember(x: X) { const y: Y = x; }
function badElementNotAssignable(bs: Bad[]) { run(bs); }
function badReadonlyToMutable(xs: readonly IMutationInfo[]) { const ys: ICommandInfo[] = xs; }
