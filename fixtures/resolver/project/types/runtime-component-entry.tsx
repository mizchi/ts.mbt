export interface BadgeProps {
  label: string;
}

export function renderBadge(props: BadgeProps): JSX.Element {
  return <badge>{props.label}</badge>;
}
