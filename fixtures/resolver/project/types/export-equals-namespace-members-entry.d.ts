declare module "node:path" {
  namespace path {
    const sep: string;
    function join(...paths: string[]): string;
    function basename(path: string, suffix?: string): string;
  }

  export = path;
}
