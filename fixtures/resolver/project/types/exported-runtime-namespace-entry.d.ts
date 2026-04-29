declare module "runtime-namespace" {
  function task(input: string): string;
  namespace task {
    interface Options {
      strict?: boolean;
    }
    function extra(input: string): string;
  }
  namespace constants {
    const read: number;
  }
}
