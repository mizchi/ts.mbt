export type Params<Key extends string = string> = {
  readonly [key in Key]: string | undefined;
};

export interface RouteMatchLike<ParamKey extends string = string> {
  params: Params<ParamKey>;
  pathname: string;
}
