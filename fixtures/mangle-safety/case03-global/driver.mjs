// Call through to the ambient global so the names reached via
// `MyGlobal.f({ x })` are actually observed.
export default async (mod) => ({ foo: mod.foo() });
