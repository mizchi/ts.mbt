// The module a namespace import points at. Its export names are
// deliberately ordinary words that another module might also declare.
export const Number = (n: number): string => "shape-number:" + n;
export const Object = (k: string): string => "shape-object:" + k;
export const label = "shapes";
