// React-shaped JSX corpus — drops a faithful slim
// `react/jsx-runtime` into the VFS so functional components +
// fragments + arrays + spread props go through the full lowering
// pipeline. The shim's output shape (`{ type, props, key }`) is
// the same as what React produces, so a hand-written renderer can
// walk it to a string without depending on real React.

///|
let react_jsx_runtime_source : String =
  #|// react/jsx-runtime shim — produces React-shaped element
  #|// objects without depending on the real React install.
  #|export function jsx(type: any, props: any, key?: any) {
  #|  return { $$typeof: REACT_ELEMENT_TYPE, type, props: props ?? {}, key: key ?? null };
  #|}
  #|export function jsxs(type: any, props: any, key?: any) {
  #|  return { $$typeof: REACT_ELEMENT_TYPE, type, props: props ?? {}, key: key ?? null };
  #|}
  #|export const Fragment = "__REACT_FRAGMENT__";
  #|export const REACT_ELEMENT_TYPE = "__REACT_ELEMENT__";
  #|

///|
let react_render_helper : String =
  #|function render(node: any): string {
  #|  if (node == null || typeof node === "boolean") return "";
  #|  if (typeof node === "string" || typeof node === "number") return String(node);
  #|  if (Array.isArray(node)) return node.map(render).join("");
  #|  if (node.$$typeof !== "__REACT_ELEMENT__") return "?";
  #|  const t = node.type;
  #|  const p = node.props || {};
  #|  if (typeof t === "function") return render(t(p));
  #|  if (t === "__REACT_FRAGMENT__") return render(p.children);
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
  #|

// ---------------------------------------------------------------------------
// Simple functional component
// ---------------------------------------------------------------------------

///|
async test "react: functional component renders to HTML" {
  let files : Map[String, String] = {}
  files["react/jsx-runtime.ts"] = react_jsx_runtime_source
  let body =
    #|/** @jsxImportSource react */
    #|function Hello({ name }: { name: string }) {
    #|  return <h1>Hello, {name}!</h1>;
    #|}
    #|
  let tail =
    #|console.log(render(<Hello name="world" />));
    #|
  files["entry.tsx"] = body + react_render_helper + tail
  run_differential(
    "react-functional",
    files,
    "entry.tsx",
    extra_reserved_props=[
      "$$typeof", "type", "props", "key", "children", "name",
    ],
  )
}

// ---------------------------------------------------------------------------
// Component composition — outer renders inner; props flow through
// ---------------------------------------------------------------------------

///|
async test "react: component composition with prop drilling" {
  let files : Map[String, String] = {}
  files["react/jsx-runtime.ts"] = react_jsx_runtime_source
  let body =
    #|/** @jsxImportSource react */
    #|function Badge({ label, color }: { label: string; color: string }) {
    #|  return <span class={"badge " + color}>{label}</span>;
    #|}
    #|function Card({ title, status }: { title: string; status: string }) {
    #|  return (
    #|    <div class="card">
    #|      <h2>{title}</h2>
    #|      <Badge label={status} color={status === "ok" ? "green" : "red"} />
    #|    </div>
    #|  );
    #|}
    #|
  let tail =
    #|console.log(render(<Card title="Profile" status="ok" />));
    #|console.log(render(<Card title="Build" status="fail" />));
    #|
  files["entry.tsx"] = body + react_render_helper + tail
  run_differential(
    "react-composition",
    files,
    "entry.tsx",
    extra_reserved_props=[
      "$$typeof", "type", "props", "key", "children",
      "label", "color", "title", "status", "class",
    ],
  )
}

// ---------------------------------------------------------------------------
// List rendering + Fragment + key prop
// ---------------------------------------------------------------------------

///|
async test "react: list rendering with Fragment + key" {
  let files : Map[String, String] = {}
  files["react/jsx-runtime.ts"] = react_jsx_runtime_source
  let body =
    #|/** @jsxImportSource react */
    #|function Item({ text }: { text: string }) {
    #|  return <li>{text}</li>;
    #|}
    #|function List({ items }: { items: string[] }) {
    #|  return (
    #|    <>
    #|      <h3>items ({items.length})</h3>
    #|      <ul>
    #|        {items.map((it, i) => <Item key={i} text={it} />)}
    #|      </ul>
    #|    </>
    #|  );
    #|}
    #|
  let tail =
    #|console.log(render(<List items={["alpha", "beta", "gamma"]} />));
    #|
  files["entry.tsx"] = body + react_render_helper + tail
  run_differential(
    "react-list",
    files,
    "entry.tsx",
    extra_reserved_props=[
      "$$typeof", "type", "props", "key", "children", "text", "items",
    ],
  )
}

// ---------------------------------------------------------------------------
// Conditional rendering — `&&`, ternary, early return
// ---------------------------------------------------------------------------

///|
async test "react: conditional rendering patterns" {
  let files : Map[String, String] = {}
  files["react/jsx-runtime.ts"] = react_jsx_runtime_source
  let body =
    #|/** @jsxImportSource react */
    #|function Avatar({ url, alt }: { url: string | null; alt: string }) {
    #|  if (url === null) return <div class="avatar placeholder">{alt[0]}</div>;
    #|  return <img src={url} alt={alt} />;
    #|}
    #|function Notification({ count, urgent }: { count: number; urgent: boolean }) {
    #|  return (
    #|    <div>
    #|      {count > 0 && <span class="badge">{count}</span>}
    #|      {urgent ? <strong>!</strong> : null}
    #|    </div>
    #|  );
    #|}
    #|
  let tail =
    #|console.log(render(<Avatar url="img.png" alt="Alice" />));
    #|console.log(render(<Avatar url={null} alt="Bob" />));
    #|console.log(render(<Notification count={3} urgent={true} />));
    #|console.log(render(<Notification count={0} urgent={false} />));
    #|
  files["entry.tsx"] = body + react_render_helper + tail
  run_differential(
    "react-conditional",
    files,
    "entry.tsx",
    extra_reserved_props=[
      "$$typeof", "type", "props", "key", "children",
      "url", "alt", "src", "count", "urgent", "class",
    ],
  )
}

// ---------------------------------------------------------------------------
// Spread props — `<X {...rest} />`
// ---------------------------------------------------------------------------

///|
async test "react: spread props pass through" {
  let files : Map[String, String] = {}
  files["react/jsx-runtime.ts"] = react_jsx_runtime_source
  let body =
    #|/** @jsxImportSource react */
    #|function Button(props: any) {
    #|  return <button class={props.class}>{props.label}</button>;
    #|}
    #|function PrimaryButton(rest: any) {
    #|  return <Button {...rest} class="btn btn-primary" />;
    #|}
    #|
  let tail =
    #|console.log(render(<PrimaryButton label="Submit" />));
    #|console.log(render(<PrimaryButton label="Cancel" id="cancel-btn" />));
    #|
  files["entry.tsx"] = body + react_render_helper + tail
  run_differential(
    "react-spread",
    files,
    "entry.tsx",
    extra_reserved_props=[
      "$$typeof", "type", "props", "key", "children",
      "label", "class", "id",
    ],
  )
}

// ---------------------------------------------------------------------------
// Hooks-like pattern (synchronous stand-in) — `useState`-style
// closure-driven state pulled through a render pass.
// ---------------------------------------------------------------------------

///|
async test "react: useState-like closure tracking pattern" {
  let files : Map[String, String] = {}
  files["react/jsx-runtime.ts"] = react_jsx_runtime_source
  let body =
    #|/** @jsxImportSource react */
    #|let __stateSlots: any[] = [];
    #|let __slotIdx = 0;
    #|function useState<T>(init: T): [T, (v: T) => void] {
    #|  const i = __slotIdx++;
    #|  if (__stateSlots[i] === undefined) __stateSlots[i] = init;
    #|  return [__stateSlots[i] as T, (v: T) => { __stateSlots[i] = v; }];
    #|}
    #|function resetHooks() { __slotIdx = 0; }
    #|function Counter() {
    #|  const [count, setCount] = useState(0);
    #|  return <div>count={count}</div>;
    #|}
    #|
  let tail =
    #|resetHooks();
    #|console.log(render(<Counter />));
    #|__stateSlots[0] = 5;
    #|resetHooks();
    #|console.log(render(<Counter />));
    #|
  files["entry.tsx"] = body + react_render_helper + tail
  run_differential(
    "react-hooks-like",
    files,
    "entry.tsx",
    extra_reserved_props=[
      "$$typeof", "type", "props", "key", "children",
    ],
  )
}

// ---------------------------------------------------------------------------
// Bench: React functional-component bundle size + throughput
// ---------------------------------------------------------------------------

///|
test "bench bundle: react functional component pipeline — full opt" (
  it : @bench.T,
) {
  let files : Map[String, String] = {}
  files["react/jsx-runtime.ts"] = react_jsx_runtime_source
  files["entry.tsx"] =
    #|/** @jsxImportSource react */
    #|function App({ name }: { name: string }) {
    #|  return <div><h1>Hello, {name}!</h1><p>welcome</p></div>;
    #|}
    #|console.log(App);
    #|
  let opts = full_opt_bundle_options()
  it.bench(fn() {
    let out = match bundle_modules(files, "entry.tsx", opts) {
      Ok(o) => o
      Err(_) => return
    }
    it.keep(out.js.length())
  })
}
