extern "js" fn test_hono_route(app : @sut.Hono) -> String =
  #| (app) => {
  #|   app.get("/hello", c => c.text("hi"));
  #|   const res = app.request("/hello");
  #|   const route = app.routes[0];
  #|   return `${res.status}:${route.method}:${route.path}:${res.headers.get("content-type")}`;
  #| }

fn main {
  let app = @sut.new_hono(None)
  if test_hono_route(app) != "200:GET:/hello:text/plain;charset=UTF-8" {
    abort("unexpected Hono route response")
  }
}

