"""
Festival and event calendar behind the seasonal banners in Social, Shop,
Book (and the other platforms).

Each event has a rule that gives its date in a year:

* ``fixed(month, day)``            Christmas, Valentine's Day, Songkran...
* ``nth_weekday(month, wd, n)``    Thanksgiving (4th Thursday of November),
                                   Mother's Day (2nd Sunday of May); ``n=-1``
                                   is the last one in the month
* ``easter(offset)``               Western Easter (and Good Friday with -2)
* ``table({year: (m, d)})``        lunar / lunisolar festivals (Diwali, Holi,
                                   Eid, Lunar New Year, Hanukkah...) whose
                                   date moves every year. These come from
                                   published calendars and are marked
                                   ``approximate`` where the day depends on
                                   moon sighting (the Eids, Ramadan). Add the
                                   next years here when they are announced;
                                   an event with no entry for a year simply
                                   doesn't show that year.

A banner is shown from ``lead`` days before the event until ``days`` days
after it starts. Events tagged with regions (ISO country codes) are shown
first to people in those regions; ``GLOBAL`` events are shown to everyone.
Copy is per platform so the same festival can say "share your moments" in
Social, "festive deals" in Shop and "plan the trip home" in Book.
"""

from __future__ import annotations

import datetime as dt
from collections.abc import Callable
from dataclasses import dataclass, field

Rule = Callable[[int], dt.date | None]
GLOBAL = "GLOBAL"
PLATFORMS = ("social", "shop", "book", "stream", "news", "rooms", "pay")


def fixed(month: int, day: int) -> Rule:
    return lambda year: dt.date(year, month, day)


def nth_weekday(month: int, weekday: int, n: int) -> Rule:
    """``weekday``: Monday=0 ... Sunday=6; ``n``: 1-based, or -1 for the last."""

    def rule(year: int) -> dt.date:
        if n > 0:
            first = dt.date(year, month, 1)
            return first + dt.timedelta(days=(weekday - first.weekday()) % 7 + 7 * (n - 1))
        last = (dt.date(year + (month == 12), month % 12 + 1, 1)) - dt.timedelta(days=1)
        return last - dt.timedelta(days=(last.weekday() - weekday) % 7)

    return rule


def _easter(year: int) -> dt.date:
    """Anonymous Gregorian algorithm (Meeus/Jones/Butcher)."""
    a, b, c = year % 19, year // 100, year % 100
    d, e = b // 4, b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c // 4, c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day = (h + l - 7 * m + 114) % 31 + 1
    return dt.date(year, month, day)


def easter(offset: int = 0) -> Rule:
    return lambda year: _easter(year) + dt.timedelta(days=offset)


def table(dates: dict[int, tuple[int, int]]) -> Rule:
    return lambda year: dt.date(year, *dates[year]) if year in dates else None


def after(rule: Rule, days: int) -> Rule:
    return lambda year: (d + dt.timedelta(days=days)) if (d := rule(year)) else None


@dataclass(frozen=True)
class Event:
    id: str
    name: str
    rule: Rule
    regions: tuple[str, ...] = (GLOBAL,)
    days: int = 1  # how long the event itself lasts
    lead: int = 5  # banner starts this many days before
    emoji: str = "✨"
    motif: str = "sparkles"  # what the app animates: diyas, lanterns, snow, hearts, confetti...
    colors: tuple[str, ...] = ("#8D78FF", "#E795D7")
    greeting: str = ""
    approximate: bool = False
    copy: dict[str, str] = field(default_factory=dict)  # platform -> line
    weight: int = 1  # bigger festivals win when several overlap


DIWALI = table({2025: (10, 20), 2026: (11, 8), 2027: (10, 29), 2028: (10, 17), 2029: (11, 5), 2030: (10, 26)})
LUNAR_NEW_YEAR = table({2025: (1, 29), 2026: (2, 17), 2027: (2, 6), 2028: (1, 26), 2029: (2, 13), 2030: (2, 3)})
EID_AL_FITR = table({2025: (3, 30), 2026: (3, 20), 2027: (3, 9), 2028: (2, 26), 2029: (2, 14), 2030: (2, 4)})
EID_AL_ADHA = table({2025: (6, 6), 2026: (5, 27), 2027: (5, 16), 2028: (5, 5), 2029: (4, 24), 2030: (4, 13)})
RAMADAN = table({2025: (3, 1), 2026: (2, 18), 2027: (2, 8), 2028: (1, 28), 2029: (1, 16), 2030: (1, 6)})
HOLI = table({2025: (3, 14), 2026: (3, 4), 2027: (3, 22), 2028: (3, 11), 2029: (3, 1), 2030: (3, 20)})
# First full day (candles are lit the evening before).
HANUKKAH = table({2025: (12, 15), 2026: (12, 5), 2027: (12, 25), 2028: (12, 13), 2029: (12, 2), 2030: (12, 21)})
MID_AUTUMN = table({2025: (10, 6), 2026: (9, 25), 2027: (9, 15), 2028: (10, 3), 2029: (9, 22), 2030: (9, 12)})
GANESH_CHATURTHI = table({2025: (8, 27), 2026: (9, 14), 2027: (9, 4), 2028: (8, 23), 2029: (9, 11), 2030: (9, 1)})
NAVRATRI = table({2025: (9, 22), 2026: (10, 11), 2027: (9, 30), 2028: (9, 19), 2029: (10, 8), 2030: (9, 27)})
RAKSHA_BANDHAN = table({2025: (8, 9), 2026: (8, 28), 2027: (8, 17), 2028: (8, 5), 2029: (8, 23), 2030: (8, 13)})

THANKSGIVING = nth_weekday(11, 3, 4)

EVENTS: tuple[Event, ...] = (
    Event("new-year", "New Year", fixed(1, 1), days=1, lead=4, emoji="🎆", motif="fireworks",
          colors=("#1B1F4B", "#8D78FF", "#FFC56E"), greeting="Happy New Year!", weight=3,
          copy=dict(social="Share your countdown moments", shop="New year, new picks",
                    book="Plan your first trip of the year", stream="Countdown party playlists")),
    Event("lunar-new-year", "Lunar New Year", LUNAR_NEW_YEAR, regions=("CN", "TW", "HK", "SG", "KR", "VN", "MY", GLOBAL),
          days=3, emoji="🏮", motif="lanterns", colors=("#B3001B", "#FF4D4D", "#FFC56E"),
          greeting="Happy Lunar New Year!", weight=3,
          copy=dict(social="Share reunion-dinner moments", shop="Red envelopes and festive gifts",
                    book="Book the trip home")),
    Event("pongal", "Pongal & Makar Sankranti", fixed(1, 14), regions=("IN",), days=2, emoji="🪁", motif="kites",
          colors=("#FF9F1C", "#FFBF69", "#2EC4B6"), greeting="Happy Pongal & Sankranti!",
          copy=dict(social="Show us your kites", shop="Harvest festival essentials")),
    Event("republic-day-in", "Republic Day", fixed(1, 26), regions=("IN",), lead=2, emoji="🇮🇳", motif="confetti",
          colors=("#FF9933", "#FFFFFF", "#138808"), greeting="Happy Republic Day!"),
    Event("valentines", "Valentine's Day", fixed(2, 14), lead=7, emoji="💘", motif="hearts",
          colors=("#FF4D6D", "#E795D7"), greeting="Happy Valentine's Day!", weight=2,
          copy=dict(social="Send some love", shop="Gifts they'll love", book="Dinner for two, booked",
                    stream="Love songs on repeat")),
    Event("ramadan", "Ramadan", RAMADAN, regions=("AE", "SA", "QA", "KW", "BH", "OM", "EG", "ID", "MY", "PK", "BD", "TR", "IN", GLOBAL),
          days=29, lead=2, emoji="🌙", motif="lanterns", colors=("#0B3D2E", "#1E7F5C", "#FFD27D"),
          greeting="Ramadan Mubarak", approximate=True,
          copy=dict(social="Share your iftar moments", shop="Iftar and suhoor essentials",
                    book="Iftar tables near you")),
    Event("womens-day", "International Women's Day", fixed(3, 8), lead=2, emoji="💜", motif="sparkles",
          colors=("#5B2A86", "#C77DFF"), greeting="Happy Women's Day!",
          copy=dict(social="Celebrate the women who inspire you", shop="Shop women-led brands")),
    Event("holi", "Holi", HOLI, regions=("IN", "NP", GLOBAL), days=1, emoji="🎨", motif="colors",
          colors=("#FF006E", "#FFBE0B", "#3A86FF", "#8338EC"), greeting="Happy Holi!", weight=3,
          copy=dict(social="Share your colours", shop="Colours, sweets and whites", book="Holi parties near you")),
    Event("st-patricks", "St Patrick's Day", fixed(3, 17), regions=("IE", "GB", "US", "CA", "AU"), lead=3, emoji="☘️",
          motif="confetti", colors=("#0B6E4F", "#40C057")),
    Event("eid-al-fitr", "Eid al-Fitr", EID_AL_FITR, regions=("AE", "SA", "QA", "KW", "BH", "OM", "EG", "ID", "MY", "PK", "BD", "TR", "IN", GLOBAL),
          days=3, lead=4, emoji="🌙", motif="lanterns", colors=("#0B3D2E", "#1E7F5C", "#FFD27D"),
          greeting="Eid Mubarak!", approximate=True, weight=3,
          copy=dict(social="Share your Eid moments", shop="Eid gifts and outfits", book="Eid feasts and family trips")),
    Event("good-friday-easter", "Easter", easter(-2), days=4, lead=5, emoji="🐣", motif="confetti",
          colors=("#FFD6E0", "#C1E1C1", "#FFF1A8"), greeting="Happy Easter!", weight=2,
          copy=dict(social="Share your Easter moments", shop="Easter treats and gifts", book="Long-weekend getaways")),
    Event("songkran", "Songkran", fixed(4, 13), regions=("TH", "LA", "MM", "KH"), days=3, emoji="💦", motif="splash",
          colors=("#00B4D8", "#90E0EF"), greeting="Happy Songkran!"),
    Event("earth-day", "Earth Day", fixed(4, 22), lead=2, emoji="🌍", motif="leaves", colors=("#2D6A4F", "#74C69D"),
          copy=dict(social="Show us your green habits", shop="Sustainable picks")),
    Event("mothers-day", "Mother's Day", nth_weekday(5, 6, 2), regions=("US", "CA", "IN", "AU", "DE", "IT", "JP", "CN", GLOBAL),
          lead=7, emoji="💐", motif="petals", colors=("#FF8FAB", "#FFC2D1"), greeting="Happy Mother's Day!", weight=2,
          copy=dict(social="Thank your mum", shop="Gifts for mum", book="Brunch with mum, booked")),
    Event("eid-al-adha", "Eid al-Adha", EID_AL_ADHA, regions=("AE", "SA", "QA", "KW", "BH", "OM", "EG", "ID", "MY", "PK", "BD", "TR", "IN", GLOBAL),
          days=3, lead=3, emoji="🕌", motif="lanterns", colors=("#0B3D2E", "#1E7F5C", "#FFD27D"),
          greeting="Eid al-Adha Mubarak!", approximate=True, weight=2),
    Event("pride", "Pride Month", fixed(6, 1), days=30, lead=0, emoji="🏳️‍🌈", motif="rainbow",
          colors=("#E40303", "#FF8C00", "#FFED00", "#008026", "#004DFF", "#750787"), greeting="Happy Pride!"),
    Event("fathers-day", "Father's Day", nth_weekday(6, 6, 3), regions=("US", "CA", "IN", "GB", "JP", GLOBAL), lead=7,
          emoji="👔", motif="confetti", colors=("#1D3557", "#457B9D"), greeting="Happy Father's Day!",
          copy=dict(shop="Gifts for dad", book="Plans with dad")),
    Event("canada-day", "Canada Day", fixed(7, 1), regions=("CA",), lead=2, emoji="🍁", motif="fireworks",
          colors=("#D80621", "#FFFFFF")),
    Event("independence-day-us", "Independence Day", fixed(7, 4), regions=("US",), lead=3, emoji="🎆", motif="fireworks",
          colors=("#B22234", "#3C3B6E"), greeting="Happy 4th of July!"),
    Event("raksha-bandhan", "Raksha Bandhan", RAKSHA_BANDHAN, regions=("IN",), lead=6, emoji="🪢", motif="sparkles",
          colors=("#FF7F11", "#FF3F00", "#FFD166"), greeting="Happy Raksha Bandhan!",
          copy=dict(social="Tag your sibling", shop="Rakhis and gifts", book="Travel home for Rakhi")),
    Event("independence-day-in", "Independence Day", fixed(8, 15), regions=("IN",), lead=2, emoji="🇮🇳", motif="kites",
          colors=("#FF9933", "#FFFFFF", "#138808"), greeting="Happy Independence Day!"),
    Event("ganesh-chaturthi", "Ganesh Chaturthi", GANESH_CHATURTHI, regions=("IN",), days=10, lead=3, emoji="🪔",
          motif="petals", colors=("#FF6D00", "#FFB300"), greeting="Ganpati Bappa Morya!",
          copy=dict(social="Share your pandal visits", shop="Modaks, decor and puja kits")),
    Event("mid-autumn", "Mid-Autumn Festival", MID_AUTUMN, regions=("CN", "TW", "HK", "SG", "VN", "MY"), lead=5,
          emoji="🥮", motif="lanterns", colors=("#2B2D42", "#F4A261"), greeting="Happy Mid-Autumn Festival!",
          copy=dict(shop="Mooncakes and lanterns")),
    Event("navratri", "Navratri & Durga Puja", NAVRATRI, regions=("IN", "NP", "BD"), days=10, lead=3, emoji="💃",
          motif="sparkles", colors=("#D00000", "#FFBA08", "#3F88C5"), greeting="Happy Navratri!", weight=2,
          copy=dict(social="Garba nights and pandal hopping", shop="Festive ethnic wear", book="Garba and Dandiya passes")),
    Event("dussehra", "Dussehra", after(NAVRATRI, 9), regions=("IN", "NP"), lead=1, emoji="🏹", motif="fireworks",
          colors=("#D00000", "#FFBA08"), greeting="Happy Dussehra!"),
    Event("diwali", "Diwali", DIWALI, regions=("IN", "NP", "SG", "MY", "LK", "MU", "FJ", "GB", "US", GLOBAL), days=5, lead=10,
          emoji="🪔", motif="diyas", colors=("#2A0845", "#FF6F00", "#FFC300"), greeting="Happy Diwali!", weight=4,
          copy=dict(social="Light up your moments", shop="Diwali deals on gifts, lights and sweets",
                    book="Book the trip home for Diwali", stream="Festive playlists", pay="Send Diwali shagun")),
    Event("halloween", "Halloween", fixed(10, 31), regions=("US", "CA", "GB", "IE", "AU", GLOBAL), lead=7, emoji="🎃",
          motif="bats", colors=("#1A1A2E", "#FF7518"), greeting="Happy Halloween!", weight=2,
          copy=dict(social="Show off your costume", shop="Costumes and candy", stream="Spooky watchlist")),
    Event("dia-de-muertos", "Día de Muertos", fixed(11, 1), regions=("MX",), days=2, lead=3, emoji="💀",
          motif="petals", colors=("#FF6B35", "#9B5DE5")),
    Event("singles-day", "11.11 Sale", fixed(11, 11), regions=("CN", "SG", "MY", "ID", "TH", "VN", "PH", GLOBAL), lead=3,
          emoji="🛍️", motif="confetti", colors=("#FF3D00", "#FF9100"), weight=1,
          copy=dict(shop="11.11 deals are live")),
    Event("thanksgiving", "Thanksgiving", THANKSGIVING, regions=("US",), lead=8, emoji="🦃", motif="leaves",
          colors=("#7F5539", "#DDB892"), greeting="Happy Thanksgiving!",
          copy=dict(social="What are you thankful for?", book="Thanksgiving dinner reservations")),
    Event("black-friday", "Black Friday", after(THANKSGIVING, 1), days=4, lead=10, emoji="🖤", motif="confetti",
          colors=("#0D0D0D", "#E63946"), weight=2,
          copy=dict(shop="Black Friday to Cyber Monday deals")),
    Event("hanukkah", "Hanukkah", HANUKKAH, regions=("IL", "US", "CA", "GB", "FR", GLOBAL), days=8, lead=3, emoji="🕎",
          motif="candles", colors=("#0038B8", "#A9D6E5"), greeting="Happy Hanukkah!"),
    Event("christmas", "Christmas", fixed(12, 25), days=2, lead=14, emoji="🎄", motif="snow",
          colors=("#0B3D20", "#C1121F", "#FFD166"), greeting="Merry Christmas!", weight=4,
          copy=dict(social="Share your festive moments", shop="Christmas gifts for everyone",
                    book="Christmas dinners and winter stays", stream="Holiday movies and carols")),
    Event("new-years-eve", "New Year's Eve", fixed(12, 31), lead=3, emoji="🥂", motif="fireworks",
          colors=("#1B1F4B", "#8D78FF", "#FFC56E"), weight=2,
          copy=dict(social="Go live at midnight", book="NYE parties near you", shop="Party essentials")),
)

DEFAULT_COPY = dict(
    social="Share your {name} moments", shop="{name} picks and deals", book="Plans for {name}",
    stream="Watch and listen for {name}", news="{name} around the world", rooms="Celebrate {name} together",
    pay="Send {name} wishes",
)


def occurrence(event: Event, today: dt.date) -> tuple[dt.date, dt.date] | None:
    """The (start, end) of the occurrence whose banner window contains ``today``."""
    for year in (today.year - 1, today.year, today.year + 1):
        start = event.rule(year)
        if start is None:
            continue
        end = start + dt.timedelta(days=event.days - 1)
        if start - dt.timedelta(days=event.lead) <= today <= end:
            return start, end
    return None


def active(today: dt.date, platform: str = "social", region: str | None = None, limit: int = 2) -> list[dict]:
    """Banners to show today on ``platform`` for someone in ``region``."""
    region = (region or "").upper() or None
    out = []
    for e in EVENTS:
        when = occurrence(e, today)
        if not when:
            continue
        local = bool(region and region in e.regions)
        if not (GLOBAL in e.regions or local or region is None):
            continue
        start, end = when
        days_to = (start - today).days
        out.append(dict(
            id=e.id, name=e.name, emoji=e.emoji, motif=e.motif, colors=list(e.colors),
            greeting=e.greeting or f"Happy {e.name}!",
            line=e.copy.get(platform) or DEFAULT_COPY.get(platform, DEFAULT_COPY["social"]).format(name=e.name),
            starts_on=start.isoformat(), ends_on=end.isoformat(),
            status="live" if days_to <= 0 else "upcoming", days_to=max(days_to, 0),
            approximate=e.approximate, local=local,
            _rank=(local, e.weight, days_to <= 0, -abs(days_to)),
        ))
    out.sort(key=lambda b: b["_rank"], reverse=True)
    for b in out:
        b.pop("_rank")
    return out[:limit]


def upcoming(today: dt.date, region: str | None = None, days: int = 60) -> list[dict]:
    """Every event starting in the next ``days`` days (for a calendar view)."""
    region = (region or "").upper() or None
    found = []
    for e in EVENTS:
        if region and not (GLOBAL in e.regions or region in e.regions):
            continue
        for year in (today.year, today.year + 1):
            start = e.rule(year)
            if start and today <= start + dt.timedelta(days=e.days - 1) and start <= today + dt.timedelta(days=days):
                found.append(dict(id=e.id, name=e.name, emoji=e.emoji, starts_on=start.isoformat(),
                                  approximate=e.approximate))
                break
    return sorted(found, key=lambda x: x["starts_on"])
