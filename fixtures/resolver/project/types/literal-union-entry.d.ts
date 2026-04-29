export interface ButtonOptions {
  variant?: "solid" | "ghost";
  disabled?: true | false;
}

export declare function renderButton(
  variant: "solid" | "ghost",
  options?: ButtonOptions,
): "ok" | "skip";
