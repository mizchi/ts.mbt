import { register, runAll } from "host-registry";

// ---- The hazard. -----------------------------------------------------
// `Widget` is not exported, and nothing in this bundle calls `render`
// or `neverNamedHere` by name. The only thing that can invoke either is
// the host, which received the instance — and it calls `render`.
//
// The bundle cannot know WHICH method the host picks, so once the value
// has left, every method has to stay. `neverNamedHere` surviving is the
// fix working, not the fix being too coarse.
class Widget {
  label: string;

  constructor(label: string) {
    this.label = label;
  }

  render(): string {
    return "widget:" + this.label;
  }

  neverNamedHere(): string {
    return "reachable only from outside";
  }
}

const first = new Widget("one");
register(first);

// ---- The protocol half. ---------------------------------------------
// `JSON.stringify` is a KNOWN sink: it observes property names, and the
// one method it invokes is `toJSON`. Nothing here calls `toJSON`, so
// only the protocol list keeps it. `notAProtocolMethod` is on the same
// class and must still go — otherwise "keep the protocol methods" would
// have degenerated into "keep everything on any class a sink touches".
class Payload {
  id = 7;

  toJSON(): { tag: string } {
    return { tag: "payload" };
  }

  notAProtocolMethod(): string {
    return "dead";
  }
}

const payload = new Payload();

// ---- The control. ---------------------------------------------------
// Never escapes, and only `live` is called, so `deadWeight` goes. The
// instance is bound to a local `const` rather than inlined into the
// exported initializer, because the export-surface walk reserves every
// member of a class it finds inside an exported binding's initializer —
// pre-existing conservatism, and enough on its own to make this case
// pass for the wrong reason.
class Local {
  live(): number {
    return 1;
  }

  deadWeight(): number {
    return 2;
  }
}

const local = new Local();

export const results = runAll();
export const serialized = JSON.stringify(payload);
export const localValue = local.live();
