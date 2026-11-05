// The JavaScript entry points.
//
// Compiled for the `js` backend only (see `targets` in `moon.pkg`).
//
// These exist because a generic function cannot be a JS export: the
// link configuration names a symbol, and `get_program_diagnostics` is
// one symbol per host type after monomorphization. So each entry point
// here is the same call with `MtscJsHost` substituted, and nothing
// else — no logic lives in this file, which is what keeps the JS path
// and the `moon test` path the same code. The service is exercised
// against `MtscMemoryHost` by `service_wbtest.mbt` on native, and the
// only thing these wrappers can get wrong is which function they call.
//
// Every array that crosses here is a `FixedArray`. A `FixedArray` IS a JS
// array on this backend, while an `Array` is a MoonBit growable array —
// since moonc v0.10.20 an object `{ buf, len }`, so returning one hands
// JavaScript something with no `.map` and taking one rejects the plain
// arrays every JS caller passes.

///|
/// Every diagnostic for the program the host describes.
pub fn js_get_program_diagnostics(
  host : MtscJsHost,
) -> FixedArray[MtscDiagnostic] {
  FixedArray::from_array(get_program_diagnostics(host))
}

///|
/// Type errors for one file.
pub fn js_get_semantic_diagnostics(
  host : MtscJsHost,
  file : String,
) -> FixedArray[MtscDiagnostic] {
  FixedArray::from_array(get_semantic_diagnostics(host, file))
}

///|
/// Parse errors for one file.
pub fn js_get_syntactic_diagnostics(
  host : MtscJsHost,
  file : String,
) -> FixedArray[MtscDiagnostic] {
  FixedArray::from_array(get_syntactic_diagnostics(host, file))
}

///|
/// Every file in the program, roots plus what they reach.
pub fn js_get_program_file_names(host : MtscJsHost) -> FixedArray[String] {
  FixedArray::from_array(get_program_file_names(host))
}

///|
/// Where one specifier resolves, as the loader would resolve it.
pub fn js_resolve_module_name(
  host : MtscJsHost,
  importer : String,
  specifier : String,
) -> MtscResolvedModule {
  resolve_module_name(host, importer, specifier)
}

///|
/// `checkModuleGraph`'s argument as JavaScript builds it: an object whose
/// `modules` and `edges` are plain JS arrays.
pub(all) struct MtscJsModuleGraph {
  modules : FixedArray[MtscModuleSource]
  edges : FixedArray[MtscModuleEdge]
}

///|
/// The original string ABI, reading the graph through `MtscJsModuleGraph`
/// so a plain JS array is accepted; the check itself is
/// `check_module_graph`, unchanged.
pub fn js_check_module_graph(graph : MtscJsModuleGraph) -> String {
  check_module_graph({
    modules: Array::from_fixed_array(graph.modules),
    edges: Array::from_fixed_array(graph.edges),
  })
}
