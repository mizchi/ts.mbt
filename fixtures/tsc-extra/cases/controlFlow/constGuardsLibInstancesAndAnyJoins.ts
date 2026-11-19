// @strict: true
// @target: esnext

// Shapes from real code that each lean on one fact. A `const` arrow guard
// narrows a parameter typed by an indexed access, and a property path. A
// regex literal is a `RegExp`, so `exec` in an assignment loop narrows. A
// `switch` over an `any` scrutinee with grouped labels keeps `any`, and so
// does a join with an `any` side. A union holding a DOM interface reached
// through an alias has the interface's members.

type UIConfig = { enabled: { zoom?: boolean } } | { disabled: { minimap?: boolean } };
type AppProps = { ui?: boolean | UIConfig };
const isUIConfig = (ui: AppProps["ui"]): ui is UIConfig => typeof ui === "object" && ui !== null;
declare const els: any[];
declare function load(): any;
declare const flag: boolean;
type Canvasish = OffscreenCanvas | HTMLCanvasElement;

export function okConstGuardOnIndexedAccessParam(ui: AppProps["ui"]) { if (isUIConfig(ui)) { const x: UIConfig = ui; return x; } return null; }
export function okConstGuardOnPath(props: AppProps) { if (isUIConfig(props.ui)) { return "enabled" in props.ui ? props.ui.enabled.zoom : props.ui.disabled.minimap; } return undefined; }
export function badConstGuardElse(props: AppProps) { if (!isUIConfig(props.ui)) { const c: UIConfig = props.ui; return c; } return null; }
export function okRegexExecLoop(t: string) { const re = /a/g; let m = null; while ((m = re.exec(t)) !== null) { return m.index; } return -1; }
export function badDateGetTime() { const d = new Date(); const s: string = d.getTime(); return s; }
export function okGroupedLabelsOnAny() { for (const el of els) { switch (el.type) { case "a": case "b": return el?.label?.text; } } return 0; }
export function okJoinWithAnySide() { let d = null; try { d = load() || null; } catch { d = { message: "x" }; } return d?.elements; }
export function badJoinOfTypedSides() { let d = null; if (flag) { d = "s"; } else { d = { a: 1 }; } return d.b; }
export function okDomUnionAlias(c: Canvasish) { return c.width; }
