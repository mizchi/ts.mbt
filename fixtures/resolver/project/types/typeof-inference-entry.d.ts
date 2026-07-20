export type ErrorMessage<TIssue> = string | ((issue: TIssue) => string);

export interface IpIssue<TInput> {
  readonly kind: 'validation';
  readonly input: TInput;
}

export interface IpAction<TInput extends string, TMessage> {
  readonly type: 'ip';
  readonly reference: typeof ip;
  readonly message: TMessage;
}

export declare function ip<TInput extends string>(): IpAction<TInput, undefined>;
export declare function ip<TInput extends string, const TMessage extends ErrorMessage<IpIssue<TInput>> | undefined>(message: TMessage): IpAction<TInput, TMessage>;

export declare class Scalar {
  static readonly BLOCK_FOLDED = "BLOCK_FOLDED";
  static readonly PLAIN = "PLAIN";
  value: unknown;
}

declare function addPairToJSMap(ctx: object | undefined, map: unknown, value: unknown): unknown;
export declare class Pair {
  toJSON(_?: unknown, ctx?: object): ReturnType<typeof addPairToJSMap>;
}
