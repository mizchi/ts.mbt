import { PkgSymlinkResultAsync, type PkgSymlinkResult } from "pkg-symlink";

export interface User {
  id: string;
  name: string;
}

export declare function parseUser(input: string): PkgSymlinkResult<User, Error>;
export declare function fetchUser(id: string): PkgSymlinkResultAsync<User, Error>;
