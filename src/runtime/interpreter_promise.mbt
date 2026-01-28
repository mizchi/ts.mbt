// Promise and microtask queue support

const PROMISE_CLASS : String = "Promise"
const PROMISE_STATE_KEY : String = "__promise_state"
const PROMISE_RESULT_KEY : String = "__promise_result"
const PROMISE_FULFILL_REACTIONS_KEY : String = "__promise_fulfill_reactions"
const PROMISE_REJECT_REACTIONS_KEY : String = "__promise_reject_reactions"
const PROMISE_REACTION_HANDLER_KEY : String = "__promise_handler"
const PROMISE_REACTION_PROMISE_KEY : String = "__promise_promise"
const PROMISE_REACTION_IS_REJECT_KEY : String = "__promise_is_reject"

///|
// / microtask enqueue
fn JSInterpreter::enqueue_promise_job(
  self : JSInterpreter,
  handler : JSValue,
  argument : JSValue,
  promise : JSValue,
  is_reject : Bool,
) -> Unit {
  self.microtasks.push({ handler, argument, promise: Some(promise), is_reject })
}

///|
// / microtask drain
pub fn JSInterpreter::drain_microtasks(self : JSInterpreter) -> Unit {
  match self.last_error {
    Some(_) => ()
    None => {
      let mut index = 0
      while index < self.microtasks.length() {
        let job = self.microtasks[index]
        index = index + 1
        self.run_microtask_job(job)
        match self.last_error {
          Some(_) => break
          None => ()
        }
      }
      if index > 0 {
        self.microtasks = []
      }
    }
  }
}

///|
// / microtask run
fn JSInterpreter::run_microtask_job(self : JSInterpreter, job : MicrotaskJob) -> Unit {
  fn get_capability(
    self : JSInterpreter,
    promise : JSValue,
  ) -> (JSValue?, JSValue?) {
    let resolve = js_get_prop(promise, "__promise_cap_resolve__")
    let reject = js_get_prop(promise, "__promise_cap_reject__")
    let cap_resolve = if self.is_callable(resolve) { Some(resolve) } else { None }
    let cap_reject = if self.is_callable(reject) { Some(reject) } else { None }
    (cap_resolve, cap_reject)
  }
  if self.is_callable(job.handler) {
    let result = self.call_function(job.handler, Undefined, [job.argument])
    match self.peek_error() {
      Some(err) => {
        match job.promise {
          Some(promise) => {
            self.last_error = None
            let (_cap_resolve, cap_reject) = get_capability(self, promise)
            match cap_reject {
              Some(reject) => {
                let _ = self.call_function(reject, Undefined, [err])
              }
              None => self.promise_reject(promise, err)
            }
          }
          None => ()
        }
      }
      None =>
        match job.promise {
          Some(promise) => {
            let (cap_resolve, _cap_reject) = get_capability(self, promise)
            match cap_resolve {
              Some(resolve) => {
                let _ = self.call_function(resolve, Undefined, [result])
              }
              None => self.promise_resolve_value(promise, result)
            }
          }
          None => ()
        }
    }
  } else {
    match job.promise {
      Some(promise) => {
        let (cap_resolve, cap_reject) = get_capability(self, promise)
        if job.is_reject {
          match cap_reject {
            Some(reject) => {
              let _ = self.call_function(reject, Undefined, [job.argument])
            }
            None => self.promise_reject(promise, job.argument)
          }
        } else {
          match cap_resolve {
            Some(resolve) => {
              let _ = self.call_function(resolve, Undefined, [job.argument])
            }
            None => self.promise_resolve_value(promise, job.argument)
          }
        }
      }
      None => ()
    }
  }
}

///|
// / bound native create
fn JSInterpreter::make_bound_native(
  self : JSInterpreter,
  name : String,
  bound_args : Array[JSValue],
) -> JSValue {
  let target = self.make_native(name)
  JSValue::Function({
    id: fresh_function_id(),
    params: [],
    body: Bound(target, Undefined, bound_args),
    env: self.global_env,
    is_arrow: false,
    is_strict: false,
    is_generator: false,
    props: [],
    object_proto: Some(self.function_proto),
  })
}

///|
// / promise resolve handler
fn JSInterpreter::make_promise_resolve_handler(
  self : JSInterpreter,
  promise : JSValue,
) -> JSValue {
  let handler = self.make_bound_native("Promise.__resolve__", [promise])
  self.set_function_length(handler, 1.0)
  self.set_function_name(handler, "resolve")
  handler
}

///|
// / promise reject handler
fn JSInterpreter::make_promise_reject_handler(
  self : JSInterpreter,
  promise : JSValue,
) -> JSValue {
  let handler = self.make_bound_native("Promise.__reject__", [promise])
  self.set_function_length(handler, 1.0)
  self.set_function_name(handler, "reject")
  handler
}

///|
// / promise check
fn JSInterpreter::is_promise(_self : JSInterpreter, value : JSValue) -> Bool {
  match value {
    Object(_) | Function(_) | Array(_) =>
      match js_get_prop(value, "__class") {
        String(tag) => tag == PROMISE_CLASS
        _ => false
      }
    _ => false
  }
}

///|
// / promise create
fn JSInterpreter::new_promise(self : JSInterpreter) -> JSValue {
  let ctor = self.global_env.get("Promise")
  let proto = js_get_prop(ctor, "prototype")
  let obj = match proto {
    Object(_) | Function(_) => js_new_object_with_proto(Some(proto))
    _ => self.new_object()
  }
  self.init_promise_instance(obj)
}

///|
// / promise instance init
fn JSInterpreter::init_promise_instance(_self : JSInterpreter, obj : JSValue) -> JSValue {
  let _ = js_set_prop(obj, "__class", String(PROMISE_CLASS))
  let _ = js_set_prop(obj, PROMISE_STATE_KEY, String("pending"))
  let _ = js_set_prop(obj, PROMISE_RESULT_KEY, Undefined)
  let _ = js_set_prop(obj, PROMISE_FULFILL_REACTIONS_KEY, js_new_array())
  let _ = js_set_prop(obj, PROMISE_REJECT_REACTIONS_KEY, js_new_array())
  obj
}

///|
// / promise state get
fn JSInterpreter::promise_state(_self : JSInterpreter, promise : JSValue) -> String {
  match js_get_prop(promise, PROMISE_STATE_KEY) {
    String(state) => state
    _ => "pending"
  }
}

///|
// / promise result get
fn JSInterpreter::promise_result(_self : JSInterpreter, promise : JSValue) -> JSValue {
  js_get_prop(promise, PROMISE_RESULT_KEY)
}

///|
// / promise reaction create
fn JSInterpreter::make_promise_reaction(
  self : JSInterpreter,
  handler : JSValue,
  promise : JSValue,
  is_reject : Bool,
) -> JSValue {
  let reaction = self.new_object()
  let _ = js_set_prop(reaction, PROMISE_REACTION_HANDLER_KEY, handler)
  let _ = js_set_prop(reaction, PROMISE_REACTION_PROMISE_KEY, promise)
  let _ = js_set_prop(reaction, PROMISE_REACTION_IS_REJECT_KEY, Bool(is_reject))
  reaction
}

///|
// / promise reaction push
fn JSInterpreter::push_promise_reaction(
  _self : JSInterpreter,
  promise : JSValue,
  is_reject : Bool,
  reaction : JSValue,
) -> Unit {
  let key = if is_reject { PROMISE_REJECT_REACTIONS_KEY } else { PROMISE_FULFILL_REACTIONS_KEY }
  let list = js_get_prop(promise, key)
  match list {
    Array(_) => {
      let _ = js_array_push(list, reaction)
    }
    _ => {
      let arr = js_array_from([reaction])
      let _ = js_set_prop(promise, key, arr)
    }
  }
}

///|
// / promise reaction enqueue
fn JSInterpreter::enqueue_promise_reaction(
  self : JSInterpreter,
  reaction : JSValue,
  argument : JSValue,
) -> Unit {
  let handler = js_get_prop(reaction, PROMISE_REACTION_HANDLER_KEY)
  let promise = js_get_prop(reaction, PROMISE_REACTION_PROMISE_KEY)
  let is_reject = match js_get_prop(reaction, PROMISE_REACTION_IS_REJECT_KEY) {
    Bool(flag) => flag
    _ => false
  }
  self.enqueue_promise_job(handler, argument, promise, is_reject)
}

///|
// / promise reactions trigger
fn JSInterpreter::trigger_promise_reactions(
  self : JSInterpreter,
  promise : JSValue,
  is_reject : Bool,
  argument : JSValue,
) -> Unit {
  let key = if is_reject { PROMISE_REJECT_REACTIONS_KEY } else { PROMISE_FULFILL_REACTIONS_KEY }
  let list = js_get_prop(promise, key)
  match list {
    Array(arr) =>
      for reaction in arr.items {
        self.enqueue_promise_reaction(reaction, argument)
      }
    _ => ()
  }
  let _ = js_set_prop(promise, PROMISE_FULFILL_REACTIONS_KEY, js_new_array())
  let _ = js_set_prop(promise, PROMISE_REJECT_REACTIONS_KEY, js_new_array())
}

///|
// / promise resolve value
fn JSInterpreter::promise_resolve_value(
  self : JSInterpreter,
  promise : JSValue,
  value : JSValue,
) -> Unit {
  if self.promise_state(promise) != "pending" {
    return
  }
  if self.same_value(promise, value) {
    let err = self.make_error_obj("TypeError", "Chaining cycle detected for promise")
    self.promise_reject(promise, err)
    return
  }
  if self.is_promise(value) {
    self.promise_link(value, promise)
    return
  }
  match value {
    Object(_) | Function(_) | Array(_) => {
      let then = self.get_prop_value(value, "then")
      match self.peek_error() {
        Some(err) => {
          self.last_error = None
          self.promise_reject(promise, err)
        }
        None =>
          if self.is_callable(then) {
            let once_token = self.new_object()
            let _ = js_set_prop(once_token, "__promise_once", Bool(false))
            let resolve_once =
              self.make_bound_native("Promise.__resolve_once__", [once_token, promise])
            let reject_once =
              self.make_bound_native("Promise.__reject_once__", [once_token, promise])
            let _ = self.call_function(then, value, [resolve_once, reject_once])
            match self.peek_error() {
              Some(err) => {
                self.last_error = None
                self.promise_reject(promise, err)
              }
              None => ()
            }
          } else {
            self.promise_fulfill(promise, value)
          }
      }
    }
    _ => self.promise_fulfill(promise, value)
  }
}

///|
// / promise fulfill
fn JSInterpreter::promise_fulfill(
  self : JSInterpreter,
  promise : JSValue,
  value : JSValue,
) -> Unit {
  if self.promise_state(promise) != "pending" {
    return
  }
  let _ = js_set_prop(promise, PROMISE_STATE_KEY, String("fulfilled"))
  let _ = js_set_prop(promise, PROMISE_RESULT_KEY, value)
  self.trigger_promise_reactions(promise, false, value)
}

///|
// / promise reject
fn JSInterpreter::promise_reject(
  self : JSInterpreter,
  promise : JSValue,
  reason : JSValue,
) -> Unit {
  if self.promise_state(promise) != "pending" {
    return
  }
  let _ = js_set_prop(promise, PROMISE_STATE_KEY, String("rejected"))
  let _ = js_set_prop(promise, PROMISE_RESULT_KEY, reason)
  self.trigger_promise_reactions(promise, true, reason)
}

///|
// / promise then
fn JSInterpreter::promise_then(
  self : JSInterpreter,
  promise : JSValue,
  on_fulfilled : JSValue,
  on_rejected : JSValue,
) -> JSValue {
  let ctor = self.promise_species_constructor(promise)
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  let (result_promise, _resolve, _reject) = self.promise_new_capability(ctor)
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  self.perform_promise_then(promise, on_fulfilled, on_rejected, result_promise)
}

///|
// / promise then with result
fn JSInterpreter::perform_promise_then(
  self : JSInterpreter,
  promise : JSValue,
  on_fulfilled : JSValue,
  on_rejected : JSValue,
  result_promise : JSValue,
) -> JSValue {
  let fulfill_handler = if self.is_callable(on_fulfilled) { on_fulfilled } else { Undefined }
  let reject_handler = if self.is_callable(on_rejected) { on_rejected } else { Undefined }
  let fulfill_reaction =
    self.make_promise_reaction(fulfill_handler, result_promise, false)
  let reject_reaction =
    self.make_promise_reaction(reject_handler, result_promise, true)
  match self.promise_state(promise) {
    "pending" => {
      self.push_promise_reaction(promise, false, fulfill_reaction)
      self.push_promise_reaction(promise, true, reject_reaction)
    }
    "fulfilled" => {
      let value = self.promise_result(promise)
      self.enqueue_promise_reaction(fulfill_reaction, value)
    }
    _ => {
      let reason = self.promise_result(promise)
      self.enqueue_promise_reaction(reject_reaction, reason)
    }
  }
  result_promise
}

///|
// / promise finally
fn JSInterpreter::promise_finally(
  self : JSInterpreter,
  promise : JSValue,
  on_finally : JSValue,
) -> JSValue {
  if not(self.is_callable(on_finally)) {
    return self.promise_then(promise, Undefined, Undefined)
  }
  let fulfill_handler = self.make_bound_native("Promise.__finally_fulfill__", [on_finally])
  let reject_handler = self.make_bound_native("Promise.__finally_reject__", [on_finally])
  self.promise_then(promise, fulfill_handler, reject_handler)
}

///|
// / promise construct
fn JSInterpreter::promise_construct(self : JSInterpreter, args : Array[JSValue]) -> JSValue {
  let executor = if args.length() > 0 { args[0] } else { Undefined }
  if not(self.is_callable(executor)) {
    return self.set_error_kind("TypeError", "Promise resolver is not a function")
  }
  let promise = self.new_promise()
  let resolve_fn = self.make_promise_resolve_handler(promise)
  let reject_fn = self.make_promise_reject_handler(promise)
  let _ = self.call_function(executor, Undefined, [resolve_fn, reject_fn])
  match self.peek_error() {
    Some(err) => {
      self.last_error = None
      self.promise_reject(promise, err)
    }
    None => ()
  }
  promise
}

///|
// / promise construct with instance
fn JSInterpreter::promise_construct_with_instance(
  self : JSInterpreter,
  instance : JSValue,
  args : Array[JSValue],
) -> JSValue {
  let executor = if args.length() > 0 { args[0] } else { Undefined }
  if not(self.is_callable(executor)) {
    return self.set_error_kind("TypeError", "Promise resolver is not a function")
  }
  let promise = self.init_promise_instance(instance)
  let resolve_fn = self.make_promise_resolve_handler(promise)
  let reject_fn = self.make_promise_reject_handler(promise)
  let _ = self.call_function(executor, Undefined, [resolve_fn, reject_fn])
  match self.peek_error() {
    Some(err) => {
      self.last_error = None
      self.promise_reject(promise, err)
    }
    None => ()
  }
  promise
}

///|
// / promise static resolve
fn JSInterpreter::promise_static_resolve(self : JSInterpreter, value : JSValue) -> JSValue {
  self.promise_static_resolve_with_ctor(self.global_env.get("Promise"), value)
}

///|
// / promise static reject
///|
// / promise capability
fn JSInterpreter::promise_new_capability(
  self : JSInterpreter,
  ctor : JSValue,
) -> (JSValue, JSValue, JSValue) {
  if not(self.is_constructor(ctor)) {
    let _ = self.set_error_kind("TypeError", "not a constructor")
    return (Undefined, Undefined, Undefined)
  }
  let cap = self.new_object()
  let _ = js_set_prop(cap, "resolve", Undefined)
  let _ = js_set_prop(cap, "reject", Undefined)
  let executor = self.make_bound_native("Promise.__cap_executor__", [cap])
  self.set_function_length(executor, 2.0)
  self.set_function_name(executor, "executor")
  let promise = self.construct_with(ctor, ctor, [executor])
  match self.peek_error() {
    Some(_) => return (Undefined, Undefined, Undefined)
    None => ()
  }
  let resolve = js_get_prop(cap, "resolve")
  let reject = js_get_prop(cap, "reject")
  if not(self.is_callable(resolve)) || not(self.is_callable(reject)) {
    let _ = self.set_error_kind("TypeError", "Promise capability is not callable")
    return (Undefined, Undefined, Undefined)
  }
  let _ = js_set_prop(promise, "__promise_cap_resolve__", resolve)
  let _ = js_set_prop(promise, "__promise_cap_reject__", reject)
  (promise, resolve, reject)
}

///|
// / promise species constructor
fn JSInterpreter::promise_species_constructor(
  self : JSInterpreter,
  promise : JSValue,
) -> JSValue {
  let ctor = self.get_prop_value(promise, "constructor")
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  match ctor {
    Undefined => return self.global_env.get("Promise")
    Object(_) | Function(_) => ()
    _ => return self.set_error_kind("TypeError", "Promise constructor is not an object")
  }
  let species = self.get_prop_value(ctor, "@@species")
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  match species {
    Undefined | Null => self.global_env.get("Promise")
    _ =>
      if self.is_constructor(species) {
        species
      } else {
        self.set_error_kind("TypeError", "Promise species is not a constructor")
      }
  }
}

///|
// / promise static resolve with constructor
fn JSInterpreter::promise_static_resolve_with_ctor(
  self : JSInterpreter,
  ctor : JSValue,
  value : JSValue,
) -> JSValue {
  if self.is_promise(value) {
    let ctor_val = self.get_prop_value(value, "constructor")
    if self.same_value(ctor_val, ctor) {
      return value
    }
  }
  let (promise, resolve, _reject) = self.promise_new_capability(ctor)
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  let _ = self.call_function(resolve, Undefined, [value])
  match self.peek_error() {
    Some(err) => err
    None => promise
  }
}

///|
// / promise static reject with constructor
fn JSInterpreter::promise_static_reject_with_ctor(
  self : JSInterpreter,
  ctor : JSValue,
  reason : JSValue,
) -> JSValue {
  let (promise, _resolve, reject) = self.promise_new_capability(ctor)
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  let _ = self.call_function(reject, Undefined, [reason])
  match self.peek_error() {
    Some(err) => err
    None => promise
  }
}

///|
// / promise try
fn JSInterpreter::promise_try(
  self : JSInterpreter,
  ctor : JSValue,
  callback : JSValue,
  args : Array[JSValue],
) -> JSValue {
  let (promise, resolve, reject) = self.promise_new_capability(ctor)
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  if not(self.is_callable(callback)) {
    let err = self.set_error_kind("TypeError", "Promise.try callback is not callable")
    self.last_error = None
    let _ = self.call_function(reject, Undefined, [err])
    match self.peek_error() {
      Some(err2) => return err2
      None => return promise
    }
  }
  let result = self.call_function(callback, Undefined, args)
  match self.peek_error() {
    Some(err) => {
      self.last_error = None
      let _ = self.call_function(reject, Undefined, [err])
      match self.peek_error() {
        Some(err2) => err2
        None => promise
      }
    }
    None => {
      let _ = self.call_function(resolve, Undefined, [result])
      match self.peek_error() {
        Some(err2) => err2
        None => promise
      }
    }
  }
}

///|
// / promise link
fn JSInterpreter::promise_link(
  self : JSInterpreter,
  source : JSValue,
  target : JSValue,
) -> Unit {
  let resolve_handler = self.make_promise_resolve_handler(target)
  let reject_handler = self.make_promise_reject_handler(target)
  let fulfill_reaction =
    self.make_promise_reaction(resolve_handler, target, false)
  let reject_reaction =
    self.make_promise_reaction(reject_handler, target, true)
  match self.promise_state(source) {
    "pending" => {
      self.push_promise_reaction(source, false, fulfill_reaction)
      self.push_promise_reaction(source, true, reject_reaction)
    }
    "fulfilled" => {
      let value = self.promise_result(source)
      self.enqueue_promise_reaction(fulfill_reaction, value)
    }
    _ => {
      let reason = self.promise_result(source)
      self.enqueue_promise_reaction(reject_reaction, reason)
    }
  }
}

///|
// / promise all/allSettled with constructor
fn JSInterpreter::promise_all_with_ctor(
  self : JSInterpreter,
  ctor : JSValue,
  iter : JSValue,
  all_settled : Bool,
) -> JSValue {
  let (promise, cap_resolve, cap_reject) = self.promise_new_capability(ctor)
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  let promise_resolve = self.get_prop_value(ctor, "resolve")
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  if not(self.is_callable(promise_resolve)) {
    return self.set_error_kind("TypeError", "Promise.resolve is not callable")
  }
  let iterator =
    match self.get_iterator(iter) {
      Some(it) => it
      None =>
        match self.peek_error() {
          Some(err) => return err
          None =>
            return self.set_error_kind(
              "TypeError",
              "Promise.all argument is not iterable",
            )
        }
    }
  let results = js_new_array()
  let state = self.new_object()
  let _ = js_set_prop(state, "__all_remaining", Number(1.0))
  let _ = js_set_prop(state, "__all_results", results)
  let _ = js_set_prop(state, "__all_resolve", cap_resolve)
  let _ = js_set_prop(state, "__all_reject", cap_reject)
  let _ = js_set_prop(state, "__all_all_settled", Bool(all_settled))
  let mut index = 0
  while true {
    let next = self.call_method(iterator, "next", [])
    match self.peek_error() {
      Some(err) => return err
      None => ()
    }
    let done_val = self.get_prop_value(next, "done")
    match self.peek_error() {
      Some(err) => return err
      None => ()
    }
    let done = done_val.to_boolean()
    if done {
      let remaining = match js_get_prop(state, "__all_remaining") {
        Number(n) => n.to_int() - 1
        _ => 0
      }
      let _ = js_set_prop(state, "__all_remaining", Number(remaining.to_double()))
      if remaining == 0 {
        let _ = self.call_function(cap_resolve, ctor, [results])
      }
      return promise
    }
    let value = self.get_prop_value(next, "value")
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iterator)
        return err
      }
      None => ()
    }
    let _ = js_array_push(results, Undefined)
    let remaining = match js_get_prop(state, "__all_remaining") {
      Number(n) => n.to_int() + 1
      _ => 1
    }
    let _ = js_set_prop(state, "__all_remaining", Number(remaining.to_double()))

    let already = self.new_object()
    let _ = js_set_prop(already, "__promise_once", Bool(false))
    let idx_val = JSValue::Number(index.to_double())
    let resolve_element =
      if all_settled {
        self.make_bound_native(
          "Promise.__all_settled_fulfill__",
          [state, idx_val, already],
        )
      } else {
        self.make_bound_native(
          "Promise.__all_fulfill__",
          [state, idx_val, already],
        )
      }
    let reject_element =
      if all_settled {
        let handler =
          self.make_bound_native(
            "Promise.__all_settled_reject__",
            [state, idx_val, already],
          )
        self.set_function_length(handler, 1.0)
        self.set_function_name(handler, "reject")
        handler
      } else {
        cap_reject
      }
    self.set_function_length(resolve_element, 1.0)
    self.set_function_name(resolve_element, "resolve")
    let next_promise = self.call_function(promise_resolve, ctor, [value])
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iterator)
        return err
      }
      None => ()
    }
    let then_method = self.get_prop_value(next_promise, "then")
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iterator)
        return err
      }
      None => ()
    }
    if not(self.is_callable(then_method)) {
      let err = self.set_error_kind("TypeError", "Promise resolve is not callable")
      self.iterator_close_on_error(iterator)
      return err
    }
    let _ = self.call_function(
      then_method,
      next_promise,
      [resolve_element, reject_element],
    )
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iterator)
        return err
      }
      None => ()
    }
    index += 1
  }
  promise
}

///|
// / promise race with constructor
fn JSInterpreter::promise_race_with_ctor(
  self : JSInterpreter,
  ctor : JSValue,
  iter : JSValue,
) -> JSValue {
  let (promise, cap_resolve, cap_reject) = self.promise_new_capability(ctor)
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  let promise_resolve = self.get_prop_value(ctor, "resolve")
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  if not(self.is_callable(promise_resolve)) {
    return self.set_error_kind("TypeError", "Promise.resolve is not callable")
  }
  let iterator =
    match self.get_iterator(iter) {
      Some(it) => it
      None =>
        match self.peek_error() {
          Some(err) => return err
          None =>
            return self.set_error_kind(
              "TypeError",
              "Promise.race argument is not iterable",
            )
        }
    }
  while true {
    let next = self.call_method(iterator, "next", [])
    match self.peek_error() {
      Some(err) => return err
      None => ()
    }
    let done_val = self.get_prop_value(next, "done")
    match self.peek_error() {
      Some(err) => return err
      None => ()
    }
    let done = done_val.to_boolean()
    if done {
      return promise
    }
    let value = self.get_prop_value(next, "value")
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iterator)
        return err
      }
      None => ()
    }
    let next_promise = self.call_function(promise_resolve, ctor, [value])
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iterator)
        return err
      }
      None => ()
    }
    let then_method = self.get_prop_value(next_promise, "then")
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iterator)
        return err
      }
      None => ()
    }
    if not(self.is_callable(then_method)) {
      let err = self.set_error_kind("TypeError", "Promise resolve is not callable")
      self.iterator_close_on_error(iterator)
      return err
    }
    let _ = self.call_function(
      then_method,
      next_promise,
      [cap_resolve, cap_reject],
    )
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iterator)
        return err
      }
      None => ()
    }
  }
  promise
}

///|
// / promise withResolvers
fn JSInterpreter::promise_with_resolvers(self : JSInterpreter, ctor : JSValue) -> JSValue {
  let (promise, resolve, reject) = self.promise_new_capability(ctor)
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  self.set_function_name(resolve, "")
  self.set_function_name(reject, "")
  let obj = self.new_object()
  let _ = js_set_prop(obj, "promise", promise)
  let _ = js_set_prop(obj, "resolve", resolve)
  let _ = js_set_prop(obj, "reject", reject)
  obj
}

///|
// / promise any with constructor
fn JSInterpreter::promise_any_with_ctor(
  self : JSInterpreter,
  ctor : JSValue,
  iter : JSValue,
) -> JSValue {
  let (promise, cap_resolve, cap_reject) = self.promise_new_capability(ctor)
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  let promise_resolve = self.get_prop_value(ctor, "resolve")
  match self.peek_error() {
    Some(err) => return err
    None => ()
  }
  if not(self.is_callable(promise_resolve)) {
    return self.set_error_kind("TypeError", "Promise.resolve is not callable")
  }
  let iterator =
    match self.get_iterator(iter) {
      Some(it) => it
      None =>
        match self.peek_error() {
          Some(err) => return err
          None =>
            return self.set_error_kind(
              "TypeError",
              "Promise.any argument is not iterable",
            )
        }
    }
  let errors = js_new_array()
  let state = self.new_object()
  let _ = js_set_prop(state, "__any_remaining", Number(1.0))
  let _ = js_set_prop(state, "__any_errors", errors)
  let _ = js_set_prop(state, "__any_reject", cap_reject)
  let mut index = 0
  while true {
    let next = self.call_method(iterator, "next", [])
    match self.peek_error() {
      Some(err) => return err
      None => ()
    }
    let done_val = self.get_prop_value(next, "done")
    match self.peek_error() {
      Some(err) => return err
      None => ()
    }
    let done = done_val.to_boolean()
    if done {
      let remaining = match js_get_prop(state, "__any_remaining") {
        Number(n) => n.to_int() - 1
        _ => 0
      }
      let _ = js_set_prop(state, "__any_remaining", Number(remaining.to_double()))
      if remaining == 0 {
        let err = self.make_aggregate_error(errors)
        let _ = self.call_function(cap_reject, Undefined, [err])
      }
      return promise
    }
    let value = self.get_prop_value(next, "value")
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iterator)
        return err
      }
      None => ()
    }
    let _ = js_array_push(errors, Undefined)
    let remaining = match js_get_prop(state, "__any_remaining") {
      Number(n) => n.to_int() + 1
      _ => 1
    }
    let _ = js_set_prop(state, "__any_remaining", Number(remaining.to_double()))
    let idx_val = JSValue::Number(index.to_double())
    let already = self.new_object()
    let _ = js_set_prop(already, "__promise_once", Bool(false))
    let reject_element = self.make_bound_native(
      "Promise.__any_reject__",
      [state, idx_val, already],
    )
    self.set_function_length(reject_element, 1.0)
    self.set_function_name(reject_element, "reject")
    let next_promise = self.call_function(promise_resolve, ctor, [value])
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iterator)
        return err
      }
      None => ()
    }
    let then_method = self.get_prop_value(next_promise, "then")
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iterator)
        return err
      }
      None => ()
    }
    if not(self.is_callable(then_method)) {
      let err = self.set_error_kind("TypeError", "Promise resolve is not callable")
      self.iterator_close_on_error(iterator)
      return err
    }
    let _ = self.call_function(
      then_method,
      next_promise,
      [cap_resolve, reject_element],
    )
    match self.peek_error() {
      Some(err) => {
        self.iterator_close_on_error(iterator)
        return err
      }
      None => ()
    }
    index += 1
  }
  promise
}

///|
// / aggregate error
fn JSInterpreter::make_aggregate_error(
  self : JSInterpreter,
  errors : JSValue,
) -> JSValue {
  let obj = self.make_error_obj("AggregateError", "All promises were rejected")
  let _ = js_set_prop(obj, "errors", errors)
  obj
}
