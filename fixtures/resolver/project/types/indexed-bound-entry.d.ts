import * as core from "./indexed-bound-core/index.js";
export interface ZodType<out Output = unknown, out Input = unknown, out Internals extends core.$ZodTypeInternals<Output, Input> = core.$ZodTypeInternals<Output, Input>> extends core.$ZodType<Output, Input, Internals> {
    def: Internals["def"];
    type: Internals["def"]["type"];
}
export declare function make(): ZodType;
