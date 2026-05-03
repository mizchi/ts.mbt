extern "js" fn test_children() -> Array[@sut.JSValue] =
  #| () => ["child"]

extern "js" fn test_props() -> @sut.JSValue =
  #| () => ({ id: "root" })

extern "js" fn test_function_component() -> @sut.FunctionComponent =
  #| () => (props) => ({ type: "component", props, key: null, ref: null })

extern "js" fn test_forward_ref_render() -> @sut.ForwardRefRenderFunction =
  #| () => (props, ref) => ({ type: "forward", props, key: null, ref })

extern "js" fn test_transition_scope() -> @sut.TransitionFunction =
  #| () => () => undefined

fn main {
  let element = @sut.createElement("div", Some(test_props()), test_children())
  let _ = @sut.cloneElement(element, None, test_children())
  if !@sut.isValidElement(@sut.unsafeCast(element)) {
    abort("expected generated React element to be valid")
  }
  let _ = @sut.memo(test_function_component(), None)
  let _ = @sut.forwardRef(test_forward_ref_render())
  @sut.startTransition(test_transition_scope())
  let _ = @sut.get_default()
}
