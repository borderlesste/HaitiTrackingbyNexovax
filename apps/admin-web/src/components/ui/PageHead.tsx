import type { ReactNode } from "react";

export default function PageHead({ title, subtitle, children }: { title: string; subtitle?: string; children?: ReactNode }) {
  return (
    <div className="head">
      <div>
        <h2>{title}</h2>
        {subtitle && <p className="muted">{subtitle}</p>}
      </div>
      {children && <div className="toolbar">{children}</div>}
    </div>
  );
}
