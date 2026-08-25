// Tests for the inverted call rule: a call escapes unless the callee
// is provably bundle-internal, with the `pure_builtins` allowlist as
// the exception.
//
// Every test drives `collect_externally_visible_props`, the same entry
// point the bundler uses, so a passing test means the reservation
// actually reaches the mangler and not just the classifier.

///|
/// Names the analysis says escape, given a block and the host-global
/// set the bundler would compute for it (the undeclared references).
fn escaping_props(source : String) -> Array[String] raise {
  let block = @parser.parse_block_from_source(source)
  let externals : Map[String, Bool] = {}
  for n in undeclared_referenced_names(block).keys() {
    externals[n] = true
  }
  collect_externally_visible_props(block, externals)
}

// ---------------------------------------------------------------------
// Holes the inversion closes
// ---------------------------------------------------------------------

///|
test "inverted: a sink two links down a host chain still escapes" {
  // The old catalog matched `HostBridge.post(x)` and missed
  // `HostBridge.channel.post(x)`, because it only looked at a
  // bare-identifier receiver.
  let result = escaping_props(
    (
      #|const record = { tickKind: "tick", tickAmount: 1 };
      #|HostBridge.channel.post(record);
      #|
    ),
  )
  // `record` carries no annotation, so its escape is the wildcard —
  // which is what suppresses property mangling for the bundle.
  assert_true(result.contains("*"))
}

///|
test "inverted: a value from a foreign factory is not internal" {
  // `client` is a bundle-local binding, so a call on it used to look
  // like a call into code the analysis can see. The body of
  // `transmit` belongs to whoever wrote `createClient`.
  let result = escaping_props(
    (
      #|const client = createClient();
      #|client.transmit({ recordId: 1, noteText: "n" });
      #|
    ),
  )
  assert_true(result.contains("recordId"))
  assert_true(result.contains("noteText"))
}

///|
test "inverted: a callback handed to a foreign call gets host values" {
  // `rowId` / `rowCaption` are read off a parameter the host fills
  // in. Nothing in the source connects them to `HostList`
  // syntactically, so only the provenance pass reaches them.
  let result = escaping_props(
    (
      #|HostList.each((row) => {
      #|  sideEffect(row.rowCaption, row.rowId);
      #|});
      #|
    ),
  )
  assert_true(result.contains("rowId"))
  assert_true(result.contains("rowCaption"))
}

///|
test "inverted: a call through an unresolvable callee escapes" {
  // `handlers[0]` isn't a name the analysis can resolve to a body.
  let result = escaping_props(
    (
      #|const handlers = getHandlers();
      #|handlers[0]({ payloadKey: 1 });
      #|
    ),
  )
  assert_true(result.contains("payloadKey"))
}

///|
test "inverted: a thin wrapper doesn't launder provenance" {
  // `load` is bundle-internal, but everything it returns came from
  // outside, so the names read off its result are the host's.
  let result = escaping_props(
    (
      #|function load() { return remote.read(); }
      #|const doc = load();
      #|sideEffect(doc.docTitle);
      #|
    ),
  )
  assert_true(result.contains("docTitle"))
}

// ---------------------------------------------------------------------
// What the allowlist has to keep manglable
// ---------------------------------------------------------------------

///|
test "allowlist: a name-blind built-in doesn't send its argument out" {
  // Without the allowlist this is the shape that breaks everything:
  // `Math` is a host global, so the inverted rule would treat
  // `Math.max(acc.largest, v)` as a hand-off and reserve `acc`'s
  // whole surface — in practice, the wildcard.
  let result = escaping_props(
    (
      #|const acc = { runningSum: 0, largest: 0 };
      #|acc.runningSum = acc.runningSum + 3;
      #|acc.largest = Math.max(acc.largest, 3);
      #|
    ),
  )
  assert_false(result.contains("runningSum"))
  assert_false(result.contains("largest"))
  assert_false(result.contains("*"))
}

///|
test "allowlist: a built-in container keeps its contents internal" {
  // `new Map()` is a host global too. Treating the result as
  // host-owned would make `seen.set(k, payload)` a hand-off.
  let result = escaping_props(
    (
      #|const payload = { innerKey: 1 };
      #|const seen = new Map();
      #|seen.set("k", payload);
      #|
    ),
  )
  assert_false(result.contains("innerKey"))
  assert_false(result.contains("*"))
}

///|
test "allowlist: a precisely-modelled sink keeps its exact reservation" {
  // `Object.keys` is on the allowlist so the generic rule doesn't add
  // a wildcard on top of the `DirectKeys` observation, which reserves
  // exactly the keys the call can expose.
  let result = escaping_props(
    (
      #|const cfg = { alpha: 1, beta: 2 };
      #|sideEffect(Object.keys(cfg));
      #|
    ),
  )
  assert_true(result.contains("alpha"))
  assert_true(result.contains("beta"))
  assert_false(result.contains("*"))
}

///|
test "allowlist: a pure call's result can still be host-shaped" {
  // `JSON.parse` takes a string, so its argument doesn't escape — but
  // the keys of its result come from text produced at runtime.
  let result = escaping_props(
    (
      #|const cfg = JSON.parse(readText());
      #|sideEffect(cfg.retryCount);
      #|
    ),
  )
  assert_true(result.contains("retryCount"))
}

///|
test "inverted: an internal call keeps its argument internal" {
  // The control case. `apply` is declared here, so the flow analysis
  // can see what happens to `opts` and nothing needs reserving.
  let result = escaping_props(
    (
      #|function apply(opts) { return opts.widthPx + 1; }
      #|const box = { widthPx: 4 };
      #|store.put(apply(box));
      #|
    ),
  )
  assert_false(result.contains("widthPx"))
  assert_false(result.contains("*"))
}
