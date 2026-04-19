import { InternalMap } from "./transitive-internal-map.ts";

export interface PublicStyle {
  id: string;
}

export const styleCache = new InternalMap<string, string>();
