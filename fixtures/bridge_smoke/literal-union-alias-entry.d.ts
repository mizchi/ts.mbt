export type ButtonVariant = "solid" | "ghost";

export declare function renderButton(variant: ButtonVariant): ButtonVariant;
export declare function maybeVariant(
  variant?: ButtonVariant,
): ButtonVariant | undefined;
