export interface Issue {
  readonly kind: string;
  readonly text: string;
}

export type ErrorMessage<TIssue> = string | ((issue: TIssue) => string);

export interface CheckAction {
  readonly message: ErrorMessage<Issue> | undefined;
  readonly expects: null;
}

export declare function check(message?: ErrorMessage<Issue>): CheckAction;
