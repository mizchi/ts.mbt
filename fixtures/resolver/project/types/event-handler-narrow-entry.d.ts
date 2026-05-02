declare interface TargetedEvent<Target = Element> {
  currentTarget: Target;
}

export type EventHandler<E extends TargetedEvent> = {
  bivarianceHack(event: E): void;
}['bivarianceHack'];

export type GenericEventHandler<Target> = EventHandler<TargetedEvent<Target>>;

export interface DomLike<Target> {
  onClick?: EventHandler<TargetedEvent<Target>> | undefined;
  onLoad?: GenericEventHandler<Target> | undefined;
}
