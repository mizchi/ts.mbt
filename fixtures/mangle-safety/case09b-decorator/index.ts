// A TypeScript-legacy property decorator. Split out of
// `case09-complex` because Node's transform mode cannot compile it —
// the `@log` token is the "Invalid or unexpected token" that cost that
// whole case its reference leg, and with it the only oracle independent
// of mtsc. Everything else in `case09-complex` runs against the
// original TypeScript now; this half cannot, and says so.
// Decorators
function log(target: any, propertyName: string | symbol): void {
  console.log(`log: ${propertyName.toString()}`);
}

export class DecoratorTest {
  @log
  private property: string = 'property';
}

const decoratorTest = new DecoratorTest();

