fn test_hono_handler(c : @sut.Context) -> @sut.Response {
  c.text("hi", None, None)
}

extern "js" fn test_undefined() -> @sut.JSValue =
  #| () => undefined

extern "js" fn test_hono_route_response(app : @sut.Hono, res : @sut.JSValue) -> String =
  #| (app, res) => {
  #|   const route = app.routes[0];
  #|   return `${res.status}:${route.method}:${route.path}:${res.headers.get("content-type")}`;
  #| }

fn main {
  let app = @sut.new_hono(None)
  let _ = app.get("/hello", test_hono_handler)
  let undefined_ = test_undefined()
  let res = app.request(
    @sut.unsafeCast("/hello"),
    @sut.unsafeCast(undefined_),
    @sut.unsafeCast(undefined_),
    @sut.unsafeCast(undefined_),
  )
  if test_hono_route_response(app, res) != "200:GET:/hello:text/plain;charset=UTF-8" {
    abort("unexpected Hono route response")
  }
}
