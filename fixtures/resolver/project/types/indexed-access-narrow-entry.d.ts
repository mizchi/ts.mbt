export interface ParamsLike {
  routeId: string;
}

export interface RouteMatch {
  id: string;
  pathname: string;
  params: ParamsLike;
}

export interface UIMatch {
  pathname: string;
  params: RouteMatch["params"];
}
