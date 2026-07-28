// Smoke for the `hono` + `@hono/node-server` combo bridge.
//
// Builds a tiny Hono app via `@sut` (`hono`) and hands it to
// `@sut_node_server.serve` (`@hono/node-server`). Both bridge
// packages must resolve through the consumer's
// `package.json#imports` map for the run to print `ok`.
//
// `Options` is opaque on the node-server bridge, so we build the
// underlying `{ fetch, port }` object via a small extern factory.
// We bind to port 0 (auto-assign) and `process.exit(0)` from
// the listen callback to keep the smoke single-shot.

extern "js" fn make_serve_options(
  app : @sut.Hono[@sut.JSValue, @sut.JSValue, @sut.JSValue],
  port : Int,
) -> @sut_node_server.Options =
  #| (app, port) => ({ fetch: app.fetch.bind(app), port })

extern "js" fn smoke_exit_ok() -> Unit =
  #| () => { console.log("ok"); process.exit(0); }

fn[A, B] smoke_unsafe_cast(value : A) -> B = "%identity"

fn main {
  let app : @sut.Hono[@sut.JSValue, @sut.JSValue, @sut.JSValue] = @sut.new_hono(
    None,
  )
  let _ = app.get("/", fn(c) {
    smoke_unsafe_cast(c.text(smoke_unsafe_cast("hello"), None, None))
  })
  let opts = make_serve_options(app, 0)
  let _ = @sut_node_server.serve(opts, Some(fn(_info) { smoke_exit_ok() }))
}
