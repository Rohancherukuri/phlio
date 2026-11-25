import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { BadgeCheck, Search } from "lucide-react";
import { useEffect, useState } from "react";
import { Badge, Button, Card, ErrorNote, Input, Skeleton } from "../components/ui";
import { api } from "../lib/api";
import { day, num } from "../lib/format";

interface UserRow { id: string; username: string; name: string; email: string; avatar_url?: string; created_at?: string; verified: boolean; creator: boolean; test: boolean; country?: string }
interface Page { total: number; offset: number; limit: number; items: UserRow[] }

const LIMIT = 25;

export default function UsersPage() {
  const [q, setQ] = useState("");
  const [term, setTerm] = useState("");
  const [offset, setOffset] = useState(0);
  useEffect(() => {
    const t = setTimeout(() => { setTerm(q); setOffset(0); }, 300);
    return () => clearTimeout(t);
  }, [q]);
  const res = useQuery({
    queryKey: ["users", term, offset],
    queryFn: () => api<Page>(`/admin/users?q=${encodeURIComponent(term)}&offset=${offset}&limit=${LIMIT}`),
    placeholderData: keepPreviousData,
  });
  const p = res.data;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <div className="relative w-full max-w-sm">
          <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-faint" />
          <Input className="pl-9" placeholder="Search by name or username" value={q} onChange={(e) => setQ(e.target.value)} />
        </div>
        {p && <span className="text-xs text-sub">{num(p.total)} {term ? "matches" : "users"}</span>}
      </div>
      <ErrorNote error={res.error} />
      <Card className="overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[720px] text-sm">
            <thead className="border-b border-line text-left text-xs text-faint">
              <tr>
                <th className="px-5 py-3 font-medium">User</th>
                <th className="px-3 py-3 font-medium">Email</th>
                <th className="px-3 py-3 font-medium">Country</th>
                <th className="px-3 py-3 font-medium">Joined</th>
                <th className="px-5 py-3 font-medium">Tags</th>
              </tr>
            </thead>
            <tbody>
              {p ? p.items.map((u) => (
                <tr key={u.id} className="border-b border-line last:border-0 hover:bg-muted">
                  <td className="px-5 py-2.5">
                    <div className="flex items-center gap-3">
                      {u.avatar_url && /^https?:/.test(u.avatar_url)
                        ? <img src={u.avatar_url} alt="" className="h-8 w-8 rounded-full object-cover" referrerPolicy="no-referrer" />
                        : <div className="flex h-8 w-8 items-center justify-center rounded-full bg-muted text-xs font-semibold">{u.name.slice(0, 1)}</div>}
                      <div className="min-w-0">
                        <p className="flex items-center gap-1 truncate font-medium">{u.name}{u.verified && <BadgeCheck size={14} className="text-[var(--s-social)]" aria-label="Verified" />}</p>
                        <p className="truncate text-xs text-faint">@{u.username}</p>
                      </div>
                    </div>
                  </td>
                  <td className="px-3 py-2.5 text-sub">{u.email}</td>
                  <td className="px-3 py-2.5 text-sub">{u.country ?? "–"}</td>
                  <td className="px-3 py-2.5 text-sub">{u.created_at ? day(u.created_at, true) : "–"}</td>
                  <td className="px-5 py-2.5">
                    <div className="flex gap-1">
                      {u.creator && <Badge tone="brand">Creator</Badge>}
                      {u.test && <Badge>Test</Badge>}
                    </div>
                  </td>
                </tr>
              )) : Array.from({ length: 8 }, (_, i) => (
                <tr key={i}><td colSpan={5} className="px-5 py-2"><Skeleton className="h-8" /></td></tr>
              ))}
            </tbody>
          </table>
        </div>
      </Card>
      {p && !term && p.total > LIMIT && (
        <div className="flex items-center justify-end gap-2">
          <span className="text-xs text-sub">{offset + 1}–{Math.min(offset + LIMIT, p.total)} of {num(p.total)}</span>
          <Button variant="outline" disabled={offset === 0} onClick={() => setOffset(Math.max(0, offset - LIMIT))}>Previous</Button>
          <Button variant="outline" disabled={offset + LIMIT >= p.total} onClick={() => setOffset(offset + LIMIT)}>Next</Button>
        </div>
      )}
    </div>
  );
}
