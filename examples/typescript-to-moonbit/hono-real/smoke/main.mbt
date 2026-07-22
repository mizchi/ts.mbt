fn test_hono_handler(
  c : @sut.Context[@sut.JSValue, @sut.JSValue, @sut.JSValue],
) -> @sut.Response {
  c.text("hi", None, None)
}

extern "js" fn test_undefined() -> @sut.JSValue =
  #| () => undefined

extern "js" fn test_hono_route_response(
  app : @sut.Hono[@sut.JSValue, @sut.JSValue, @sut.JSValue],
  res : @sut.JSValue,
) -> String =
  #| (app, res) => {
  #|   const route = app.routes[0];
  #|   return `${res.status}:${route.method}:${route.path}:${res.headers.get("content-type")}`;
  #| }

fn[A, B] test_unsafe_cast(value : A) -> B = "%identity"

fn main {
  let app : @sut.Hono[@sut.JSValue, @sut.JSValue, @sut.JSValue] = @sut.new_hono(
    None,
  )
  let _ = app.get("/hello", test_hono_handler)
  let undefined_ = test_undefined()
  let res = app.request(
    test_unsafe_cast("/hello"),
    test_unsafe_cast(undefined_),
    test_unsafe_cast(undefined_),
    test_unsafe_cast(undefined_),
  )
  if test_hono_route_response(app, res) != "200:GET:/hello:text/plain;charset=UTF-8" {
    abort("unexpected Hono route response")
  }
}
