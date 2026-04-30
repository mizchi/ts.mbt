declare module "type-only-alias-value" {
  type Color = (text: string | number) => string;
  const red: Color;
}
