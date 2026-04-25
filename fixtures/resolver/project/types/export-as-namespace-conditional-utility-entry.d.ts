declare namespace ReactLike {
  type ComponentRef<T extends ElementType> =
    ComponentPropsWithRef<T> extends RefAttributes<infer Method> ? Method
    : never;

  type LibraryManagedAttributes<C, P> = C extends
    ReactLike.MemoExoticComponent<infer T> | ReactLike.LazyExoticComponent<
      infer T
    >
      ? T extends
          ReactLike.MemoExoticComponent<infer U> | ReactLike.LazyExoticComponent<
            infer U
          >
          ? ReactManagedAttributes<U, P>
          : ReactManagedAttributes<T, P>
      : ReactManagedAttributes<C, P>;
}

export = ReactLike;
export as namespace ReactLike;
