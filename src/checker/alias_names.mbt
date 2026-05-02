// Pure name-based predicates extracted from the bridge generator. They
// recognize TypeScript alias names that the structural lowering passes need to
// special-case. Keeping them here lets parser, bridge, and any future
// type-checking pass share the same definitions.

///|
pub fn is_qualified_react_node_name(name : String) -> Bool {
  name.has_suffix(".ReactNode") && name.length() > ".ReactNode".length()
}

///|
pub fn is_react_node_like_name(name : String) -> Bool {
  name == "ReactNode" || name.has_suffix(".ReactNode")
}

///|
pub fn is_event_handler_alias_name(name : String) -> Bool {
  name == "EventHandler" || name.has_suffix("EventHandler")
}

///|
pub fn is_signalish_alias_name(name : String) -> Bool {
  name == "Signalish" || name.has_suffix(".Signalish")
}

///|
pub fn is_params_alias_name(name : String) -> Bool {
  name == "Params" || name.has_suffix(".Params")
}

///|
pub fn is_ref_alias_name(name : String) -> Bool {
  name == "Ref" || name.has_suffix(".Ref")
}

///|
pub fn is_props_passthrough_name(name : String) -> Bool {
  name == "PropsWithoutRef" || name == "PropsWithRef"
}

///|
pub fn is_mapped_interface_utility_name(name : String) -> Bool {
  name == "Partial" || name == "Required" || name == "Readonly"
}

///|
pub fn is_component_ref_like_name(name : String) -> Bool {
  name == "ComponentRef" || name == "ElementRef"
}
