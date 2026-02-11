// VM-level garbage collection for weak references and finalization

///|
/// Object registry entry - stores weak reference targets
priv struct VMGCEntry {
  id : Int
  mut marked : Bool
  target : JSValue // The actual object
}

///|
/// VM GC state - tracks all objects that can be weakly referenced
priv struct VMGCState {
  // Map from object ID to entry
  entries : Array[VMGCEntry]
  // FinalizationRegistry instances to check during GC
  finalization_registries : Array[JSValue]
  // WeakRef instances to clean up
  weak_refs : Array[JSValue]
  // WeakMap instances to clean up
  weak_maps : Array[JSValue]
  // WeakSet instances to clean up
  weak_sets : Array[JSValue]
}

///|
let vm_gc_state : VMGCState = {
  entries: [],
  finalization_registries: [],
  weak_refs: [],
  weak_maps: [],
  weak_sets: [],
}

///|
/// Reset VM GC state (for testing)
pub fn vm_gc_reset() -> Unit {
  vm_gc_state.entries.clear()
  vm_gc_state.finalization_registries.clear()
  vm_gc_state.weak_refs.clear()
  vm_gc_state.weak_maps.clear()
  vm_gc_state.weak_sets.clear()
}

///|
/// Register an object for potential weak referencing
pub fn vm_gc_register_object(obj : JSValue) -> Unit {
  let id = get_object_id(obj)
  if id < 0 {
    return
  }
  // Check if already registered
  for entry in vm_gc_state.entries {
    if entry.id == id {
      return
    }
  }
  vm_gc_state.entries.push({ id, marked: true, target: obj })
}

///|
/// Register a FinalizationRegistry for GC callbacks
pub fn vm_gc_register_finalization_registry(fr : JSValue) -> Unit {
  vm_gc_state.finalization_registries.push(fr)
}

///|
/// Register a WeakRef for cleanup
pub fn vm_gc_register_weak_ref(wr : JSValue) -> Unit {
  vm_gc_state.weak_refs.push(wr)
}

///|
/// Register a WeakMap for cleanup
pub fn vm_gc_register_weak_map(wm : JSValue) -> Unit {
  vm_gc_state.weak_maps.push(wm)
}

///|
/// Register a WeakSet for cleanup
pub fn vm_gc_register_weak_set(ws : JSValue) -> Unit {
  vm_gc_state.weak_sets.push(ws)
}

///|
/// Get object ID from JSValue
fn get_object_id(val : JSValue) -> Int {
  match val {
    Object(map) => map.id
    JSValue::Array(arr) => arr.id
    Function(f) => f.id
    _ => -1
  }
}

///|
/// Check if an object ID is still alive (not collected)
pub fn vm_gc_is_alive(id : Int) -> Bool {
  for entry in vm_gc_state.entries {
    if entry.id == id {
      return true
    }
  }
  false
}

///|
/// Get object by ID if it's still alive
pub fn vm_gc_get_object(id : Int) -> JSValue? {
  for entry in vm_gc_state.entries {
    if entry.id == id {
      return Some(entry.target)
    }
  }
  None
}

///|
/// Track visited objects during marking to avoid infinite recursion
let mark_visited : Array[Int] = []

///|
/// Mark an object and all objects it references
fn vm_gc_mark_object(val : JSValue) -> Unit {
  let id = get_object_id(val)
  if id < 0 {
    return
  }
  // Check if already visited (handles circular references)
  if mark_visited.contains(id) {
    return
  }
  mark_visited.push(id)
  // Find entry and mark it (if registered)
  for entry in vm_gc_state.entries {
    if entry.id == id {
      entry.marked = true
      break
    }
  }
  // Mark referenced objects
  match val {
    Object(map) => {
      for prop in map.props {
        vm_gc_mark_value(prop.value)
      }
      match map.prototype {
        Some(proto) => vm_gc_mark_object(proto)
        None => ()
      }
    }
    JSValue::Array(arr) => {
      for item in arr.items {
        vm_gc_mark_value(item)
      }
      for prop in arr.props {
        vm_gc_mark_value(prop.value)
      }
      match arr.prototype {
        Some(proto) => vm_gc_mark_object(proto)
        None => ()
      }
    }
    Function(closure) => {
      for prop in closure.props {
        vm_gc_mark_value(prop.value)
      }
      match closure.object_proto {
        Some(proto) => vm_gc_mark_object(proto)
        None => ()
      }
      // Mark bound values
      match closure.body {
        Bound(target, this_arg, args) => {
          vm_gc_mark_value(target)
          vm_gc_mark_value(this_arg)
          for arg in args {
            vm_gc_mark_value(arg)
          }
        }
        _ => ()
      }
    }
    _ => ()
  }
}

///|
/// Mark a value (handles both objects and primitives)
fn vm_gc_mark_value(val : JSValue) -> Unit {
  match val {
    Object(_) | JSValue::Array(_) | Function(_) => vm_gc_mark_object(val)
    _ => ()
  }
}

///|
/// Mark all objects reachable from an environment
fn vm_gc_mark_env(env : JSEnv) -> Unit {
  for binding in env.bindings {
    vm_gc_mark_value(binding.value)
  }
  match env.parent {
    Some(parent) => vm_gc_mark_env(parent)
    None => ()
  }
}

///|
/// Perform GC: mark reachable objects from roots, sweep unreachable
/// Returns list of collected object IDs
pub fn vm_gc_collect(roots : Array[JSValue], root_env : JSEnv?) -> Array[Int] {
  // Phase 0: Clear visited tracking
  mark_visited.clear()
  // Phase 1: Unmark all entries
  for entry in vm_gc_state.entries {
    entry.marked = false
  }
  // Phase 2: Mark from roots
  for root in roots {
    vm_gc_mark_value(root)
  }
  match root_env {
    Some(env) => vm_gc_mark_env(env)
    None => ()
  }
  // Phase 3: Collect unmarked entries
  let collected : Array[Int] = []
  let remaining : Array[VMGCEntry] = []
  for entry in vm_gc_state.entries {
    if entry.marked {
      remaining.push(entry)
    } else {
      collected.push(entry.id)
    }
  }
  // Update entries
  vm_gc_state.entries.clear()
  for entry in remaining {
    vm_gc_state.entries.push(entry)
  }
  collected
}

///|
/// Clean up WeakRefs pointing to collected objects
pub fn vm_gc_cleanup_weak_refs(collected : Array[Int]) -> Unit {
  for wr in vm_gc_state.weak_refs {
    match js_get_prop(wr, "__weakref_target") {
      Object(map) if collected.contains(map.id) => {
        let _ = js_set_prop(wr, "__weakref_target", Undefined)
      }
      JSValue::Array(arr) if collected.contains(arr.id) => {
        let _ = js_set_prop(wr, "__weakref_target", Undefined)
      }
      Function(f) if collected.contains(f.id) => {
        let _ = js_set_prop(wr, "__weakref_target", Undefined)
      }
      _ => ()
    }
  }
}

///|
/// Clean up WeakMap entries pointing to collected objects
pub fn vm_gc_cleanup_weak_maps(collected : Array[Int]) -> Unit {
  for wm in vm_gc_state.weak_maps {
    match js_get_prop(wm, "__weakmap_entries") {
      JSValue::Array(arr) => {
        let mut i = 0
        while i < arr.length {
          match arr.items[i] {
            JSValue::Array(pair) if pair.length >= 2 =>
              match pair.items[0] {
                Number(id) if collected.contains(id.to_int()) => {
                  let _ = arr.items.remove(i)
                  arr.length = arr.length - 1
                  continue
                }
                _ => ()
              }
            _ => ()
          }
          i = i + 1
        }
      }
      _ => ()
    }
  }
}

///|
/// Clean up WeakSet entries pointing to collected objects
pub fn vm_gc_cleanup_weak_sets(collected : Array[Int]) -> Unit {
  for ws in vm_gc_state.weak_sets {
    match js_get_prop(ws, "__weakset_entries") {
      JSValue::Array(arr) => {
        let mut i = 0
        while i < arr.length {
          match arr.items[i] {
            Number(id) if collected.contains(id.to_int()) => {
              let _ = arr.items.remove(i)
              arr.length = arr.length - 1
              continue
            }
            _ => ()
          }
          i = i + 1
        }
      }
      _ => ()
    }
  }
}

///|
/// Get pending FinalizationRegistry callbacks for collected objects
/// Returns array of (callback, heldValue) pairs
pub fn vm_gc_get_finalization_callbacks(
  collected : Array[Int],
) -> Array[(JSValue, JSValue)] {
  let callbacks : Array[(JSValue, JSValue)] = []
  for fr in vm_gc_state.finalization_registries {
    let callback = js_get_prop(fr, "__fr_callback")
    match js_get_prop(fr, "__fr_registrations") {
      JSValue::Array(arr) => {
        let mut i = 0
        while i < arr.length {
          match arr.items[i] {
            JSValue::Array(entry) if entry.length >= 3 =>
              match entry.items[0] {
                Number(target_id) if collected.contains(target_id.to_int()) => {
                  // Target was collected - add callback
                  let held_value = entry.items[1]
                  callbacks.push((callback, held_value))
                  // Remove this registration
                  let _ = arr.items.remove(i)
                  arr.length = arr.length - 1
                  continue
                }
                _ => ()
              }
            _ => ()
          }
          i = i + 1
        }
      }
      _ => ()
    }
  }
  callbacks
}
