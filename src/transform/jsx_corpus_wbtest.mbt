// JSX corpus — functional components, props, conditional rendering,
// fragments, and the jsx-runtime lowering. Each fixture provides a
// runtime `jsx`/`Fragment` shim so node can execute the bundle
// without React installed.

// ---------------------------------------------------------------------------
// Shim helper — every JSX fixture's entry includes the same tiny
// renderer that consumes the jsx-runtime API.
// ---------------------------------------------------------------------------

///|
let jsx_shim : String =
  #|globalThis.__jsxShim = (tag: any, props: any, key?: any): any => {
  #|  return { __t: tag, __p: props ?? {}, __k: key };
  #|};
  #|globalThis.__jsxFrag = "__FRAGMENT__";
  #|function render(node: any): string {
  #|  if (node == null || typeof node === "boolean") return "";
  #|  if (typeof node === "string" || typeof node === "number") return String(node);
  #|  if (Array.isArray(node)) return node.map(render).join("");
  #|  const t = node.__t;
  #|  const p = node.__p || {};
  #|  if (typeof t === "function") return render(t(p));
  #|  if (t === "__FRAGMENT__") return render(p.children);
  #|  let out = "<" + String(t);
  #|  for (const k of Object.keys(p)) {
  #|    if (k === "children") continue;
  #|    out = out + " " + k + "=\"" + String(p[k]) + "\"";
  #|  }
  #|  out = out + ">";
  #|  out = out + render(p.children);
  #|  out = out + "</" + String(t) + ">";
  #|  return out;
  #|}
  #|(globalThis as any).render = render;
  #|

// ---------------------------------------------------------------------------
// Bare JSX expression: `<div>hi</div>` → jsx("div", { children: "hi" })
// ---------------------------------------------------------------------------

///|
async test "jsx: bare element with text child" {
  let files : Map[String, String] = {}
  files["entry.tsx"] =
    #|/** @jsxImportSource ./shim */
    #|const el = <div>hello, world</div>;
    #|console.log(render(el));
    #|
  files["shim/jsx-runtime.ts"] =
    jsx_shim +
    #|export const jsx = globalThis.__jsxShim;
    #|export const jsxs = globalThis.__jsxShim;
    #|export const Fragment = globalThis.__jsxFrag;
    #|
  run_differential(
    "jsx-bare",
    files,
    "entry.tsx",
    extra_reserved_props=["__t", "__p", "__k", "children"],
  )
}

// ---------------------------------------------------------------------------
// Functional component with typed props
// ---------------------------------------------------------------------------

///|
async test "jsx: functional component with destructured props" {
  let files : Map[String, String] = {}
  files["entry.tsx"] =
    #|/** @jsxImportSource ./shim */
    #|function Greet({ name, count }: { name: string; count: number }) {
    #|  return <p>hi {name} x {String(count)}</p>;
    #|}
    #|const el = <Greet name="alice" count={3} />;
    #|console.log(render(el));
    #|
  files["shim/jsx-runtime.ts"] =
    jsx_shim +
    #|export const jsx = globalThis.__jsxShim;
    #|export const jsxs = globalThis.__jsxShim;
    #|export const Fragment = globalThis.__jsxFrag;
    #|
  run_differential(
    "jsx-component",
    files,
    "entry.tsx",
    extra_reserved_props=["__t", "__p", "__k", "children", "name", "count"],
  )
}

// ---------------------------------------------------------------------------
// Conditional rendering — `cond && <X/>` and ternary
// ---------------------------------------------------------------------------

///|
async test "jsx: conditional rendering with && + ternary" {
  let files : Map[String, String] = {}
  files["entry.tsx"] =
    #|/** @jsxImportSource ./shim */
    #|function Card({ active, label }: { active: boolean; label: string }) {
    #|  return (
    #|    <div>
    #|      <span>{label}</span>
    #|      {active && <strong>ACTIVE</strong>}
    #|      {active ? <em>on</em> : <em>off</em>}
    #|    </div>
    #|  );
    #|}
    #|console.log(render(<Card active={true} label="A" />));
    #|console.log(render(<Card active={false} label="B" />));
    #|
  files["shim/jsx-runtime.ts"] =
    jsx_shim +
    #|export const jsx = globalThis.__jsxShim;
    #|export const jsxs = globalThis.__jsxShim;
    #|export const Fragment = globalThis.__jsxFrag;
    #|
  run_differential(
    "jsx-conditional",
    files,
    "entry.tsx",
    extra_reserved_props=["__t", "__p", "__k", "children", "active", "label"],
  )
}

// ---------------------------------------------------------------------------
// Fragment + list rendering
// ---------------------------------------------------------------------------

///|
async test "jsx: fragment wraps multiple children + array map" {
  let files : Map[String, String] = {}
  files["entry.tsx"] =
    #|/** @jsxImportSource ./shim */
    #|function List({ items }: { items: string[] }) {
    #|  return (
    #|    <>
    #|      <h1>items</h1>
    #|      <ul>
    #|        {items.map((it: string, i: number) => <li key={i}>{it}</li>)}
    #|      </ul>
    #|    </>
    #|  );
    #|}
    #|console.log(render(<List items={["a", "b", "c"]} />));
    #|
  files["shim/jsx-runtime.ts"] =
    jsx_shim +
    #|export const jsx = globalThis.__jsxShim;
    #|export const jsxs = globalThis.__jsxShim;
    #|export const Fragment = globalThis.__jsxFrag;
    #|
  run_differential(
    "jsx-fragment",
    files,
    "entry.tsx",
    extra_reserved_props=["__t", "__p", "__k", "children", "items"],
  )
}

// ---------------------------------------------------------------------------
// Spread props
// ---------------------------------------------------------------------------

///|
async test "jsx: spread attributes forward props through wrapper" {
  let files : Map[String, String] = {}
  files["entry.tsx"] =
    #|/** @jsxImportSource ./shim */
    #|function Inner(props: any) {
    #|  return <p>{props.title}: {props.body}</p>;
    #|}
    #|function Outer(props: any) {
    #|  return <Inner {...props} />;
    #|}
    #|console.log(render(<Outer title="hello" body="world" />));
    #|
  files["shim/jsx-runtime.ts"] =
    jsx_shim +
    #|export const jsx = globalThis.__jsxShim;
    #|export const jsxs = globalThis.__jsxShim;
    #|export const Fragment = globalThis.__jsxFrag;
    #|
  run_differential(
    "jsx-spread",
    files,
    "entry.tsx",
    extra_reserved_props=["__t", "__p", "__k", "children", "title", "body"],
  )
}
