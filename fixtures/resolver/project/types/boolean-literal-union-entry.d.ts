export type FeatureFlag = true | false;
export type AlwaysOn = true | undefined;

export declare function flipFlag(flag: FeatureFlag): FeatureFlag;
export declare function maybeAlways(flag?: AlwaysOn): AlwaysOn;
