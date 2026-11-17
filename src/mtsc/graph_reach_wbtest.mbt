///|
/// The path-based walk `graph_type_modules` used before it ran on integer
/// ids, kept verbatim as the reference: breadth-first over the edges in
/// edge order, every edge whose target has a parsed module pushed, and
/// each module kept at its LAST position. Ingestion order decides which
/// declaration wins a merge, so the id-based walk must return exactly this.
fn reference_type_module_paths(
  root : String,
  modules : Array[ParsedMtscModule],
  edges : Array[MtscModuleEdge],
) -> Array[String] {
  let by_path : Map[String, ParsedMtscModule] = Map([])
  for m in modules {
    if !by_path.contains(m.source.path) {
      by_path[m.source.path] = m
    }
  }
  let by_importer : Map[String, Array[String]] = Map([])
  for e in edges {
    match by_importer.get(e.importerPath) {
      Some(ts) => ts.push(e.targetPath)
      None => by_importer[e.importerPath] = [e.targetPath]
    }
  }
  let order : Array[String] = []
  let visited : Map[String, Unit] = Map([])
  let pending = [root]
  let mut cursor = 0
  while cursor < pending.length() {
    let p = pending[cursor]
    cursor = cursor + 1
    if visited.contains(p) {
      continue
    }
    visited[p] = ()
    for t in by_importer.get(p).unwrap_or([]) {
      match by_path.get(t) {
        Some(m) => {
          order.push(m.source.path)
          pending.push(m.source.path)
        }
        None => ()
      }
    }
  }
  let last : Map[String, Int32] = Map([])
  for i, p in order {
    last[p] = i
  }
  let out = []
  for i, p in order {
    if last.get(p) == Some(i) {
      out.push(p)
    }
  }
  out
}

///|
fn reach_test_module(path : String) -> ParsedMtscModule {
  match
    parse_graph_module({ path, source: "export const x = 1;", allowJsx: false, }) {
    Ok(m) => m
    Err(e) => abort(e)
  }
}

///|
/// A cycle, a diamond whose shared node is reached twice (so its LAST
/// position wins), an edge to a path with no parsed module, a module listed
/// twice (first wins), and an unreachable module.
test "graph_type_modules on ids keeps the path-based walk's order" {
  let paths = ["/a.ts", "/b.ts", "/c.ts", "/d.ts", "/e.ts", "/b.ts", "/z.ts"]
  let modules = paths.map(reach_test_module)
  let edge = fn(f : String, t : String) {
    { importerPath: f, moduleSpecifier: t, targetPath: t, }
  }
  let edges = [
    edge("/a.ts", "/b.ts"),
    edge("/a.ts", "/c.ts"),
    edge("/b.ts", "/d.ts"),
    edge("/c.ts", "/d.ts"),
    edge("/d.ts", "/a.ts"),
    edge("/c.ts", "/missing.ts"),
    edge("/d.ts", "/e.ts"),
    edge("/e.ts", "/b.ts"),
  ]
  for root in ["/a.ts", "/c.ts", "/e.ts", "/z.ts"] {
    let root_module = modules
      .iter()
      .find_first(fn(m) { m.source.path == root })
      .unwrap()
    let keys : Array[String] = []
    let _ = graph_type_modules(root_module, modules, edges, keys~)
    assert_eq(keys, reference_type_module_paths(root, modules, edges))
  }
  // A second call with the same arrays reuses the index; a longer edge
  // list builds a new one and sees the new edge.
  edges.push(edge("/z.ts", "/a.ts"))
  let z = modules[6]
  let keys : Array[String] = []
  let _ = graph_type_modules(z, modules, edges, keys~)
  assert_eq(keys, reference_type_module_paths("/z.ts", modules, edges))
  assert_true(keys.length() > 0)
}
