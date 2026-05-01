export interface CounterState {
  count: number;
  label: string;
}

export interface IncrementAction {
  type: "increment";
  amount: number;
}

export interface RenameAction {
  type: "rename";
  label: string;
}

export interface ResetAction {
  type: "reset";
}

export type CounterAction = IncrementAction | RenameAction | ResetAction;

export declare function reducer(
  state: CounterState,
  action: CounterAction,
): CounterState;

export declare function actionKind(action: CounterAction): string;
