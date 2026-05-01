export type StableName = "a-b" | "a_b" | "String" | "_private" | "";

export declare function cycleName(value: StableName): StableName;
