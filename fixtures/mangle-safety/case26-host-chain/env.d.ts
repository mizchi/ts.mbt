declare const HostBridge: {
  channel: {
    post(msg: { tickKind: string; tickAmount: number }): { echoedValue: number };
  };
};
