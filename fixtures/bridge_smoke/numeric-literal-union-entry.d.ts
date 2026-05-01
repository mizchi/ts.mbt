export type StatusCode = 200 | 404;

export declare function nextStatus(code: StatusCode): StatusCode;
export declare function maybeStatus(code?: StatusCode): StatusCode | undefined;
