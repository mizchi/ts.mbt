// @strict: true
// @target: esnext
// @noImplicitOverride: true

// `override` through an intersection-returning mixin: TS4113 for a member
// the intersection lacks, and under `noImplicitOverride` TS4114 for one it
// has but that is written without `override`.

type Foo = abstract new(...args: any) => any;
declare function CreateMixin<C extends Foo, T extends Foo>(Context: C, Base: T): T & { new (...args: any[]): { context: InstanceType<C> } }
class Context {}
class A { doSomething() {} }
class Bad extends CreateMixin(Context, A) { override foo() {} }
class OkOverride extends CreateMixin(Context, A) { override doSomething() {} }
class OkContext extends CreateMixin(Context, A) { override context: Context = new Context(); }
class BadNoModifier extends CreateMixin(Context, A) { doSomething() {} }
