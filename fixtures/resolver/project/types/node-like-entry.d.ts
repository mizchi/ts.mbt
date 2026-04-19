export interface RuntimeConfig {
  env: NodeJS.ProcessEnv;
}

export declare class NodeRunner {
  readonly env: NodeJS.ProcessEnv;
  constructor(env: NodeJS.ProcessEnv);
  hasEnv(key: string): boolean;
}

export declare function hasEnv(
  env: NodeJS.ProcessEnv,
  key: string,
): boolean;
