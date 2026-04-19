import { ResultAsync, type Result } from "neverthrow-like";

export interface User {
  id: string;
  name: string;
}

export declare function parseUser(input: string): Result<User, Error>;
export declare function fetchUser(id: string): ResultAsync<User, Error>;
