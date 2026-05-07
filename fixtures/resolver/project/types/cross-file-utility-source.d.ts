// Models the puppeteer / better-auth pattern: a sub-module exports a
// concrete options interface that consumers project with `Omit<...>`
// or `Pick<...>` from across the namespace boundary.
export interface CallFunctionParameters {
  functionDeclaration: string;
  awaitPromise: boolean;
  target: string;
  arguments: Array<string>;
  thisArgument: string;
}
