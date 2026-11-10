"""Sixty more Social clips cut from Blender Foundation open movies, with natural engagement.

Films (all Creative Commons BY, credited on every clip):
  * Sintel (2010) - 20 clips          * Big Buck Bunny (2008) - 20 clips
  * Elephants Dream (2006) - 10 clips  * Tears of Steel (2012) - 10 new moments

Each clip is a vertical 540x960 cut of 12-30 s, posted by one of the community
creators (demo_000-019) at a time spread over the last five weeks. Engagement
comes from the community accounts only (nothing is copied from other sites):
views, likes, saves, shares and reposts follow a per-clip popularity curve, so a
few clips take off and most get modest numbers, and the activity happens after
the clip was posted. Comments come from seed_community_comments (run it after
this script; Start-GraphDemo.ps1 -Seed does both).

The full films are downloaded once to data/open_movies/ (kept out of media/, so
they are not published to R2). Clips land in media/open_movies/.

Idempotent: rerunning skips finished clips and existing activity.
Run: uv run python -m scripts.import_open_movie_clips [--reset]
"""
import argparse
import asyncio
import datetime as dt
import hashlib
import json
import random
import subprocess
import uuid
from pathlib import Path

import httpx

from app.core.container import build_container, media_root_path
from app.domains.graph.service import key
from scripts.run_graph_demo import settings
from app.infrastructure.video_thumbnail import make_thumbnail

SEED = "open-movies-v1"
SOURCE_DIR = Path("data/open_movies")

FILMS = [
    dict(slug="sintel", title="Sintel", count=20, start=45, end=760, year=2010,
         urls=["https://download.blender.org/demo/movies/Sintel.2010.720p.mkv",
               "http://ftp.nluug.nl/pub/graphics/blender/demo/movies/Sintel.2010.720p.mkv",
               "http://ftp.halifax.rwth-aachen.de/blender/demo/movies/Sintel.2010.720p.mkv",
               # Original render (MP4): different encode, so a bad copy of the MKV doesn't block us.
               "http://mirrorblender.top-ix.org/movies/sintel-1280-surround.mp4",
               "http://peach.themazzone.com/durian/movies/sintel-1280-surround.mp4"],
         min_minutes=13,
         license="CC BY 3.0", license_url="https://creativecommons.org/licenses/by/3.0/",
         credit="Sintel — (c) copyright Blender Foundation | durian.blender.org · CC BY 3.0",
         tags=["sintel", "animation", "openmovie", "blender"],
         captions=["the dragon chase in Sintel still gives me chills 🐉", "Sintel's rooftop scene, pure atmosphere",
                   "this snow sequence is a whole mood ❄️", "nobody talks about the lighting in Sintel enough",
                   "Scales the baby dragon 🥹", "the market scene, so much detail in the background",
                   "that moment when she finds the cave", "Sintel's fight choreography goes hard",
                   "rewatching Sintel and this cut hits different", "the score in this part 🎻",
                   "frame by frame this film is a painting", "the shaman scene is so underrated",
                   "Sintel walking through the storm 🌪️", "animation study: Sintel's hair sim",
                   "this transition is so clean", "the bamboo forest sequence 🎋",
                   "Sintel's ending wrecked me ngl", "the colour palette in this shot",
                   "made in Blender, free to watch, still elite", "15 seconds of Sintel to fix your day"]),
    dict(slug="bbb", title="Big Buck Bunny", count=20, start=30, end=540, year=2008,
         urls=["https://download.blender.org/peach/bigbuckbunny_movies/big_buck_bunny_720p_h264.mov",
               "http://ftp.nluug.nl/pub/graphics/blender/demo/movies/BBB/big_buck_bunny_720p_h264.mov",
               "https://archive.org/download/BigBuckBunny_124/Content/big_buck_bunny_720p_surround.mp4"],
         license="CC BY 3.0", license_url="https://creativecommons.org/licenses/by/3.0/",
         credit="Big Buck Bunny — (c) copyright 2008, Blender Foundation | www.bigbuckbunny.org · CC BY 3.0",
         tags=["bigbuckbunny", "animation", "openmovie", "blender"],
         captions=["Big Buck Bunny waking up is literally me on Mondays 🐰", "the butterfly scene 🦋 so wholesome",
                   "these three troublemakers 😂", "Bunny's revenge arc starts here",
                   "the fur rendering in 2008?? insane", "comfort cartoon unlocked",
                   "the squirrel's face in this part 😭", "Big Buck Bunny traps, engineering level 100",
                   "this forest looks so soft", "the timing on this gag is perfect",
                   "showed this to my little cousin and she lost it", "peak open-source animation",
                   "the flying squirrel bit 🐿️", "Bunny smelling the flower 🌸",
                   "this apple moment lol", "the colours in this film are so warm",
                   "plotting the trap, every frame is a joke", "the chinchilla deserved better",
                   "Big Buck Bunny never gets old", "best 10 minutes on the internet"]),
    dict(slug="elephants", title="Elephants Dream", count=10, start=40, end=590, year=2006,
         urls=["https://archive.org/download/ElephantsDream/ed_hd.mp4",
               "https://download.blender.org/ED/elephantsdream-720-h264-st-aac.mov"],
         license="CC BY 2.5", license_url="https://creativecommons.org/licenses/by/2.5/",
         credit="Elephants Dream — (c) copyright 2006, Blender Foundation / Netherlands Media Art Institute | elephantsdream.org · CC BY 2.5",
         tags=["elephantsdream", "animation", "openmovie", "blender"],
         captions=["Elephants Dream is so surreal, the first open movie ever 🐘", "this machine world is wild",
                   "the cable room scene 🔌", "Proog and Emo, the original duo",
                   "2006 and they made this with open tools", "the audio design in this part is creepy good",
                   "the telephone sequence 📞", "this film feels like a fever dream (complimentary)",
                   "the bird scene, still beautiful", "every frame looks like concept art"]),
    dict(slug="tears", title="Tears of Steel", count=10, start=60, end=650, year=2012,
         urls=["https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov"],
         license="CC BY 3.0", license_url="https://creativecommons.org/licenses/by/3.0/",
         credit="Tears of Steel — (CC) Blender Foundation | mango.blender.org · CC BY 3.0",
         tags=["tearsofsteel", "scifi", "openmovie", "blender"],
         captions=["Tears of Steel, the bridge scene 🌉", "the robots in this one 🤖",
                   "Amsterdam but make it sci-fi", "this VFX shot is so clean",
                   "the dome fight sequence", "Celia and Thom, the breakup that started a war",
                   "the practical sets + CG blend here", "Tears of Steel's colour grade is everything",
                   "this shot is my wallpaper now", "open-source VFX hitting hard"]),
]


def healthy(path, min_seconds):
    """A source/clip ffprobe can read, with video, at least `min_seconds` long."""
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_type",
                              "-of", "json", str(path)], capture_output=True, text=True, check=True, timeout=60)
        data = json.loads(out.stdout)
        return (any(s.get("codec_type") == "video" for s in data.get("streams", []))
                and float(data["format"]["duration"]) >= min_seconds)
    except (subprocess.SubprocessError, ValueError, KeyError, OSError):
        return False


def readable_to_the_end(path, minimum):
    """A truncated download keeps its full duration in the header, so decode
    one frame near the end to be sure the whole file is there."""
    import tempfile
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(path)],
                             capture_output=True, text=True, check=True, timeout=60)
        position = max(minimum * 0.9, float(json.loads(out.stdout)["format"]["duration"]) * 0.92)
        with tempfile.TemporaryDirectory() as tmp:
            frame = Path(tmp) / "end.jpg"
            subprocess.run(["ffmpeg", "-nostdin", "-v", "fatal", "-y", "-ss", f"{position:.1f}", "-i", str(path),
                            "-frames:v", "1", "-an", str(frame)], check=True, timeout=120)
            return frame.exists() and frame.stat().st_size > 1000
    except (subprocess.SubprocessError, ValueError, KeyError, OSError):
        return False


def download(film):
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    minimum = film.get("min_minutes", 5) * 60
    for p in sorted(SOURCE_DIR.glob(film["slug"] + "-source.*")):
        if p.suffix == ".part":
            continue
        if healthy(p, minimum) and readable_to_the_end(p, minimum):
            return p
        print(f"  {p.name} is damaged or incomplete; downloading it again", flush=True)
        p.unlink(missing_ok=True)
    # Tears of Steel was already fetched by import_licensed_social.
    if film["slug"] == "tears":
        old = media_root_path(settings) / "licensed_social" / "tears-of-steel-source.mov"
        if old.exists():
            return old
    for url in film["urls"]:
        target = SOURCE_DIR / (film["slug"] + "-source" + Path(url).suffix)
        partial = target.with_suffix(".part")
        print(f"Downloading {film['title']} from {url}", flush=True)
        try:
            with httpx.Client(timeout=120, follow_redirects=True) as client, client.stream("GET", url) as response:
                response.raise_for_status()
                with partial.open("wb") as out:
                    for chunk in response.iter_bytes(1024 * 1024):
                        out.write(chunk)
            partial.replace(target)
            if healthy(target, minimum) and readable_to_the_end(target, minimum):
                return target
            print(f"  {url} gave a damaged or incomplete file; trying the next mirror", flush=True)
            target.unlink(missing_ok=True)
        except (httpx.HTTPError, OSError) as exc:
            print(f"  failed ({exc}); trying the next mirror", flush=True)
            partial.unlink(missing_ok=True)
    print(f"Skipping {film['title']}: no mirror could be downloaded.", flush=True)
    return None


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(path)],
                         capture_output=True, text=True, check=True, timeout=30)
    return float(json.loads(out.stdout)["format"]["duration"])


def cut(source, target, start, seconds):
    """Centre crop to 9:16 at 960 tall. Tolerates damaged audio packets (some
    mirrors' AC-3 tracks have them): decode errors are skipped, and if the
    clip still comes out broken it is cut again without sound. Returns
    whether a playable clip was written."""
    vf = "scale=-2:960,crop=540:960"
    base = ["ffmpeg", "-nostdin", "-v", "fatal", "-y", "-err_detect", "ignore_err", "-ss", f"{start:.2f}",
            "-i", str(source), "-t", str(seconds), "-vf", vf, "-r", "30", "-c:v", "libx264",
            "-preset", "veryfast", "-crf", "24", "-pix_fmt", "yuv420p"]
    for audio in (["-c:a", "aac", "-b:a", "128k", "-ac", "2"], ["-an"]):
        try:
            subprocess.run(base + audio + ["-movflags", "+faststart", str(target)], check=True, timeout=300)
        except (subprocess.SubprocessError, OSError):
            pass
        if healthy(target, seconds - 1.5):
            return True
        target.unlink(missing_ok=True)
    return False


async def engage(c, obj, posted, members, rng, now):
    """Views, likes, saves, shares and reposts from community members."""
    # Popularity: most clips modest, a handful break out.
    heat = min(1.0, rng.lognormvariate(-1.0, 0.6))
    viewers = rng.sample(members, max(12, int(len(members) * (0.25 + 0.7 * heat))))
    span = max(3600.0, (now - posted).total_seconds() - 600)
    counts = dict(viewed=0, liked=0, saved=0, shared=0, reposted=0)
    for uid in viewers:
        # Most views land in the first two days, then a long tail.
        when = posted + dt.timedelta(seconds=min(span, rng.expovariate(1 / 50000) + 60))
        verbs = ["viewed"]
        roll = rng.random()
        if roll < 0.22 + 0.45 * heat:
            verbs.append("liked")
        if rng.random() < 0.04 + 0.1 * heat:
            verbs.append("saved")
        if rng.random() < 0.03 + 0.08 * heat:
            verbs.append("shared")
        if rng.random() < 0.01 + 0.04 * heat:
            verbs.append("reposted")
        for verb in verbs:
            aid = key("activity", uid, obj["id"], verb)
            if await c.graph.store.get(aid):
                continue
            policy = await c.graph.policy(uid, obj, verb)
            moment = when + dt.timedelta(seconds=rng.randint(5, 40) if verb != "viewed" else 0)
            await c.graph.store.put(aid, {
                "in": "user:" + uid, "out": obj["id"], "verb": verb, "created_at": moment.isoformat(),
                "visibility_class": policy["audience"] + "_" + policy["identity_mode"]})
            if verb == "shared":
                for _ in range(rng.choice([1, 1, 1, 2])):  # some people share twice
                    await c.graph.store.put("share_event:" + uuid.uuid4().hex,
                                            dict(object_id=obj["id"], user_id=uid,
                                                 created_at=moment.isoformat(), seed=SEED))
            counts[verb] += 1
    return counts


async def reset(c):
    # `activity` is a SCHEMAFULL relation table (no extra fields), so seeded
    # rows are found by their clip object rather than a seed marker.
    removed = 0
    rows = c.social_video_service.db.execute("SELECT id FROM videos WHERE id LIKE 'open_clip_%'").fetchall()
    clips = {key("phlio_object", "social", row["id"]) for row in rows}
    for row in await c.graph.store.rows("activity"):
        if str(row.get("out")) in clips:
            await c.graph.store.delete(row["id"])
            removed += 1
    for row in await c.graph.store.rows("share_event", {"seed": SEED}):
        await c.graph.store.delete(row["id"])
        removed += 1
    for row in rows:
        for table in ("phlio_object", "platform_content"):
            await c.graph.store.delete(key(table, "social", row["id"]))
    c.social_video_service.db.execute("DELETE FROM videos WHERE id LIKE 'open_clip_%'")
    c.social_video_service.db.commit()
    return removed + len(rows)


async def main(do_reset=False):
    c = await build_container(settings)
    now = dt.datetime.now(dt.UTC)
    root = media_root_path(settings) / "open_movies"
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
        fingerprints, manifest, made = [], [], 0
        totals = dict(viewed=0, liked=0, saved=0, shared=0, reposted=0)
        for film in FILMS:
            source = download(film)
            if source is None:
                continue
            length = probe(source)
            end = min(film["end"], length - 40)
            for n in range(film["count"]):
                ref = f"open_clip_{film['slug']}_{n:02}"
                rng = random.Random(hashlib.sha256((SEED + ref).encode()).hexdigest())
                seconds = rng.randint(12, 30)
                slot = (end - film["start"]) / film["count"]
                start = film["start"] + slot * n + rng.uniform(0, max(1, slot - seconds))
                name = f"{film['slug']}-{n:02}"
                target, cover = root / f"{name}.mp4", root / f"{name}-cover.jpg"
                print(f"{film['title']} {n + 1}/{film['count']}", flush=True)
                # Re-cut clips a failed earlier run left broken.
                if target.exists() and not healthy(target, seconds - 1.5):
                    target.unlink()
                    cover.unlink(missing_ok=True)
                if not target.exists() and not cut(source, target, start, seconds):
                    print(f"  skipped {name}: could not cut a playable clip", flush=True)
                    continue
                if not cover.exists():
                    try:
                        make_thumbnail(target, cover, seconds, fingerprints, offset=rng.randint(2, 9))
                    except ValueError:  # every bright frame looks like an earlier cover; allow a repeat
                        try:
                            make_thumbnail(target, cover, seconds, None, offset=rng.randint(2, 9))
                        except (ValueError, subprocess.SubprocessError):
                            pass
                    except subprocess.SubprocessError:
                        pass
                if not cover.exists():
                    print(f"  skipped {name}: no usable cover frame", flush=True)
                    continue
                creator = creators[int(hashlib.sha256((ref + "owner").encode()).hexdigest(), 16) % len(creators)]
                caption = film["captions"][n % len(film["captions"])]
                posted = now - dt.timedelta(days=rng.uniform(0.5, 35), minutes=rng.randint(0, 600))
                url, thumb = f"/media/open_movies/{target.name}", f"/media/open_movies/{cover.name}"
                db = c.social_video_service.db
                if not db.execute("SELECT id FROM videos WHERE id=?", (ref,)).fetchone():
                    c.social_video_service.publish(ref, creator, caption, url, kind="clip", duration_seconds=seconds)
                    db.execute("UPDATE videos SET created_at=? WHERE id=?", (posted.isoformat(), ref))
                else:
                    posted = dt.datetime.fromisoformat(
                        db.execute("SELECT created_at FROM videos WHERE id=?", (ref,)).fetchone()["created_at"])
                db.execute("UPDATE videos SET thumbnail_url=?, url=?, duration_seconds=? WHERE id=?",
                           (thumb, url, seconds, ref))
                db.commit()
                obj = await c.graph.register_object(creator, "social.clip", ref, caption)
                if obj.get("created_at") != posted.isoformat():
                    obj["created_at"] = posted.isoformat()
                    obj = await c.graph.store.put(obj["id"], obj)
                tags = film["tags"] + rng.sample(["fyp", "cinema", "animation", "vfx", "shortfilm", "cgi",
                                                  "creativecommons", "filmclips", "art"], 2)
                description = f"{caption}\n\nFrom {film['title']} ({film['year']}). {film['credit']}. Trimmed and reframed vertically."
                await c.graph.store.put(key("platform_content", "social", ref), dict(
                    platform="social", domain_ref=ref, object_id=obj["id"], kind="clip",
                    description=description, image_url=thumb, media_url=url, tags=list(dict.fromkeys(tags)),
                    attribution=film["credit"], source_url=film["urls"][0], license=film["license"],
                    license_url=film["license_url"], film=film["title"], visibility="public", seed=SEED))
                counts = await engage(c, obj, posted, [m for m in members if m != creator], rng, now)
                for verb, value in counts.items():
                    totals[verb] += value
                manifest.append(dict(id=ref, film=film["title"], start=round(start, 2), seconds=seconds,
                                     creator=creator, caption=caption, file=target.name))
                made += 1
        (root / "clips.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
        (root / "LICENSE.json").write_text(json.dumps(
            {f["title"]: dict(credit=f["credit"], license=f["license"], url=f["license_url"]) for f in FILMS},
            indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"{made} open-movie clips ready. New activity: {totals}", flush=True)
        print("Next: uv run python -m scripts.seed_community_comments  (adds comment threads)", flush=True)
    finally:
        await c.cache.close()
        if getattr(c.graph.store, "db", None):
            await c.graph.store.db.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--reset", action="store_true", help="remove the clips and their activity first")
    asyncio.run(main(parser.parse_args().reset))
