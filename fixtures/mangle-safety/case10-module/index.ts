// `namespace`, not the legacy `module` keyword. The two lower
// identically, and the block below already covers `namespace`, so the
// keyword was the only unique thing here — while Node's transform mode
// rejects it outright ("`module` keyword is not supported"), which cost
// this case its reference leg and so its only independent oracle. The
// keyword's parse is pinned in `bundle_wbtest.mbt` instead.
namespace InternalModule {
  const internalMessage = "Hello from internal module";

  export function getInternalMessage(): string {
    return internalMessage;
  }
}

// Namespace
namespace MyNamespace {
  export const namespaceMessage = "Hello from namespace";

  export function getNamespaceMessage(): string {
    return namespaceMessage;
  }
}

// Global augmentation of the 'window' object
declare global {
  interface Window {
    myCustomFunction?: () => string;
  }
}

window.myCustomFunction = () => "Hello from custom function";

export const messages = {
  internal: InternalModule.getInternalMessage(),
  namespace: MyNamespace.getNamespaceMessage(),
  window: window.myCustomFunction ? window.myCustomFunction() : "",
};

import * as myModule from "myModule";

const result = myModule.myFunction("Hello, TypeScript!");

console.log(result);
