// typebox's `src/index.ts`, reduced: a namespace import that is both
// re-exported by name and made the default export, in a barrel that
// also star-exports a module declaring the same name.
import * as Type from "./shapes";
export * from "./helpers";
export default Type;
export { Type as Shapes };
