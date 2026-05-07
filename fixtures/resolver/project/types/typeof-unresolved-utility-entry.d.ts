export interface ZodCustom<Output, Input> {}

export declare function instanceOf(
  cls: unknown,
): ZodCustom<InstanceType<typeof cls>, InstanceType<typeof cls>>;
