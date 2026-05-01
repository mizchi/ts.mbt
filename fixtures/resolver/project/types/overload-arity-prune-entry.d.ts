export interface StatOptions {
  bigint?: boolean | undefined;
}

export interface Stats {}

export interface BigIntStats {}

export declare function fstatSync(fd: number): Stats;
export declare function fstatSync(
  fd: number,
  options?: StatOptions & { bigint?: false | undefined },
): Stats;
export declare function fstatSync(
  fd: number,
  options: StatOptions & { bigint: true },
): BigIntStats;
export declare function fstatSync(
  fd: number,
  options?: StatOptions,
): Stats | BigIntStats;
