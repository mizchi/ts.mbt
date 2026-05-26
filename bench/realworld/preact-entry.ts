import { h, render } from "preact";

// Minimal preact test - just verify the API is callable.
const vnode = h("div", { class: "x" }, "hello");
console.log("preact vnode:", typeof vnode, vnode.type, vnode.props.class);
