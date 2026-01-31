// JS lexical environment and bindings.

///|
// /
pub struct JSBinding {
  name : String
  mut value : JSValue
  mut is_const : Bool
  mut is_uninitialized : Bool
} derive(Show)

///|
// /
pub struct JSEnv {
  parent : JSEnv?
  bindings : Array[JSBinding]
} derive(Show)

///|
// / create
pub fn js_new_env(parent : JSEnv?) -> JSEnv {
  gc_stats_inc_env()
  { parent, bindings: [] }
}

///|
// / variabledefine
pub fn JSEnv::define_var(self : JSEnv, name : String, value : JSValue) -> Unit {
  self.bindings.push({ name, value, is_const: false, is_uninitialized: false })
}

///|
pub fn JSEnv::define_const(
  self : JSEnv,
  name : String,
  value : JSValue,
) -> Unit {
  self.bindings.push({ name, value, is_const: true, is_uninitialized: false })
}

///|
pub fn JSEnv::define_uninitialized(
  self : JSEnv,
  name : String,
  is_const : Bool,
) -> Unit {
  self.bindings.push({
    name,
    value: Undefined,
    is_const,
    is_uninitialized: true,
  })
}

///|
pub fn JSEnv::initialize(
  self : JSEnv,
  name : String,
  value : JSValue,
  is_const : Bool,
) -> Unit {
  // First check local bindings
  let len = self.bindings.length()
  let mut i = len - 1
  while i >= 0 {
    if self.bindings[i].name == name {
      self.bindings[i].value = value
      self.bindings[i].is_const = is_const
      self.bindings[i].is_uninitialized = false
      return
    }
    i -= 1
  }
  // If not found locally, recursively check parent chain
  // (for var declarations hoisted to outer scope)
  match self.parent {
    Some(parent) =>
      if parent.has(name) {
        // Recursively initialize in parent (will find the correct scope)
        parent.initialize(name, value, is_const)
        return
      }
    None => ()
  }
  // Create new binding if not found anywhere
  self.bindings.push({ name, value, is_const, is_uninitialized: false })
}

///|
/// Check if binding exists locally (not in parent)
pub fn JSEnv::has_local(self : JSEnv, name : String) -> Bool {
  let len = self.bindings.length()
  let mut i = len - 1
  while i >= 0 {
    if self.bindings[i].name == name {
      return true
    }
    i -= 1
  }
  false
}

///|
// / variablecheck
pub fn JSEnv::has(self : JSEnv, name : String) -> Bool {
  let len = self.bindings.length()
  let mut i = len - 1
  let mut with_target : JSValue? = None
  while i >= 0 {
    if self.bindings[i].name == name {
      return true
    }
    if self.bindings[i].name == WITH_BINDING_NAME {
      with_target = Some(self.bindings[i].value)
    }
    i -= 1
  }
  match with_target {
    Some(obj) => if js_has_prop(obj, name) { return true }
    None => ()
  }
  match self.parent {
    Some(parent) => parent.has(name)
    None => false
  }
}

///|
// / variableforceupdate
pub fn JSEnv::force_set(self : JSEnv, name : String, value : JSValue) -> Bool {
  let len = self.bindings.length()
  let mut i = len - 1
  while i >= 0 {
    if self.bindings[i].name == name {
      self.bindings[i].value = value
      self.bindings[i].is_uninitialized = false
      return true
    }
    i -= 1
  }
  self.define_var(name, value)
  true
}

///|
pub fn JSEnv::is_const(self : JSEnv, name : String) -> Bool {
  let len = self.bindings.length()
  let mut i = len - 1
  while i >= 0 {
    if self.bindings[i].name == name {
      return self.bindings[i].is_const
    }
    i -= 1
  }
  match self.parent {
    Some(parent) => parent.is_const(name)
    None => false
  }
}

///|
pub fn JSEnv::is_uninitialized(self : JSEnv, name : String) -> Bool {
  let len = self.bindings.length()
  let mut i = len - 1
  while i >= 0 {
    if self.bindings[i].name == name {
      return self.bindings[i].is_uninitialized
    }
    i -= 1
  }
  match self.parent {
    Some(parent) => parent.is_uninitialized(name)
    None => false
  }
}
