// Perceus-style scope-based garbage collection
// Objects are cleaned up immediately when their scope exits (if they haven't escaped)

///|
/// Scope entry - tracks objects created in this scope
priv struct ScopeEntry {
  id : Int
  object_ids : Array[Int] // Objects created in this scope
}

///|
/// Perceus GC state
priv struct PerceusState {
  mut next_scope_id : Int
  scope_stack : Array[ScopeEntry]
  // Map from object ID to scope ID where it was created
  object_scopes : Array[(Int, Int)]
  // Objects that have escaped their scope (returned, assigned to outer scope)
  escaped_objects : Array[Int]
}

///|
let perceus_state : PerceusState = {
  next_scope_id: 1,
  scope_stack: [],
  object_scopes: [],
  escaped_objects: [],
}

///|
/// Reset Perceus state (for testing)
pub fn perceus_reset() -> Unit {
  perceus_state.next_scope_id = 1
  perceus_state.scope_stack.clear()
  perceus_state.object_scopes.clear()
  perceus_state.escaped_objects.clear()
}

///|
/// Enter a new scope - call when entering block, function, etc.
pub fn perceus_enter_scope() -> Int {
  let scope_id = perceus_state.next_scope_id
  perceus_state.next_scope_id = perceus_state.next_scope_id + 1
  perceus_state.scope_stack.push({ id: scope_id, object_ids: [] })
  scope_id
}

///|
/// Get current scope ID (or 0 if no scope)
pub fn perceus_current_scope() -> Int {
  let len = perceus_state.scope_stack.length()
  if len > 0 {
    perceus_state.scope_stack[len - 1].id
  } else {
    0
  }
}

///|
/// Register an object in the current scope
pub fn perceus_register_object(obj_id : Int) -> Unit {
  let scope_id = perceus_current_scope()
  if scope_id > 0 {
    // Add to current scope's object list
    let len = perceus_state.scope_stack.length()
    if len > 0 {
      perceus_state.scope_stack[len - 1].object_ids.push(obj_id)
    }
    // Record which scope created this object
    perceus_state.object_scopes.push((obj_id, scope_id))
  }
}

///|
/// Mark an object as escaped (it was returned or assigned to outer scope)
pub fn perceus_mark_escaped(obj_id : Int) -> Unit {
  if not(perceus_state.escaped_objects.contains(obj_id)) {
    perceus_state.escaped_objects.push(obj_id)
  }
}

///|
/// Check if an object has escaped its scope
fn perceus_has_escaped(obj_id : Int) -> Bool {
  perceus_state.escaped_objects.contains(obj_id)
}

///|
/// Leave current scope and cleanup unreachable objects
/// Returns list of object IDs that should be cleaned up
pub fn perceus_leave_scope() -> Array[Int] {
  let len = perceus_state.scope_stack.length()
  if len == 0 {
    return []
  }
  // Pop the scope
  let scope = perceus_state.scope_stack.remove(len - 1)
  // Find objects that haven't escaped
  let to_cleanup : Array[Int] = []
  for obj_id in scope.object_ids {
    if not(perceus_has_escaped(obj_id)) {
      to_cleanup.push(obj_id)
    }
  }
  // Remove scope entries for cleaned up objects
  let remaining_scopes : Array[(Int, Int)] = []
  for pair in perceus_state.object_scopes {
    let (obj_id, _scope_id) = pair
    if not(to_cleanup.contains(obj_id)) {
      remaining_scopes.push(pair)
    }
  }
  perceus_state.object_scopes.clear()
  for pair in remaining_scopes {
    perceus_state.object_scopes.push(pair)
  }
  to_cleanup
}

///|
/// Cleanup weak collections for the given object IDs
/// This is called when leaving a scope with objects to cleanup
pub fn perceus_cleanup_objects(object_ids : Array[Int]) -> Unit {
  if object_ids.length() == 0 {
    return
  }
  // Use the VM GC cleanup functions
  vm_gc_cleanup_weak_refs(object_ids)
  vm_gc_cleanup_weak_maps(object_ids)
  vm_gc_cleanup_weak_sets(object_ids)
}

///|
/// Get object ID from JSValue (reuse from vm_gc)
fn perceus_get_object_id(val : JSValue) -> Int {
  match val {
    Object(map) => map.id
    JSValue::Array(arr) => arr.id
    Function(f) => f.id
    _ => -1
  }
}

///|
/// Register a JSValue in the current scope (convenience function)
pub fn perceus_track_object(val : JSValue) -> Unit {
  let id = perceus_get_object_id(val)
  if id >= 0 {
    perceus_register_object(id)
    // Also register with VM GC for finalization support
    vm_gc_register_object(val)
  }
}

///|
/// Mark a JSValue as escaped (convenience function)
pub fn perceus_mark_value_escaped(val : JSValue) -> Unit {
  let id = perceus_get_object_id(val)
  if id >= 0 {
    perceus_mark_escaped(id)
  }
}

///|
/// Leave scope and run cleanup (convenience function that combines leave + cleanup)
pub fn perceus_exit_scope_with_cleanup() -> Int {
  let to_cleanup = perceus_leave_scope()
  let count = to_cleanup.length()
  perceus_cleanup_objects(to_cleanup)
  count
}

///|
/// Leave scope with a return value - marks the return value as escaped
pub fn perceus_exit_scope_with_return(return_val : JSValue) -> Int {
  // Mark return value as escaped before leaving scope
  perceus_mark_value_escaped(return_val)
  // Also mark any objects contained in the return value
  perceus_mark_contained_objects_escaped(return_val)
  perceus_exit_scope_with_cleanup()
}

///|
/// Recursively mark objects contained in a value as escaped
fn perceus_mark_contained_objects_escaped(val : JSValue) -> Unit {
  match val {
    Object(map) => {
      for prop in map.props {
        let prop_id = perceus_get_object_id(prop.value)
        if prop_id >= 0 {
          perceus_mark_escaped(prop_id)
          perceus_mark_contained_objects_escaped(prop.value)
        }
      }
    }
    JSValue::Array(arr) => {
      for item in arr.items {
        let item_id = perceus_get_object_id(item)
        if item_id >= 0 {
          perceus_mark_escaped(item_id)
          perceus_mark_contained_objects_escaped(item)
        }
      }
    }
    Function(closure) => {
      for prop in closure.props {
        let prop_id = perceus_get_object_id(prop.value)
        if prop_id >= 0 {
          perceus_mark_escaped(prop_id)
        }
      }
    }
    _ => ()
  }
}
