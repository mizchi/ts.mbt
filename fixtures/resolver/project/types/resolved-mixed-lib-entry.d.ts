import { PkgResultAsync, type PkgResult } from "pkg-mixed";

export interface User {
  id: string;
  name: string;
}

export declare function parseUser(input: string): PkgResult;
export declare function fetchUser(id: string): PkgResultAsync;
