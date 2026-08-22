import { createClient } from "ext-net";

// `client` is a local binding, so the old rule saw a call on
// bundle-internal code — but the value came back from a foreign
// factory, so `transmit`'s body is the other package's.
const client = createClient();

export function send(recordId: number, noteText: string): string {
  return client.transmit({ recordId, noteText });
}
