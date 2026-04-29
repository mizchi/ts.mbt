declare module "node:path" {
  namespace path {
    const sep: string;
    function join(...paths: string[]): string;
  }

  export = path;
}
