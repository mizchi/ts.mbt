import { useState, useMemo, type ReactNode } from "react";
export function List(props: { items: string[]; footer?: ReactNode }) {
  const [q, setQ] = useState("");
  const shown = useMemo(() => props.items.filter((i) => i.includes(q)), [props.items, q]);
  return <div><input value={q} onChange={(e) => setQ(e.target.value)} />{shown.map((s) => <p key={s}>{s}</p>)}{props.footer}</div>;
}
