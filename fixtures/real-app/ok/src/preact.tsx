/** @jsxImportSource preact */
import { render, h } from "preact";
import { useState, useEffect } from "preact/hooks";
import type { ComponentChildren } from "preact";
export function Box(props: { title: string; children?: ComponentChildren }) {
  const [n, setN] = useState(0);
  useEffect(() => { setN((x) => x + 1); }, []);
  return <div class="box" onClick={() => setN(n + 1)}><h1>{props.title}</h1>{props.children}{n}</div>;
}
export function mount(el: HTMLElement) { render(h(Box, { title: "x" }), el); }
