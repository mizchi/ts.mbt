// `roughjs/bin/generator` — the `RoughGenerator` class.
//
// The bundled build exports only the default object, so the class is
// reached through the factory it exposes: `rough.generator()` returns a
// RoughGenerator instance, and its constructor is the real class.
// Excalidraw does `new RoughGenerator()` in a static class field, so
// what it needs is the constructor itself.
import rough from "roughjs/bundled/rough.esm.js";

export const RoughGenerator = rough.generator().constructor;
