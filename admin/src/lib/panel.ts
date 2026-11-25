import { useOutletContext } from "react-router-dom";
import type { Admin } from "./api";
import type { LiveSnapshot, LiveStatus } from "./live";

export interface PanelContext {
  admin: Admin;
  days: number;
  live: { data: LiveSnapshot | null; status: LiveStatus };
}

export const usePanel = () => useOutletContext<PanelContext>();
