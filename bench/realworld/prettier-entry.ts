import { format } from "prettier";
import babelPlugin from "prettier/plugins/babel";
import estreePlugin from "prettier/plugins/estree";

async function main() {
  const out = await format("const x={a:1,b:2,c:3,d:4};function f(  a,b  ){return a+b;}", {
    parser: "babel",
    plugins: [babelPlugin, estreePlugin] as any,
    semi: true,
    singleQuote: false,
  });
  if (out.includes("const x = {") && out.includes("a: 1") && out.includes("function f(a, b)")) {
    console.log("prettier ok:", JSON.stringify(out.trim()));
  } else {
    console.log("prettier fail:", JSON.stringify(out.trim()));
  }
}

main().catch((e) => console.log("prettier error:", e.message));
