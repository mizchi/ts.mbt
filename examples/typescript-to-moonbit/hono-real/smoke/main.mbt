fn[A, B] test_unsafe_cast(value : A) -> B = "%identity"

fn test_hono_handler(
  c : @sut.Context[@sut.JSValue, @sut.JSValue, @sut.JSValue],
) -> @sut.Response {
  test_unsafe_cast(c.text(test_unsafe_cast("hi"), None, None))
}

extern "js" fn test_undefined() -> @sut.JSValue =
  #| () => undefined

extern "js" fn test_hono_route_response(
  app : @sut.Hono[@sut.JSValue, @sut.JSValue, @sut.JSValue],
) -> String =
  #| (app) => {
  #|   const route = app.routes[0];
  #|   return `${route.method}:${route.path}`;
  #| }

fn main {
  let app : @sut.Hono[@sut.JSValue, @sut.JSValue, @sut.JSValue] = @sut.new_hono(
    None,
  )
  let _ = app.get("/hello", test_hono_handler)
  let undefined_ = test_undefined()
  let _ : @sut.Promise[@sut.Response] = app.request(
    test_unsafe_cast("/hello"),
    test_unsafe_cast(undefined_),
    test_unsafe_cast(undefined_),
    test_unsafe_cast(undefined_),
  )
  if test_hono_route_response(app) != "GET:/hello" {
    abort("unexpected Hono route response")
  }
}
