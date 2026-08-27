// Explicit type arguments hide the whole call from a pass that forgot
// the wrapper.
//
// `f<T>(x)`, `new C<T>(x)` and `o.m<T>(x)` all parse as
// `TypeArgs([T], <the call>)` — a wrapper kept so the pervasive `Call` /
// `New` / `MethodCall` match sites did not have to change. The cost is
// that a walker matching those three and ending in `_ => ()` does not
// fall through to the inner call: it sees nothing, and every name and
// every property read inside the call is invisible to that analysis.
//
// Nineteen files peeled `As` / `NonNull` and not this one. Two of them
// were unsound: treeshake deleted the declaration of a binding used only
// inside such a call (Excalidraw's `new Map<K, V>([[…, CODES.Z]])`, a
// ReferenceError at module load), and the read-property collector missed
// a property read so dead-property elimination deleted the key.
//
// Each shape below puts the ONLY reference to something inside a
// type-argument call, so a pass that cannot see through the wrapper
// changes what this program prints.

// 1. The only use of a binding is inside `new C<T>(…)`.
const CODES = { Z: "KeyZ", Y: "KeyY" };
const codeMap = new Map<string, string>([
  ["z", CODES.Z],
  ["y", CODES.Y],
]);

// 2. The only read of a property is inside `f<T>(…)`.
function identity<T>(v: T): T {
  return v;
}
const holder = { onlyReadInTypeArgsCall: 41 };
const picked = identity<number>(holder.onlyReadInTypeArgsCall) + 1;

// 3. An object literal escapes to an external observer through the
//    wrapper, so its keys are ABI.
const payload = { alpha: 1, beta: { gamma: 2 } };
const serialized = JSON.stringify<never>(payload as never);

// 4. A method call carrying type arguments, whose receiver is the only
//    thing keeping the array alive.
const rows = [{ label: "a" }, { label: "b" }];
const labels = rows.map<string>((row) => row.label).join(",");

// 5. A side effect inside the wrapper: dropping the call changes the
//    count.
let effects = 0;
function bump<T>(v: T): T {
  effects = effects + 1;
  return v;
}
const bumped = bump<number>(2) + bump<number>(3);

export const report = {
  z: codeMap.get("z"),
  y: codeMap.get("y"),
  picked,
  serialized,
  labels,
  bumped,
  effects,
};
console.log(JSON.stringify(report));
