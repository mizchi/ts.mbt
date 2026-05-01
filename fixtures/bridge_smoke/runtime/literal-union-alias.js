export function renderButton(variant) {
  return variant === "solid" ? "ghost" : "solid";
}

export function maybeVariant(variant) {
  if (variant === undefined) return undefined;
  return renderButton(variant);
}
