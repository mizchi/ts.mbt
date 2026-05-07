export declare class Widget {
  constructor(name: string);
}

export type DirectDouble = number;
export type NonNullName = NonNullable<string | undefined>;
export type AwaitedName = Awaited<Promise<string>>;
export type ReturnNumber = ReturnType<() => number>;
export type WidgetArgs = Parameters<(value: string) => void>;
export type WidgetInstance = InstanceType<typeof Widget>;
export type WidgetConstructorArgs = ConstructorParameters<typeof Widget>;

export function makeWidget(name: NonNullName): WidgetInstance;
