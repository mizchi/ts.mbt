export type ModifierName = "reset" | "bold";
export type Modifiers = ModifierName;

export declare function applyModifier(name: Modifiers): string;
