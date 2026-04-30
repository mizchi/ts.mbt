export interface Context {
  text(body: string): Response;
}

export interface Response {
  status: number;
}

export interface Handler {
  (ctx: Context): Response;
}

export interface RouteHandler {
  (path: string, handler: Handler): Router;
}

declare class Router {
  get: RouteHandler;
  request(input: string): Response;
}

export { Router as RouterBase };
