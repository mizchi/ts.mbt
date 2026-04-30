declare module "declaration-merge-namespace" {
  export function make(input: string): string;
  export namespace make {
    export interface Options {
      uppercase?: boolean;
    }
    export const version: string;
    export function withOptions(input: string, options: Options): string;
  }

  export class Tool {
    constructor(name: string);
    run(input: string): string;
    static create(name: string): Tool;
  }
  export namespace Tool {
    export interface Config {
      label: string;
    }
    export const version: string;
    export function parse(input: string): Tool;
  }

  export interface Settings {
    mode: string;
  }
  export const settings: Settings;
  export namespace settings {
    export interface Meta {
      source: string;
    }
    export const defaultMode: string;
    export function normalize(input: string): string;
  }
}
