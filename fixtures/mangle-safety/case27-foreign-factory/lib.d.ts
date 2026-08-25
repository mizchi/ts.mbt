declare module "ext-net" {
  type Client = {
    transmit(record: { recordId: number; noteText: string }): string;
  };
  export function createClient(): Client;
}
