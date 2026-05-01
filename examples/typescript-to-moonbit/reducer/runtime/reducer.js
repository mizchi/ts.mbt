export function reducer(state, action) {
  switch (action.type) {
    case "increment":
      return { count: state.count + action.amount, label: state.label };
    case "rename":
      return { count: state.count, label: action.label };
    case "reset":
      return { count: 0, label: "idle" };
    default:
      throw new Error(`unexpected action: ${action.type}`);
  }
}

export function actionKind(action) {
  return action.type;
}
