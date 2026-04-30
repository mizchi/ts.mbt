function createElement(type, props, children) {
  return { type, props: props ?? null, children, key: null, ref: null };
}

function cloneElement(element, props, children) {
  return {
    ...element,
    props: { ...(element.props ?? {}), ...(props ?? {}) },
    children,
  };
}

function isValidElement(value) {
  return !!value && typeof value === "object" && "type" in value;
}

function memo(component) {
  return component;
}

function forwardRef(render) {
  return render;
}

function useState() {
  let state = undefined;
  return [state, (next) => {
    state = next;
  }];
}

function useTransition() {
  return [false, (scope) => scope()];
}

function startTransition(scope) {
  return scope();
}

const React = {
  createElement,
  cloneElement,
  isValidElement,
  memo,
  forwardRef,
  useState,
  useTransition,
  startTransition,
  Fragment: Symbol.for("react.fragment"),
  StrictMode: Symbol.for("react.strict_mode"),
  Suspense: Symbol.for("react.suspense"),
  version: "stub",
};

export {
  createElement,
  cloneElement,
  isValidElement,
  memo,
  forwardRef,
  useState,
  useTransition,
  startTransition,
};
export default React;
