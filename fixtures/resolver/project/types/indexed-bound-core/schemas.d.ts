export interface _$ZodTypeInternals {
    def: $ZodTypeDef;
}
export interface $ZodTypeInternals<out O = unknown, out I = unknown> extends _$ZodTypeInternals {
    output: O;
    input: I;
}
export interface $ZodTypeDef {
    type: "string" | "number";
}
export interface $ZodType<O = unknown, I = unknown, Internals extends $ZodTypeInternals<O, I> = $ZodTypeInternals<O, I>> {
    _zod: Internals;
}
