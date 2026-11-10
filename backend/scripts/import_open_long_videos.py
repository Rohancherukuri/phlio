"""Longer Social videos (1-7 minutes) from openly licensed sources.

Two sources, both free to reuse with credit:

* **Blender Foundation open movies** (CC BY): Sintel, Big Buck Bunny,
  Elephants Dream and Tears of Steel, cut into chapters of up to seven
  minutes. Uses the copies import_open_movie_clips already downloaded to
  data/open_movies/ (fetched here if missing).
* **Wikimedia Commons**: videos found by topic search (nature, space,
  oceans, cities, music, food, travel, science...). Only files whose licence
  allows reuse (public domain, CC0, CC BY, CC BY-SA) and that run 60-420 s
  are taken. Each keeps its author, licence and source page as attribution.

Every video is posted by one of the community creators (demo_000-019): each
creator has a beat (the space nerd, the travel vlogger, the film buff...), so
uploads look like a real channel's. Titles, descriptions and tags come from
the source, cleaned up. Engagement (views, likes, saves, shares, reposts)
comes from the community accounts, like the open-movie clips; comments come
from seed_community_comments (run it afterwards).

Videos are re-encoded to 720p H.264 with a 360p data-saver copy, and land in
media/open_long/ so publish_local_data uploads them to R2. Rows go to the
social-videos SQLite and the graph (SurrealDB), so they publish too.

Idempotent: rerunning skips finished videos. --reset removes them.
Run: uv run python -m scripts.import_open_long_videos [--reset] [--max 40]
"""
from __future__ import annotations

import argparse
import asyncio
import datetime as dt
import hashlib
import html
import json
import random
import re
import subprocess
from pathlib import Path

import httpx

from app.core.container import build_container, media_root_path
from app.domains.graph.service import key
from app.infrastructure.video_thumbnail import make_thumbnail
from scripts.import_open_movie_clips import FILMS, download, engage, healthy, probe
from scripts.run_graph_demo import settings

SEED = "open-long-v1"
PREFIX = "open_long_"
MIN_SECONDS, MAX_SECONDS = 60, 420
COMMONS = "https://commons.wikimedia.org/w/api.php"
# Wikimedia asks automated clients to identify themselves.
HEADERS = {"User-Agent": "PhlioDemoSeeder/1.0 (local demo data; python-httpx)"}
ALLOWED_LICENSES = re.compile(r"^(cc0|public domain|pd|cc by(-sa)? [0-9.]+|cc-by(-sa)?-[0-9.]+)", re.I)

# Film chapters: (film slug, part title, start s, end s). Ends are clamped to
# the film's length; each chapter stays within 60-420 s.
CHAPTERS = [
    ("sintel", "Part 1 · The Baby Dragon", 0, 300),
    ("sintel", "Part 2 · The Search", 300, 600),
    ("sintel", "Part 3 · The Cave", 600, 900),
    ("bbb", "Part 1 · A Perfect Morning", 0, 300),
    ("bbb", "Part 2 · Payback", 300, 600),
    ("elephants", "Part 1 · The Machine", 0, 330),
    ("elephants", "Part 2 · Emo and Proog", 330, 660),
    ("tears", "Part 1 · Amsterdam, the Future", 0, 370),
    ("tears", "Part 2 · The Bridge", 370, 740),
]
FILM_CREATOR_BEAT = "film"

# Commons topics: (beat, search, tags). Each beat maps to one creator.
TOPICS = [
    ("space", "International Space Station earth view", ["space", "nasa", "iss", "earth"]),
    ("space", "NASA rocket launch", ["space", "nasa", "launch", "rocket"]),
    ("nature", "wildlife documentary", ["nature", "wildlife", "animals"]),
    ("nature", "birds nature film", ["nature", "birds", "wildlife"]),
    ("ocean", "coral reef underwater", ["ocean", "underwater", "reef"]),
    ("ocean", "whales ocean", ["ocean", "whales", "marine"]),
    ("city", "city timelapse night", ["timelapse", "city", "night"]),
    ("travel", "train journey railway", ["travel", "train", "journey"]),
    ("travel", "drone aerial landscape", ["travel", "aerial", "drone", "landscape"]),
    ("earth", "volcano eruption lava", ["earth", "volcano", "science"]),
    ("earth", "aurora borealis", ["sky", "aurora", "night"]),
    ("music", "orchestra concert performance", ["music", "live", "orchestra"]),
    ("music", "folk music performance", ["music", "live", "folk"]),
    ("food", "cooking recipe", ["food", "cooking", "recipe"]),
    ("science", "science experiment demonstration", ["science", "experiment", "learn"]),
    ("history", "historical film archive", ["history", "archive", "vintage"]),
]
BEATS = ["film", "space", "nature", "ocean", "city", "travel", "earth", "music", "food", "science", "history"]
EXTRA_TAGS = ["fyp", "longform", "watchlater", "creativecommons", "documentary", "4you", "phlio"]


# ---------------------------------------------------------------------------
# Wikimedia Commons search


def _plain(value: str | None, limit: int = 400) -> str:
    """Commons metadata is HTML; keep readable text."""
    text = re.sub(r"<[^>]+>", " ", value or "")
    text = re.sub(r"\s+", " ", html.unescape(text)).strip()
    return text if len(text) <= limit else text[: limit - 1].rsplit(" ", 1)[0] + "…"


def _title(file_title: str) -> str:
    name = file_title.removeprefix("File:").rsplit(".", 1)[0]
    name = re.sub(r"[_]+", " ", name)
    name = re.sub(r"\s*\((?:[0-9]{3,4}p|HD|hd|720p|1080p|webm)\)\s*", " ", name)
    name = re.sub(r"\s+", " ", name).strip(" -–")
    return name[:90]


def _duration(info: dict) -> float | None:
    for item in info.get("metadata") or []:
        if item.get("name") in ("length", "playtime_seconds", "duration"):
            try:
                return float(item["value"])
            except (TypeError, ValueError):
                pass
    return None


def search_commons(client: httpx.Client, query: str, wanted: int, seen: set[str]) -> list[dict]:
    """Up to `wanted` reusable 1-7 minute videos for `query`."""
    params = {
        "action": "query", "format": "json", "formatversion": "2",
        "generator": "search", "gsrnamespace": "6", "gsrlimit": "40",
        "gsrsearch": f"{query} filetype:video",
        "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata|metadata",
        "iiextmetadatafilter": "LicenseShortName|LicenseUrl|Artist|Credit|ImageDescription|DateTimeOriginal",
    }
    try:
        pages = client.get(COMMONS, params=params).raise_for_status().json().get("query", {}).get("pages", [])
    except (httpx.HTTPError, ValueError) as exc:
        print(f"  Commons search failed for {query!r}: {exc}", flush=True)
        return []
    found = []
    for page in sorted(pages, key=lambda p: p.get("index", 0)):
        info = (page.get("imageinfo") or [{}])[0]
        meta = info.get("extmetadata") or {}
        license_name = _plain((meta.get("LicenseShortName") or {}).get("value"), 60)
        if page["title"] in seen or not ALLOWED_LICENSES.match(license_name):
            continue
        if not str(info.get("mime", "")).startswith("video/") or info.get("size", 0) > 700_000_000:
            continue
        if (info.get("width") or 0) < 480:
            continue
        seconds = _duration(info)
        if seconds is None or not MIN_SECONDS <= seconds <= MAX_SECONDS:
            continue
        found.append(dict(
            title=_title(page["title"]), file_title=page["title"], url=info["url"],
            page_url=info.get("descriptionurl") or f"https://commons.wikimedia.org/wiki/{page['title']}",
            seconds=seconds, license=license_name,
            license_url=(meta.get("LicenseUrl") or {}).get("value") or "",
            author=_plain((meta.get("Artist") or {}).get("value"), 120) or "Unknown author",
            description=_plain((meta.get("ImageDescription") or {}).get("value"), 360)))
        seen.add(page["title"])
        if len(found) >= wanted:
            break
    return found


def fetch(client: httpx.Client, url: str, target: Path) -> bool:
    partial = target.with_suffix(target.suffix + ".part")
    try:
        with client.stream("GET", url) as response:
            response.raise_for_status()
            with partial.open("wb") as out:
                for chunk in response.iter_bytes(1024 * 1024):
                    out.write(chunk)
        partial.replace(target)
        return True
    except (httpx.HTTPError, OSError) as exc:
        print(f"  download failed ({exc})", flush=True)
        partial.unlink(missing_ok=True)
        return False


# ---------------------------------------------------------------------------
# Encoding


def encode(source: Path, target: Path, start: float, seconds: float, height: int, crf: int) -> bool:
    """Landscape H.264 at `height` (no crop). Tolerates damaged audio by
    retrying without sound."""
    base = ["ffmpeg", "-nostdin", "-v", "fatal", "-y", "-err_detect", "ignore_err", "-ss", f"{start:.2f}",
            "-i", str(source), "-t", f"{seconds:.2f}",
            "-vf", f"scale=-2:'min({height},ih)',fps=30", "-c:v", "libx264", "-preset", "veryfast",
            "-crf", str(crf), "-pix_fmt", "yuv420p"]
    for audio in (["-c:a", "aac", "-b:a", "128k" if height >= 720 else "64k", "-ac", "2"], ["-an"]):
        try:
            subprocess.run(base + audio + ["-movflags", "+faststart", str(target)], check=True, timeout=1800)
        except (subprocess.SubprocessError, OSError):
            pass
        if healthy(target, min(seconds, MIN_SECONDS) - 2):
            return True
        target.unlink(missing_ok=True)
    return False


def cover_for(target: Path, cover: Path, seconds: float, fingerprints: list, rng: random.Random) -> bool:
    for prints in (fingerprints, None):
        try:
            make_thumbnail(target, cover, seconds, prints, offset=rng.randint(5, 40))
            return True
        except (ValueError, subprocess.SubprocessError):
            continue
    return cover.exists()


# ---------------------------------------------------------------------------


async def reset(c) -> int:
    rows = c.social_video_service.db.execute("SELECT id FROM videos WHERE id LIKE ?", (PREFIX + "%",)).fetchall()
    objects = {key("phlio_object", "social", row["id"]) for row in rows}
    removed = 0
    for row in await c.graph.store.rows("activity"):
        if str(row.get("out")) in objects:
            await c.graph.store.delete(row["id"])
            removed += 1
    for row in await c.graph.store.rows("share_event"):
        if str(row.get("object_id")) in objects:
            await c.graph.store.delete(row["id"])
            removed += 1
    for row in rows:
        for table in ("phlio_object", "platform_content"):
            await c.graph.store.delete(key(table, "social", row["id"]))
    c.social_video_service.db.execute("DELETE FROM videos WHERE id LIKE ?", (PREFIX + "%",))
    c.social_video_service.db.commit()
    return removed + len(rows)


async def publish(c, item: dict, creator: str, members: list[str], fingerprints: list, root: Path, now) -> dict | None:
    """Encodes one video (if needed) and writes its rows. Returns counts."""
    ref = item["ref"]
    rng = random.Random(hashlib.sha256((SEED + ref).encode()).hexdigest())
    name = ref.removeprefix(PREFIX).replace("_", "-")
    target, saver, cover = root / f"{name}.mp4", root / f"{name}-360p.mp4", root / f"{name}-cover.jpg"
    seconds = item["seconds"]
    if target.exists() and not healthy(target, min(seconds, MIN_SECONDS) - 2):
        target.unlink()
    if not target.exists() and not encode(item["source"], target, item.get("start", 0), seconds, 720, 25):
        print(f"  skipped {name}: could not encode", flush=True)
        return None
    seconds = probe(target)  # the real length of what we made
    if not saver.exists():
        encode(target, saver, 0, seconds, 360, 28)
    if not cover.exists() and not cover_for(target, cover, seconds, fingerprints, rng):
        print(f"  skipped {name}: no usable cover frame", flush=True)
        return None
    url, thumb = f"/media/open_long/{target.name}", f"/media/open_long/{cover.name}"
    posted = now - dt.timedelta(days=rng.uniform(0.3, 60), minutes=rng.randint(0, 900))
    db = c.social_video_service.db
    existing = db.execute("SELECT created_at FROM videos WHERE id=?", (ref,)).fetchone()
    if existing:
        posted = dt.datetime.fromisoformat(existing["created_at"])
    else:
        c.social_video_service.publish(ref, creator, item["title"], url, kind="video",
                                       duration_seconds=round(seconds))
        db.execute("UPDATE videos SET created_at=? WHERE id=?", (posted.isoformat(), ref))
    db.execute("UPDATE videos SET thumbnail_url=?, url=?, duration_seconds=?, title=? WHERE id=?",
               (thumb, url, round(seconds), item["title"], ref))
    db.commit()
    obj = await c.graph.register_object(creator, "social.video", ref, item["title"])
    if obj.get("created_at") != posted.isoformat():
        obj["created_at"] = posted.isoformat()
        obj = await c.graph.store.put(obj["id"], obj)
    tags = list(dict.fromkeys(item["tags"] + rng.sample(EXTRA_TAGS, 2)))
    sources = [dict(label="720p", url=url)]
    if saver.exists():
        sources.append(dict(label="360p (data saver)", url=f"/media/open_long/{saver.name}"))
    await c.graph.store.put(key("platform_content", "social", ref), dict(
        platform="social", domain_ref=ref, object_id=obj["id"], kind="video",
        description=item["description"], image_url=thumb, media_url=url, tags=tags, sources=sources,
        attribution=item["credit"], source_url=item["source_url"], license=item["license"],
        license_url=item["license_url"], visibility="public", seed=SEED))
    return await engage(c, obj, posted, [m for m in members if m != creator], rng, now)


def film_items() -> list[dict]:
    films = {f["slug"]: f for f in FILMS}
    items = []
    for n, (slug, part, start, end) in enumerate(CHAPTERS):
        film = films[slug]
        source = download(film)
        if source is None:
            continue
        end = min(end, probe(source) - 1)
        seconds = end - start
        if seconds < MIN_SECONDS:
            continue
        items.append(dict(
            ref=f"{PREFIX}film_{slug}_{n:02}", beat=FILM_CREATOR_BEAT, source=source, start=start,
            seconds=min(seconds, MAX_SECONDS), title=f"{film['title']} ({film['year']}) — {part}",
            tags=film["tags"] + ["fullfilm", "shortfilm"],
            description=(f"{film['title']}, {part.split('·')[-1].strip().lower()}. A Blender Foundation open "
                         f"movie from {film['year']}, made entirely with open-source tools.\n\n{film['credit']}."),
            credit=film["credit"], source_url=film["urls"][0], license=film["license"],
            license_url=film["license_url"]))
    return items


def commons_items(limit: int, cache: Path) -> list[dict]:
    """Searches Commons (once; the picks are cached in cache/picks.json so
    reruns are stable) and downloads the chosen originals to `cache`."""
    cache.mkdir(parents=True, exist_ok=True)
    picks_file = cache / "picks.json"
    picks = json.loads(picks_file.read_text(encoding="utf-8")) if picks_file.exists() else []
    with httpx.Client(timeout=120, follow_redirects=True, headers=HEADERS) as client:
        if len(picks) < limit:
            seen = {p["file_title"] for p in picks}
            per_topic = max(1, -(-(limit - len(picks)) // len(TOPICS)))
            for beat, query, tags in TOPICS:
                if len(picks) >= limit:
                    break
                print(f"Searching Commons: {query}", flush=True)
                for found in search_commons(client, query, per_topic, seen):
                    picks.append(dict(found, beat=beat, tags=tags))
            picks_file.write_text(json.dumps(picks, indent=2, ensure_ascii=False), encoding="utf-8")
        items = []
        for pick in picks[:limit]:
            digest = hashlib.sha1(pick["file_title"].encode()).hexdigest()[:10]
            source = cache / (digest + Path(pick["url"]).suffix.lower())
            if not source.exists() or not healthy(source, MIN_SECONDS - 2):
                print(f"Downloading {pick['title']}", flush=True)
                if not fetch(client, pick["url"], source) or not healthy(source, MIN_SECONDS - 2):
                    source.unlink(missing_ok=True)
                    continue
            credit = f"“{pick['title']}” by {pick['author']} · {pick['license']} · via Wikimedia Commons"
            description = pick["description"] or pick["title"]
            items.append(dict(
                ref=f"{PREFIX}wm_{digest}", beat=pick["beat"], source=source, start=0,
                seconds=min(pick["seconds"], MAX_SECONDS), title=pick["title"], tags=pick["tags"],
                description=f"{description}\n\n{credit}.", credit=credit, source_url=pick["page_url"],
                license=pick["license"], license_url=pick["license_url"]))
    return items


async def main(do_reset: bool, limit: int) -> None:
    c = await build_container(settings)
    now = dt.datetime.now(dt.UTC)
    root = media_root_path(settings) / "open_long"
    root.mkdir(parents=True, exist_ok=True)
    try:
        if do_reset:
            print(f"Removed {await reset(c)} seeded rows.")
        members = []
        for i in range(100):
            person = await c.identity_repository.get_by_id(f"demo_{i:03}")
            if person and person.is_test_user:
                members.append(person.id)
        creators = [uid for uid in members if int(uid[-3:]) < 20]
        if len(creators) < 5:
            raise SystemExit("Seed the community accounts first (Start-GraphDemo.ps1 -Seed).")
        # One creator per beat, so each uploader has a recognisable channel.
        channel = {beat: creators[(i * 7 + 3) % len(creators)] for i, beat in enumerate(BEATS)}
        items = film_items() + commons_items(limit, Path("data/open_long"))
        fingerprints, manifest, made = [], [], 0
        totals = dict(viewed=0, liked=0, saved=0, shared=0, reposted=0)
        for n, item in enumerate(items, 1):
            print(f"[{n}/{len(items)}] {item['title']}", flush=True)
            creator = channel.get(item["beat"], creators[0])
            counts = await publish(c, item, creator, members, fingerprints, root, now)
            if counts is None:
                continue
            for verb, value in counts.items():
                totals[verb] += value
            manifest.append(dict(id=item["ref"], title=item["title"], creator=creator, tags=item["tags"],
                                 credit=item["credit"], license=item["license"], source=item["source_url"]))
            made += 1
        (root / "videos.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"{made} long videos ready. New activity: {totals}", flush=True)
        print("Next: uv run python -m scripts.seed_community_comments  (comment threads)", flush=True)
    finally:
        await c.cache.close()
        if getattr(c.graph.store, "db", None):
            await c.graph.store.db.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--reset", action="store_true", help="remove these videos and their activity first")
    parser.add_argument("--max", type=int, default=30, help="Wikimedia Commons videos to add (on top of 9 film chapters)")
    args = parser.parse_args()
    asyncio.run(main(args.reset, args.max))
