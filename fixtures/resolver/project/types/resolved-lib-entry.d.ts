import { type PkgTypesValue } from "pkg-types";

export interface User {
  id: string;
  name: string;
}

export declare function parseUser(input: string): PkgTypesValue;
