// Round-two adversarial corpus — patterns that real applications
// rely on but that the optimizer hasn't been stressed against yet.
// Same shape as `adversarial_wbtest.mbt`: each fixture executes
// under node with both the baseline and optimized bundle, and any
// stdout divergence is a real false positive.

// ---------------------------------------------------------------------------
// Iterator protocol / Symbol-keyed access
// ---------------------------------------------------------------------------

///|
async test "adv2: custom iterator via Symbol.iterator returns iterable" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|class Counter {
    #|  start: number;
    #|  end: number;
    #|  constructor(s: number, e: number) {
    #|    this.start = s;
    #|    this.end = e;
    #|  }
    #|  [Symbol.iterator]() {
    #|    let i = this.start;
    #|    const e = this.end;
    #|    return {
    #|      next() {
    #|        return i < e
    #|          ? { value: i++, done: false }
    #|          : { value: undefined, done: true };
    #|      },
    #|    };
    #|  }
    #|}
    #|const out: number[] = [];
    #|for (const v of new Counter(1, 4)) out.push(v);
    #|console.log(out.join(","));
    #|
  run_differential(
    "adv2-symbol-iterator",
    files,
    "entry.ts",
    extra_reserved_props=["start", "end"],
  )
}

// ---------------------------------------------------------------------------
// for-await-of / async iterator
// ---------------------------------------------------------------------------

///|
async test "adv2: async function with await chain in a Promise.all" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|async function run() {
    #|  const tasks = [1, 2, 3].map((n) => Promise.resolve(n * 10));
    #|  const all = await Promise.all(tasks);
    #|  console.log("all:", all.join(","));
    #|  const settled = await Promise.allSettled(
    #|    [1, 2, 3].map((n) => n === 2
    #|      ? Promise.reject(new Error("bad:" + n))
    #|      : Promise.resolve("ok:" + n))
    #|  );
    #|  for (const r of settled) {
    #|    if (r.status === "fulfilled") console.log("F", r.value);
    #|    else console.log("R", r.reason.message);
    #|  }
    #|}
    #|run();
    #|
  run_differential("adv2-promise-all-settled", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// setTimeout / setInterval semantics — closure captures, timer
// scheduling. We rely on a microtask flush to keep the test
// deterministic.
// ---------------------------------------------------------------------------

///|
async test "adv2: setTimeout closure captures the loop variable correctly" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const out: number[] = [];
    #|const start = () => {
    #|  for (let i = 0; i < 3; i = i + 1) {
    #|    setTimeout(() => out.push(i), 0);
    #|  }
    #|  setTimeout(() => console.log("vals:", out.join(",")), 5);
    #|};
    #|start();
    #|
  run_differential("adv2-settimeout-closure", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Tagged template — i18n-style with named placeholders
// ---------------------------------------------------------------------------

///|
async test "adv2: tagged template builds a string via positional args" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|function tpl(strings: TemplateStringsArray, ...values: any[]): string {
    #|  let out = strings[0];
    #|  for (let i = 0; i < values.length; i = i + 1) {
    #|    out = out + "<<" + values[i] + ">>" + strings[i + 1];
    #|  }
    #|  return out;
    #|}
    #|const a = "alpha";
    #|const b = 42;
    #|console.log(tpl`[a=${a}, b=${b}]`);
    #|
  run_differential("adv2-tagged-template", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Date / Intl — locale-aware formatting is sensitive to property
// names and global side-effects.
// ---------------------------------------------------------------------------

///|
async test "adv2: Date arithmetic + toISOString round-trip" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const t0 = new Date("2024-01-01T00:00:00.000Z").getTime();
    #|const t1 = new Date("2024-01-08T00:00:00.000Z").getTime();
    #|const days = (t1 - t0) / (1000 * 60 * 60 * 24);
    #|console.log("days:", days);
    #|console.log(new Date(t0).toISOString());
    #|
  run_differential("adv2-date", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// TypedArray
// ---------------------------------------------------------------------------

///|
async test "adv2: Uint8Array roundtrip with set + slice" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const a = new Uint8Array([1, 2, 3, 4, 5, 6]);
    #|const b = a.slice(2, 5);
    #|console.log("byte-length:", a.byteLength);
    #|console.log("slice:", Array.from(b).join(","));
    #|a.set([99, 100], 1);
    #|console.log("set:", Array.from(a).join(","));
    #|
  run_differential("adv2-typed-array", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// React-style: function component returning a virtual DOM node
// ---------------------------------------------------------------------------

///|
async test "adv2: functional component with props passes through external surface" {
  // The component returns an object whose keys (`tag`, `props`,
  // `children`) are consumed by an external "renderer" — they
  // must survive mangling.
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|function h(tag: string, props: any, ...children: any[]) {
    #|  return { tag, props, children };
    #|}
    #|function Greet({ name, count }: { name: string; count: number }) {
    #|  return h("div", { className: "greet" },
    #|    h("strong", null, name),
    #|    " x ",
    #|    h("em", null, String(count)));
    #|}
    #|function render(node: any): string {
    #|  if (typeof node === "string") return node;
    #|  if (typeof node !== "object" || node === null) return String(node);
    #|  const childStr = node.children.map(render).join("");
    #|  const cls = node.props && node.props.className
    #|    ? ' class="' + node.props.className + '"'
    #|    : "";
    #|  return "<" + node.tag + cls + ">" + childStr + "</" + node.tag + ">";
    #|}
    #|console.log(render(Greet({ name: "alice", count: 3 })));
    #|
  run_differential(
    "adv2-functional-component",
    files,
    "entry.ts",
    // VDOM-shape keys cross between code and rendering layer; both
    // sides see them as runtime data.
    extra_reserved_props=["tag", "props", "children", "name", "count", "className"],
  )
}

// ---------------------------------------------------------------------------
// Recursive data shape — a JSON-Schema-ish walker
// ---------------------------------------------------------------------------

///|
async test "adv2: recursive walker on a nested tree shape" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|type Node = { label: string; children?: Node[] };
    #|const tree: Node = {
    #|  label: "root",
    #|  children: [
    #|    { label: "a", children: [{ label: "a1" }, { label: "a2" }] },
    #|    { label: "b" },
    #|  ],
    #|};
    #|function walk(n: Node, depth: number, out: string[]): void {
    #|  out.push(" ".repeat(depth * 2) + n.label);
    #|  if (n.children) for (const c of n.children) walk(c, depth + 1, out);
    #|}
    #|const lines: string[] = [];
    #|walk(tree, 0, lines);
    #|console.log(lines.join("|"));
    #|
  run_differential(
    "adv2-tree-walk",
    files,
    "entry.ts",
    extra_reserved_props=["label", "children"],
  )
}

// ---------------------------------------------------------------------------
// Map of higher-order functions — function composition
// ---------------------------------------------------------------------------

///|
async test "adv2: function composition pipeline" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|type Fn<A, B> = (a: A) => B;
    #|function pipe<A, B, C>(f: Fn<A, B>, g: Fn<B, C>): Fn<A, C> {
    #|  return (a: A) => g(f(a));
    #|}
    #|const double = (n: number) => n * 2;
    #|const plus1 = (n: number) => n + 1;
    #|const stringify = (n: number) => "v=" + n;
    #|const transform = pipe(pipe(double, plus1), stringify);
    #|console.log(transform(5));
    #|console.log(transform(0));
    #|
  run_differential("adv2-pipe", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Symbol-as-key — well-known and custom symbol
// ---------------------------------------------------------------------------

///|
async test "adv2: Symbol-keyed property survives optimization" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const tag = Symbol("custom-tag");
    #|const obj: any = { regular: 1 };
    #|obj[tag] = "hidden";
    #|console.log("regular:", obj.regular);
    #|console.log("via-symbol:", obj[tag]);
    #|console.log("string-keys:", Object.keys(obj).join(","));
    #|console.log("symbols:", Object.getOwnPropertySymbols(obj).length);
    #|
  run_differential(
    "adv2-symbol-key",
    files,
    "entry.ts",
    extra_reserved_props=["regular"],
  )
}

// ---------------------------------------------------------------------------
// Proxy — completely opaque, every operation is trapped
// ---------------------------------------------------------------------------

///|
async test "adv2: Proxy with trapping handler returns runtime values" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const handler = {
    #|  get(target: any, key: string | symbol): any {
    #|    if (typeof key === "string") {
    #|      return "proxied:" + key + ":" + (target[key] ?? "none");
    #|    }
    #|    return undefined;
    #|  },
    #|};
    #|const p: any = new Proxy({ alpha: 1 }, handler);
    #|console.log(p.alpha);
    #|console.log(p.beta);
    #|console.log(p.gamma);
    #|
  run_differential(
    "adv2-proxy",
    files,
    "entry.ts",
    // The handler reads `key` at runtime — every property name we
    // touch on the proxy crosses the boundary and must survive.
    extra_reserved_props=["alpha", "beta", "gamma"],
  )
}

// ---------------------------------------------------------------------------
// Class with private field (`#name`) and a public method touching it
// ---------------------------------------------------------------------------

///|
async test "adv2: private field via TS private modifier" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|class Wallet {
    #|  private balance: number = 0;
    #|  deposit(n: number) { this.balance = this.balance + n; }
    #|  withdraw(n: number) {
    #|    if (n > this.balance) throw new Error("insufficient");
    #|    this.balance = this.balance - n;
    #|  }
    #|  total() { return this.balance; }
    #|}
    #|const w = new Wallet();
    #|w.deposit(100);
    #|w.deposit(50);
    #|w.withdraw(30);
    #|console.log("total:", w.total());
    #|try {
    #|  w.withdraw(9999);
    #|} catch (e: any) {
    #|  console.log("err:", e.message);
    #|}
    #|console.log("final:", w.total());
    #|
  run_differential(
    "adv2-private-field",
    files,
    "entry.ts",
    extra_reserved_props=["balance"],
  )
}

// ---------------------------------------------------------------------------
// Module side-effect ordering — top-level `console.log` flushes
// before the entry's code runs.
// ---------------------------------------------------------------------------

///|
async test "adv2: side-effect order across modules survives tree-shake + reorder" {
  let files : Map[String, String] = {}
  files["a.ts"] =
    #|console.log("a:load");
    #|export const valA = 1;
    #|
  files["b.ts"] =
    #|console.log("b:load");
    #|import { valA } from "./a";
    #|export const valB = valA + 1;
    #|
  files["entry.ts"] =
    #|console.log("entry:start");
    #|import { valB } from "./b";
    #|console.log("entry:got", valB);
    #|console.log("entry:end");
    #|
  run_differential("adv2-side-effect-order", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Recursive function with multiple base cases
// ---------------------------------------------------------------------------

///|
async test "adv2: fibonacci-style recursion preserves both bases" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|function fib(n: number): number {
    #|  if (n <= 0) return 0;
    #|  if (n === 1) return 1;
    #|  return fib(n - 1) + fib(n - 2);
    #|}
    #|for (let i = 0; i < 10; i = i + 1) console.log(fib(i));
    #|
  run_differential("adv2-fib", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Spread into function call + as const tuple
// ---------------------------------------------------------------------------

///|
async test "adv2: as-const tuple destructured + spread back into call" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const pair = [3, 4] as const;
    #|function hypot(a: number, b: number) { return Math.sqrt(a * a + b * b); }
    #|console.log("hypot:", hypot(...pair));
    #|const [a, b] = pair;
    #|console.log("destruct:", a, b);
    #|
  run_differential("adv2-spread-tuple", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// String methods chain
// ---------------------------------------------------------------------------

///|
async test "adv2: string methods chain (replace / split / map)" {
  let files : Map[String, String] = {}
  files["entry.ts"] =
    #|const raw = "  ALPHA, beta , Gamma  ";
    #|const cleaned = raw
    #|  .trim()
    #|  .toLowerCase()
    #|  .split(",")
    #|  .map((s: string) => s.trim())
    #|  .filter((s: string) => s.length > 0)
    #|  .join("|");
    #|console.log(cleaned);
    #|
  run_differential("adv2-string-chain", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Re-export chain — a -> b -> c
// ---------------------------------------------------------------------------

///|
async test "adv2: re-export chain across three modules" {
  let files : Map[String, String] = {}
  files["a.ts"] =
    #|export const message = "from-a";
    #|export function greet(name: string): string { return message + ":" + name; }
    #|
  files["b.ts"] =
    #|export { greet, message } from "./a";
    #|
  files["c.ts"] =
    #|export { greet } from "./b";
    #|
  files["entry.ts"] =
    #|import { greet } from "./c";
    #|console.log(greet("alice"));
    #|
  run_differential("adv2-reexport-chain", files, "entry.ts")
}

// ---------------------------------------------------------------------------
// Default + named imports mixed
// ---------------------------------------------------------------------------

///|
async test "adv2: default + named imports both used" {
  let files : Map[String, String] = {}
  files["lib.ts"] =
    #|export default function (n: number): number { return n * 10; }
    #|export const VERSION = "1.0";
    #|export const ENABLED = true;
    #|
  files["entry.ts"] =
    #|import multiply, { VERSION, ENABLED } from "./lib";
    #|console.log("ver:", VERSION);
    #|console.log("on:", ENABLED);
    #|console.log("x10:", multiply(5));
    #|
  run_differential("adv2-default-named-mix", files, "entry.ts")
}
