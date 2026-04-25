export interface RuntimeImportedOptions {
  basePath: string;
}

export class RuntimeImported {
  constructor(_options: RuntimeImportedOptions = { basePath: "/" }) {}
}
