import clsx from "clsx";
import type { ReactNode } from "react";

export const MARK_SRC = `${import.meta.env.BASE_URL}phlio-mark.png`;

/** The Phlio "P" mark (frontend/ui/assets/images/logo/logo_mark.png). */
export function PhlioMark({ size = 18, className }: { size?: number; className?: string }) {
  return (
    <img
      src={MARK_SRC}
      alt=""
      aria-hidden
      draggable={false}
      style={{ height: size, width: "auto" }}
      className={clsx("inline-block shrink-0 select-none object-contain", className)}
    />
  );
}

/** "Phlio …" with the P mark in front, for headings and labels. */
export function PhlioName({ children, size = 16, className }: { children?: ReactNode; size?: number; className?: string }) {
  return (
    <span className={clsx("inline-flex min-w-0 items-center gap-1.5", className)}>
      <PhlioMark size={size} />
      <span className="truncate">Phlio{children ? <> {children}</> : null}</span>
    </span>
  );
}
