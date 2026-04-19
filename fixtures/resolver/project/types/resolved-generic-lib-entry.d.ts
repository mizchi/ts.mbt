import { PkgResultAsync, type PkgResult } from "pkg-generic";

export interface User {
  id: string;
  name: string;
}

export declare function parseUser(input: string): PkgResult<User, Error>;
export declare function fetchUser(id: string): PkgResultAsync<User, Error>;
