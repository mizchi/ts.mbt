export interface Result<T, E> {
  readonly value: T;
  isOk(): boolean;
}

export interface ResultAsync<T, E> {
  readonly promiseValue: T;
  isOk(): boolean;
}

export interface User {
  id: string;
  name: string;
}

export declare function parseUser(input: string): Result<User, Error>;
export declare function fetchUser(id: string): ResultAsync<User, Error>;
