export { type PublicStyle } from "./transitive-style.ts";

export interface WebviewConfig {
  style: PublicStyle;
}

export declare function createStyle(id: string): PublicStyle;
