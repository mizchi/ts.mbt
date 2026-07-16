export interface $IssueBase {
    readonly path: string[];
    readonly message: string;
}
export interface $IssueTooBig extends $IssueBase {
    readonly code: "too_big";
}
export interface $IssueTooSmall extends $IssueBase {
    readonly code: "too_small";
}
interface $IssueNoMatch extends $IssueBase {
    readonly code: "no_match";
}
interface $IssueMultiMatch extends $IssueBase {
    readonly code: "multi_match";
}
export type $IssueUnionKind = $IssueNoMatch | $IssueMultiMatch;
export type $Issue = $IssueTooBig | $IssueTooSmall | $IssueUnionKind;
export interface Report {
    issues: $Issue[];
}
export declare function report(): Report;
