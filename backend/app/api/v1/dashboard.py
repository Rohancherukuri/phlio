"""The all-in-one profile dashboard: one call, every Phlio platform.

``GET /profile/dashboard?days=7|30|90`` returns, for the chosen period and the
period before it (for the trend arrows):

  overview   how much you did on each platform (the "Phlio mix"), active days,
             your most-used platform, a daily activity series per platform
  social     views / interactions / followers / content (same numbers as
             /profile/insights) plus moments posted and their viewers
  pay        full money analytics: balance, money in / out / net with daily
             series, average and biggest payment, spending by category
             (from notes), by weekday and hour, who you pay and who pays you
             most, open bill splits
  messages   DMs sent / received, chats, media shared, busiest chats
  rooms      rooms you're in, messages you sent, most active rooms
  stream     watched / listened, likes, saves, playlists, what kinds
  news       stories read, bookmarks, shares, top publishers
  shop       products viewed, saved, bag value, parcels tracked, categories
  book       bookings, upcoming, estimated spend, categories

Every section has the same shape so the app can draw any of them:

    {id, label, has_data, currency?, headline: {label, value, format, change},
     kpis: [{id, label, value, format, change?, hint?}],
     series: {keys: [{id, label}], days: [{day, <key>: n}]},
     breakdown: {title, format, items: [{label, value}]},
     top: {title, items: [{title, subtitle, value, format, image_url}]},
     insights: ["plain-language takeaways"], extra: {...}}

``format`` is "count", "money" (minor units, in ``currency``) or "percent".
Sections fail independently: a platform that errors comes back empty.
"""

from __future__ import annotations

import collections
import datetime as dt
import logging
import re

from fastapi import APIRouter, Depends, Query

from app.api.deps import get_container, get_current_user
from app.api.v1.appearance import insights as social_insights
from app.domains.graph.service import key

router = APIRouter(tags=["dashboard"])
log = logging.getLogger("phlio.dashboard")

CONSUME = {"viewed", "watched", "listened", "attended"}
WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
CATEGORIES = [
    ("Food & drinks", r"food|lunch|dinner|breakfast|brunch|cafe|coffee|chai|tea|pizza|burger|biryani|swiggy|zomato|restaurant|snack|dessert|bakery|grocer"),
    ("Shopping", r"shop|order|amazon|flipkart|myntra|cloth|shoe|bag|gift|mall|store"),
    ("Travel", r"uber|ola|rapido|cab|taxi|auto|flight|train|bus|metro|fuel|petrol|diesel|trip|travel|hotel|toll|parking"),
    ("Bills & rent", r"bill|rent|electric|recharge|wifi|internet|broadband|emi|insurance|water|gas|maintenance|subscription"),
    ("Fun", r"movie|ticket|concert|netflix|spotify|prime|game|show|party|club|bowling"),
    ("Health", r"doctor|medicine|pharma|hospital|clinic|gym|fitness|yoga"),
]


def _when(value) -> dt.datetime | None:
    if value is None:
        return None
    if isinstance(value, dt.datetime):
        moment = value
    else:
        try:
            moment = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except ValueError:
            return None
    return moment if moment.tzinfo else moment.replace(tzinfo=dt.UTC)


def _pct(now: float, before: float) -> float | None:
    if before == 0:
        return None  # nothing to compare with: the app shows no arrow
    return round((now - before) * 100 / before, 1)


class Period:
    def __init__(self, days: int):
        self.days = days
        self.now = dt.datetime.now(dt.UTC)
        self.start = (self.now - dt.timedelta(days=days - 1)).replace(hour=0, minute=0, second=0, microsecond=0)
        self.before = self.start - dt.timedelta(days=days)
        self.labels = [(self.start + dt.timedelta(days=i)).date().isoformat() for i in range(days)]

    def which(self, moment: dt.datetime | None) -> str | None:
        """'now', 'before' or None (outside both)."""
        if moment is None:
            return None
        if moment >= self.start:
            return "now"
        if moment >= self.before:
            return "before"
        return None

    def series(self, keys: list[tuple[str, str]]) -> dict:
        return dict(keys=[dict(id=k, label=label) for k, label in keys],
                    days=[dict(day=d, **{k: 0 for k, _ in keys}) for d in self.labels])

    def add(self, series: dict, moment: dt.datetime, name: str, amount: float = 1) -> None:
        index = (moment.date() - self.start.date()).days
        if 0 <= index < len(series["days"]):
            series["days"][index][name] += amount


def _kpi(id_, label, value, fmt="count", change=None, hint=None) -> dict:
    out = dict(id=id_, label=label, value=value, format=fmt)
    if change is not None:
        out["change"] = change
    if hint:
        out["hint"] = hint
    return out


def _section(id_, label, *, headline, kpis, series=None, breakdown=None, top=None, insights=None,
             has_data=True, currency=None, extra=None) -> dict:
    return dict(id=id_, label=label, has_data=has_data, currency=currency, headline=headline, kpis=kpis,
                series=series, breakdown=breakdown, top=top, insights=insights or [], extra=extra or {})


def _empty(id_, label) -> dict:
    return _section(id_, label, has_data=False, headline=dict(label="Activity", value=0, format="count"), kpis=[])


def _trend_line(what: str, change: float | None) -> str | None:
    if change is None:
        return None
    if abs(change) < 3:
        return f"Your {what} held steady compared with the period before."
    return f"Your {what} went {'up' if change > 0 else 'down'} {abs(change):.0f}% compared with the period before."


# -- Pay ------------------------------------------------------------------------------------------

async def _all_transactions(c, user_id: str, since: dt.datetime) -> list:
    out, cursor = [], None
    for _ in range(50):
        page, cursor = await c.pay_service.list_transactions(user_id=user_id, cursor=cursor, limit=100)
        out.extend(page)
        oldest = min((_when(t.created_at) for t in page), default=None)
        if not cursor or not page or (oldest and oldest < since):
            break
    return out


def _category(text: str) -> str:
    low = text.lower()
    for name, pattern in CATEGORIES:
        if re.search(pattern, low):
            return name
    return "People & other"


async def _pay(c, user, p: Period) -> dict:
    wallet = await c.pay_service.get_wallet(user.id)
    currency = wallet.currency
    txns = await _all_transactions(c, user.id, p.before)
    series = p.series([("sent", "Money out"), ("received", "Money in")])
    now = collections.Counter()
    before = collections.Counter()
    categories = collections.Counter()
    weekday = [0] * 7
    hours = [0] * 24
    to_people: collections.Counter = collections.Counter()
    from_people: collections.Counter = collections.Counter()
    biggest = None
    per_day = [0] * p.days
    for t in txns:
        moment = _when(t.created_at)
        period = p.which(moment)
        if period is None or str(t.status) != "success":
            continue
        kind = "sent" if str(t.type) == "send" else "received"
        bucket = now if period == "now" else before
        bucket[kind] += t.amount_minor_units
        bucket[kind + "_count"] += 1
        if period != "now":
            continue
        p.add(series, moment, kind, t.amount_minor_units)
        index = (moment.date() - p.start.date()).days
        if 0 <= index < p.days:
            per_day[index] += 1
        if kind == "sent":
            categories[_category(f"{t.note} {t.counterparty}")] += t.amount_minor_units
            weekday[moment.weekday()] += t.amount_minor_units
            hours[moment.hour] += t.amount_minor_units
            to_people[t.counterparty] += t.amount_minor_units
        else:
            from_people[t.counterparty] += t.amount_minor_units
        if biggest is None or t.amount_minor_units > biggest["amount"]:
            biggest = dict(amount=t.amount_minor_units, counterparty=t.counterparty, type=kind,
                           note=t.note, at=moment.isoformat())
    count = now["sent_count"] + now["received_count"]
    net = now["received"] - now["sent"]
    splits, cursor = [], None
    for _ in range(5):
        page, cursor = await c.pay_service.list_splits(user_id=user.id, cursor=cursor, limit=100)
        splits.extend(page)
        if not cursor:
            break
    open_splits = [s for s in splits if any(not x.has_paid for x in s.participants)]
    owed = sum(x.amount_minor_units for s in open_splits for x in s.participants if not x.has_paid)
    sent_change = _pct(now["sent"], before["sent"])
    insights = []
    if now["sent"]:
        top_cat, top_amount = categories.most_common(1)[0]
        share = round(top_amount * 100 / now["sent"])
        insights.append(f"{top_cat} took {share}% of what you spent." if top_cat != "People & other"
                        else f"{share}% of what you spent went to people and other payments.")
    if line := _trend_line("spending", sent_change):
        insights.append(line)
    if to_people:
        insights.append(f"You paid {to_people.most_common(1)[0][0]} the most.")
    if any(weekday):
        insights.append(f"{['Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays', 'Sundays'][max(range(7), key=weekday.__getitem__)]} are your biggest spending days.")
    if count and net >= 0:
        insights.append("More money came in than went out. Nice.")
    elif count:
        insights.append("You spent more than you received in this period.")
    if open_splits:
        insights.append(f"{len(open_splits)} bill split{'s are' if len(open_splits) != 1 else ' is'} still waiting on friends.")
    people = [dict(title=name, subtitle="You paid", value=v, format="money") for name, v in to_people.most_common(5)]
    people += [dict(title=name, subtitle="Paid you", value=v, format="money") for name, v in from_people.most_common(3)]
    return _section(
        "pay", "Pay", currency=currency, has_data=bool(count or wallet.balance_minor_units),
        headline=dict(label="Spent", value=now["sent"], format="money", change=sent_change),
        kpis=[
            _kpi("balance", "Balance", wallet.balance_minor_units, "money"),
            _kpi("sent", "Money out", now["sent"], "money", sent_change),
            _kpi("received", "Money in", now["received"], "money", _pct(now["received"], before["received"])),
            _kpi("net", "Net flow", net, "money", hint="Money in minus money out"),
            _kpi("payments", "Payments", count, "count",
                 _pct(count, before["sent_count"] + before["received_count"])),
            _kpi("average", "Average payment", round((now["sent"] + now["received"]) / count) if count else 0, "money"),
        ],
        series=series,
        breakdown=dict(title="Where your money went", format="money",
                       items=[dict(label=k, value=v) for k, v in categories.most_common()]),
        top=dict(title="People you pay and who pay you", items=people),
        insights=insights,
        extra=dict(
            biggest=biggest,
            weekday=[dict(label=WEEKDAYS[i], value=weekday[i]) for i in range(7)],
            hours=hours,
            split=dict(open=len(open_splits), owed_to_you=owed),
            in_out=dict(sent=now["sent"], received=now["received"]),
            daily_count=per_day,
            savings_rate=round(net * 100 / now["received"], 1) if now["received"] else None,
        ),
    )


# -- Messages and rooms --------------------------------------------------------------------------

async def _messages(c, user, p: Period) -> dict:
    db = c.messaging_service.db
    rows = db.execute(
        "SELECT sender, recipient, attachments, created_at FROM messages "
        "WHERE (sender=? OR recipient=?) AND created_at >= ?",
        (user.id, user.id, p.before.isoformat()[:19]),
    ).fetchall()
    series = p.series([("sent", "Sent"), ("received", "Received")])
    now = collections.Counter()
    before = collections.Counter()
    peers: collections.Counter = collections.Counter()
    hours = [0] * 24
    for row in rows:
        moment = _when(row["created_at"])
        period = p.which(moment)
        if period is None:
            continue
        kind = "sent" if row["sender"] == user.id else "received"
        (now if period == "now" else before)[kind] += 1
        if period != "now":
            continue
        p.add(series, moment, kind)
        peers[row["recipient"] if kind == "sent" else row["sender"]] += 1
        hours[moment.hour] += 1
        if kind == "sent" and row["attachments"] not in (None, "", "[]"):
            now["media"] += 1
    total, total_before = now["sent"] + now["received"], before["sent"] + before["received"]
    top = []
    for peer, n in peers.most_common(5):
        person = await c.identity_repository.get_by_id(peer)
        if person:
            top.append(dict(title=person.full_name or person.username, subtitle="@" + person.username, value=n,
                            format="count", image_url=person.avatar_url, username=person.username))
    insights = []
    if top:
        insights.append(f"You talk to {top[0]['title']} the most.")
    if line := _trend_line("messaging", _pct(total, total_before)):
        insights.append(line)
    if any(hours):
        peak = max(range(24), key=hours.__getitem__)
        insights.append(f"Your chats are busiest around {peak % 12 or 12} {'AM' if peak < 12 else 'PM'}.")
    return _section(
        "messages", "Messages", has_data=total > 0,
        headline=dict(label="Messages", value=total, format="count", change=_pct(total, total_before)),
        kpis=[
            _kpi("sent", "Sent", now["sent"], change=_pct(now["sent"], before["sent"])),
            _kpi("received", "Received", now["received"], change=_pct(now["received"], before["received"])),
            _kpi("chats", "People", len(peers)),
            _kpi("media", "Media & stickers sent", now["media"]),
        ],
        series=series,
        breakdown=dict(title="Sent vs received", format="count",
                       items=[dict(label="Sent", value=now["sent"]), dict(label="Received", value=now["received"])]),
        top=dict(title="Your top chats", items=top), insights=insights, extra=dict(hours=hours),
    )


async def _rooms(c, user, p: Period) -> dict:
    rooms = await c.rooms_repository.list_member_rooms(user.id)
    series = p.series([("mine", "Your messages"), ("all", "All messages")])
    now = collections.Counter()
    before = collections.Counter()
    per_room = []
    for room in rooms[:40]:
        mine = everyone = 0
        cursor = None
        for _ in range(3):
            page, cursor = await c.rooms_repository.list_messages(room.id, cursor=cursor, limit=100)
            for m in page:
                moment = _when(m.created_at)
                period = p.which(moment)
                if period is None:
                    continue
                own = m.author_id == user.id
                if period == "now":
                    p.add(series, moment, "all")
                    everyone += 1
                    if own:
                        p.add(series, moment, "mine")
                        mine += 1
                        now["mine"] += 1
                    now["all"] += 1
                else:
                    before["all"] += 1
                    before["mine"] += own
            if not cursor:
                break
        per_room.append((room, mine, everyone))
    per_room.sort(key=lambda r: (r[2], r[1]), reverse=True)
    insights = []
    if per_room and per_room[0][2]:
        insights.append(f"{per_room[0][0].name} was your liveliest room.")
    if line := _trend_line("room activity", _pct(now["all"], before["all"])):
        insights.append(line)
    return _section(
        "rooms", "Rooms", has_data=bool(rooms),
        headline=dict(label="Room messages", value=now["all"], format="count", change=_pct(now["all"], before["all"])),
        kpis=[
            _kpi("rooms", "Rooms you're in", len(rooms)),
            _kpi("mine", "Your messages", now["mine"], change=_pct(now["mine"], before["mine"])),
            _kpi("all", "All messages", now["all"], change=_pct(now["all"], before["all"])),
            _kpi("members", "People in your rooms", sum(r.member_count for r in rooms)),
        ],
        series=series,
        breakdown=dict(title="Rooms by category", format="count",
                       items=[dict(label=str(k).replace("_", " ").title(), value=v) for k, v in
                              collections.Counter(str(getattr(r.category, "value", r.category)) for r in rooms).most_common()]),
        top=dict(title="Most active rooms", items=[
            dict(title=f"{r.icon} {r.name}".strip(), subtitle=f"{mine} from you", value=n, format="count", room_id=r.id)
            for r, mine, n in per_room[:5] if n]),
        insights=insights,
    )


# -- Platforms from your activity (Stream, News, Shop, Book) -----------------------------------------

async def _my_activity(c, user) -> list[dict]:
    """Your actions on Phlio objects, each with its object (platform, type, title)."""
    out, cache = [], {}
    for edge in await c.graph.store.rows("activity", {"in": "user:" + user.id}):
        oid = edge.get("out")
        if oid not in cache:
            cache[oid] = await c.graph.store.get(oid)
        obj = cache[oid]
        if obj:
            out.append(dict(edge, obj=obj, moment=_when(edge.get("created_at"))))
    return out


async def _details(c, obj: dict) -> dict:
    return await c.graph.store.get(key("platform_content", obj["platform"], obj.get("domain_ref", ""))) or {}


async def _activity_section(c, p: Period, acts: list[dict], platform: str, label: str, *, consume_label: str,
                            type_names: dict[str, str]) -> tuple[dict, list[dict], collections.Counter, collections.Counter]:
    mine = [a for a in acts if a["obj"].get("platform") == platform]
    series = p.series([("consumed", consume_label), ("engaged", "Likes, saves & shares")])
    now, before = collections.Counter(), collections.Counter()
    kinds = collections.Counter()
    recent = []
    for a in mine:
        period = p.which(a["moment"])
        if period is None:
            continue
        verb = a.get("verb")
        group = "consumed" if verb in CONSUME else verb
        (now if period == "now" else before)[group] += 1
        if period != "now":
            continue
        if verb in CONSUME:
            p.add(series, a["moment"], "consumed")
            kinds[type_names.get(a["obj"].get("object_type"), str(a["obj"].get("object_type") or "Other").title())] += 1
            recent.append(a)
        elif verb in {"liked", "saved", "shared", "reposted", "commented"}:
            p.add(series, a["moment"], "engaged")
    recent.sort(key=lambda a: a["moment"], reverse=True)
    top = []
    for a in recent[:5]:
        d = await _details(c, a["obj"])
        top.append(dict(title=a["obj"].get("title") or "Untitled", subtitle=d.get("publisher") or type_names.get(a["obj"].get("object_type"), ""),
                        value=None, format="count", image_url=d.get("image_url"),
                        path=f"{platform}/{a['obj'].get('domain_ref')}"))
    return dict(series=series, top=top, breakdown=kinds), recent, now, before


async def _stream(c, user, p: Period, acts) -> dict:
    s, recent, now, before = await _activity_section(
        c, p, acts, "stream", "Stream", consume_label="Watched & played",
        type_names={"movie": "Movies", "series": "Shows", "episode": "Episodes", "track": "Songs", "scene": "Clips"})
    playlists = await c.graph.store.rows("playlist", {"owner_id": user.id, "platform": "stream"})
    total = now["consumed"]
    insights = []
    if s["breakdown"]:
        fav, n = s["breakdown"].most_common(1)[0]
        insights.append(f"{fav} made up {round(n * 100 / max(1, total))}% of what you watched and played.")
    if line := _trend_line("streaming", _pct(total, before["consumed"])):
        insights.append(line)
    return _section(
        "stream", "Stream", has_data=bool(total or now["liked"] or playlists),
        headline=dict(label="Watched & played", value=total, format="count", change=_pct(total, before["consumed"])),
        kpis=[
            _kpi("consumed", "Watched & played", total, change=_pct(total, before["consumed"])),
            _kpi("liked", "Liked", now["liked"], change=_pct(now["liked"], before["liked"])),
            _kpi("saved", "Saved", now["saved"]),
            _kpi("playlists", "Playlists", len(playlists)),
        ],
        series=s["series"],
        breakdown=dict(title="What you streamed", format="count",
                       items=[dict(label=k, value=v) for k, v in s["breakdown"].most_common()]),
        top=dict(title="Recently played", items=s["top"]), insights=insights,
    )


async def _news(c, user, p: Period, acts) -> dict:
    s, recent, now, before = await _activity_section(
        c, p, acts, "news", "News", consume_label="Stories read",
        type_names={"article": "Articles", "topic": "Topics", "publisher": "Publishers"})
    publishers = collections.Counter()
    for a in recent:
        d = await _details(c, a["obj"])
        if d.get("publisher"):
            publishers[d["publisher"]] += 1
    lists = await c.graph.store.rows("playlist", {"owner_id": user.id, "platform": "news"})
    bookmarks = 0
    for pl in lists:
        bookmarks += len(await c.graph.store.rows("playlist_item", {"playlist_id": pl["id"]}))
    read = now["consumed"]
    insights = []
    if publishers:
        insights.append(f"You read {publishers.most_common(1)[0][0]} the most.")
    if line := _trend_line("reading", _pct(read, before["consumed"])):
        insights.append(line)
    if bookmarks:
        insights.append(f"{bookmarks} stor{'ies are' if bookmarks != 1 else 'y is'} waiting in your bookmarks.")
    return _section(
        "news", "News", has_data=bool(read or bookmarks),
        headline=dict(label="Stories read", value=read, format="count", change=_pct(read, before["consumed"])),
        kpis=[
            _kpi("read", "Stories read", read, change=_pct(read, before["consumed"])),
            _kpi("bookmarks", "Bookmarked", bookmarks),
            _kpi("shared", "Shared", now["shared"]),
            _kpi("liked", "Liked", now["liked"]),
        ],
        series=s["series"],
        breakdown=dict(title="Publishers you read", format="count",
                       items=[dict(label=k, value=v) for k, v in publishers.most_common(6)]),
        top=dict(title="Recently read", items=s["top"]), insights=insights,
    )


async def _shop(c, user, p: Period, acts) -> dict:
    s, recent, now, before = await _activity_section(
        c, p, acts, "shop", "Shop", consume_label="Products viewed",
        type_names={"product": "Products", "store": "Stores", "collection": "Collections"})
    categories = collections.Counter()
    for a in recent:
        product = await c.shop_repository.get_product(a["obj"].get("domain_ref", ""))
        if product:
            categories[str(getattr(product.category, "value", product.category)).replace("_", " ").title()] += 1
    cart_value, cart_items, currency = 0, 0, None
    for row in await c.graph.store.rows("shop_cart", {"user_id": user.id}):
        product = await c.shop_repository.get_product(row["product_id"])
        if product:
            cart_value += product.price_minor_units * row["quantity"]
            cart_items += row["quantity"]
            currency = currency or product.currency
    parcels = await c.graph.store.rows("shop_tracking", {"user_id": user.id})
    viewed = now["consumed"]
    insights = []
    if categories:
        insights.append(f"You browsed {categories.most_common(1)[0][0].lower()} the most.")
    if cart_items:
        insights.append(f"{cart_items} item{'s' if cart_items != 1 else ''} in your bag.")
    if line := _trend_line("browsing", _pct(viewed, before["consumed"])):
        insights.append(line)
    return _section(
        "shop", "Shop", currency=currency, has_data=bool(viewed or cart_items or parcels or now["saved"]),
        headline=dict(label="Products viewed", value=viewed, format="count", change=_pct(viewed, before["consumed"])),
        kpis=[
            _kpi("viewed", "Products viewed", viewed, change=_pct(viewed, before["consumed"])),
            _kpi("saved", "Saved & liked", now["saved"] + now["liked"]),
            _kpi("bag", "Bag value", cart_value, "money", hint=f"{cart_items} item{'s' if cart_items != 1 else ''}"),
            _kpi("parcels", "Parcels tracked", len(parcels)),
        ],
        series=s["series"],
        breakdown=dict(title="Categories you browsed", format="count",
                       items=[dict(label=k, value=v) for k, v in categories.most_common(6)]),
        top=dict(title="Recently viewed", items=s["top"]), insights=insights,
    )


async def _book(c, user, p: Period, acts) -> dict:
    bookings, cursor = [], None
    for _ in range(10):
        page, cursor = await c.book_service.my_bookings(user_id=user.id, cursor=cursor, limit=100)
        bookings.extend(page)
        if not cursor:
            break
    series = p.series([("booked", "Bookings"), ("browsed", "Places browsed")])
    now, before = collections.Counter(), collections.Counter()
    categories = collections.Counter()
    spend, currency = 0, None
    today = p.now.date()
    upcoming = [b for b in bookings if b.date >= today and str(b.status) == "confirmed"]
    for b in bookings:
        moment = _when(b.created_at)
        period = p.which(moment)
        if period is None or str(b.status) == "cancelled":
            continue
        (now if period == "now" else before)["booked"] += 1
        if period == "now":
            p.add(series, moment, "booked")
            spend += (b.estimated_total_min_minor_units + b.estimated_total_max_minor_units) // 2
            currency = currency or b.currency
            listing = await c.book_repository.get_listing(b.listing_id)
            if listing:
                categories[str(getattr(listing.category, "value", listing.category)).replace("_", " ").title()] += 1
    for a in acts:
        if a["obj"].get("platform") == "book" and a.get("verb") in CONSUME and p.which(a["moment"]) == "now":
            p.add(series, a["moment"], "browsed")
            now["browsed"] += 1
    insights = []
    if upcoming:
        nxt = min(upcoming, key=lambda b: b.date)
        insights.append(f"Next up: {nxt.title} on {nxt.date.strftime('%a %d %b')}.")
    if categories:
        insights.append(f"You book {categories.most_common(1)[0][0].lower()} the most.")
    return _section(
        "book", "Book", currency=currency, has_data=bool(bookings or now["browsed"]),
        headline=dict(label="Bookings", value=now["booked"], format="count", change=_pct(now["booked"], before["booked"])),
        kpis=[
            _kpi("booked", "Bookings", now["booked"], change=_pct(now["booked"], before["booked"])),
            _kpi("upcoming", "Upcoming", len(upcoming)),
            _kpi("spend", "Estimated spend", spend, "money"),
            _kpi("browsed", "Places browsed", now["browsed"]),
        ],
        series=series,
        breakdown=dict(title="What you booked", format="count",
                       items=[dict(label=k, value=v) for k, v in categories.most_common()]),
        top=dict(title="Upcoming", items=[
            dict(title=b.title, subtitle=f"{b.venue} · {b.date.strftime('%d %b')}", value=b.participants,
                 format="count") for b in sorted(upcoming, key=lambda b: b.date)[:5]]),
        insights=insights,
    )


# -- Social ----------------------------------------------------------------------------------------

async def _social(c, user, p: Period) -> dict:
    data = await social_insights(days=p.days, user=user, c=c)
    moments_now = moments_before = 0
    for row in await c.graph.store.rows("social_moment", {"author": user.id}):
        period = p.which(_when(row.get("created_at")))
        moments_now += period == "now"
        moments_before += period == "before"
    viewers = {v["user_id"] for v in await c.graph.store.rows("moment_view", {"author": user.id})
               if p.which(_when(v.get("seen_at"))) == "now" and v.get("user_id") != user.id}
    series = dict(keys=[dict(id="views", label="Views"), dict(id="interactions", label="Interactions")],
                  days=[dict(day=d["day"], views=d["views"], interactions=d["interactions"]) for d in data["series"]][-p.days:])
    inter = data["interactions"]
    insights = [line for line in (_trend_line("views", data["views"]["change"]),
                                  _trend_line("follower growth", data["followers"]["change"])) if line]
    if data.get("peak_hour") is not None:
        h = data["peak_hour"]
        insights.append(f"Your audience is most active around {h % 12 or 12} {'AM' if h < 12 else 'PM'}.")
    return _section(
        "social", "Social",
        has_data=bool(data["views"]["value"] or data["content"]["value"] or moments_now or data["followers"]["value"]),
        headline=dict(label="Views", value=data["views"]["value"], format="count", change=data["views"]["change"]),
        kpis=[
            _kpi("views", "Views", data["views"]["value"], change=data["views"]["change"]),
            _kpi("interactions", "Interactions", inter["value"], change=inter["change"]),
            _kpi("followers", "New followers", data["followers"]["value"], change=data["followers"]["change"]),
            _kpi("content", "Posts shared", data["content"]["value"], change=data["content"]["change"]),
            _kpi("moments", "Moments posted", moments_now, change=_pct(moments_now, moments_before)),
            _kpi("moment_viewers", "Moment viewers", len(viewers)),
        ],
        series=series,
        breakdown=dict(title="How people interact", format="count", items=[
            dict(label=label, value=inter[k]) for k, label in
            (("liked", "Likes"), ("commented", "Comments"), ("saved", "Saves"), ("shared", "Shares"), ("reposted", "Reposts"))]),
        top=dict(title="Top content", items=[
            dict(title=t["title"], subtitle=str(t.get("type") or "").title(), value=t["views"], format="count",
                 image_url=t.get("image_url")) for t in data["top_content"]]),
        insights=insights, extra=dict(active_hours=data["active_hours"]),
    )


# -- Endpoint --------------------------------------------------------------------------------------

LABELS = {"social": "Social", "pay": "Pay", "messages": "Messages", "rooms": "Rooms", "stream": "Stream",
          "news": "News", "shop": "Shop", "book": "Book"}


@router.get("/profile/dashboard")
async def dashboard(days: int = Query(30, ge=7, le=90), user=Depends(get_current_user), c=Depends(get_container)):
    cache_key = f"dashboard:{user.id}:{days}:{await c.graph.store.revision()}"
    cached = await c.cache.get(cache_key)
    if cached is not None:
        return cached
    p = Period(days)
    acts = await _my_activity(c, user)
    makers = {
        "social": lambda: _social(c, user, p),
        "pay": lambda: _pay(c, user, p),
        "messages": lambda: _messages(c, user, p),
        "rooms": lambda: _rooms(c, user, p),
        "stream": lambda: _stream(c, user, p, acts),
        "news": lambda: _news(c, user, p, acts),
        "shop": lambda: _shop(c, user, p, acts),
        "book": lambda: _book(c, user, p, acts),
    }
    sections = {}
    for name, make in makers.items():
        try:
            sections[name] = await make()
        except Exception:
            log.exception("dashboard.section_failed section=%s", name)
            sections[name] = _empty(name, LABELS[name])

    # Overview: how much you did on each platform, day by day.
    mix = collections.Counter()
    daily = p.series([(k, LABELS[k]) for k in makers])
    active_days = set()

    def tally(platform, moment, n=1):
        if p.which(moment) == "now":
            mix[platform] += n
            p.add(daily, moment, platform, n)
            active_days.add(moment.date())

    for a in acts:
        platform = a["obj"].get("platform")
        if platform in {"stream", "news", "shop", "book", "social"}:
            tally(platform, a["moment"])
    def per_day(name: str) -> list[int]:
        section = sections[name]
        if name == "pay":
            return section["extra"].get("daily_count") or []
        days_ = (section.get("series") or {}).get("days") or []
        # Messages: everything sent and received; rooms: your own messages.
        field = {"messages": ("sent", "received"), "rooms": ("mine",)}[name]
        return [sum(d.get(f, 0) for f in field) for d in days_]

    for name in ("pay", "messages", "rooms"):
        for i, n in enumerate(per_day(name)):
            if n:
                tally(name, dt.datetime.fromisoformat(p.labels[i]).replace(tzinfo=dt.UTC, hour=12), n)
    for row in await c.graph.store.rows("phlio_object", {"owner": user.id}):
        tally("social", _when(row.get("created_at")))
    favourite = mix.most_common(1)[0][0] if mix else None
    overview = dict(
        mix=[dict(id=k, label=LABELS[k], value=mix[k]) for k in makers],
        total=sum(mix.values()),
        active_days=len(active_days),
        favourite=favourite,
        series=daily,
        headlines=[dict(id=k, label=s["label"], has_data=s["has_data"], currency=s.get("currency"),
                        metric=s["headline"]["label"], value=s["headline"]["value"],
                        format=s["headline"]["format"], change=s["headline"].get("change"))
                   for k, s in sections.items()],
        insights=[x for x in (
            f"{LABELS[favourite]} is your most-used part of Phlio." if favourite else None,
            f"You were active on {len(active_days)} of the last {days} days." if active_days else None,
            sections["pay"]["insights"][0] if sections["pay"]["insights"] else None,
        ) if x],
    )
    result = dict(days=days, start=p.start.date().isoformat(), end=p.now.date().isoformat(),
                  overview=overview, sections=[sections[k] for k in makers])
    await c.cache.put(cache_key, result, ttl=60)
    return result
