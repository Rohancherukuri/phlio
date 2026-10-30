"""Believable comment threads across Social, Shop, Book, Stream and News.

Every public object gets a deterministic set of comments written by the
seeded community accounts (run ``scripts.humanize_demo_accounts`` first so
they have real-looking names). Threads include questions the creator answers,
people replying to and @mentioning each other, Foxy stickers, GIPHY reactions,
photos (product shots, venue photos, film stills) and short GIFs cut from the
licensed Tears of Steel clips. Comments get likes from other members.

Rules that keep it authentic:
* The account that posted something only replies on its own Social posts,
  videos and clips; catalog listings (Shop, Book, Stream, News) are discussed
  by members only.
* Content owned by a real (non-seeded) account is commented on, but nobody
  ever writes as a real account.
* Times fall after the content was published and before now.

Idempotent per object; ``--reset`` removes this seed's comments first.
"""

import argparse
import asyncio
import datetime as dt
import hashlib
import random
import subprocess

from app.core.container import build_container, media_root_path
from app.domains.graph.service import key
from scripts.run_graph_demo import settings

SEED = "community-v1"
PLATFORMS = {"social", "shop", "book", "stream", "news"}
CATALOG_CAP = 60  # objects per non-Social platform

GIFS = {  # GIPHY ids, rendered via the app's GIPHY lookup
    "mindblown": ["3OSo3PPaXdw0U", "1L5YuA6wpKkNO", "OK27wINdQS5YQ", "3XR0chfiSTtAI", "75ZaxapnyMp2w"],
    "clap": ["9uoYC7cjcU6w8", "l9Tllo1thElT5gvVOU", "rP1fif3VHKIIZA3UhF"],
    "wow": ["dnMwfGJPdsqYEbmrD5", "oYtVHSxngR3lC", "fpXxIjftmkk9y", "5VKbvrjxpVJCM"],
    "money": ["3oKIPa2TdahY8LAAxy", "yC5yXN0r1tQvP47gmV", "mHcEcam5FtKQE", "6jwZT8O6t8M8ZG1l65"],
    "vibe": ["Q9AxXRnlwz1DwcQDWF", "WOT9tRmLbjw7M6m2R1", "4oMoIbIQrvCjm", "8m4R4pvViWtRzbloJ1"],
    "yum": ["12uXi1GXBibALC", "XDchDU77dNigejOCBl", "gglO1iZFT76UAYDAiR"],
    "laugh": ["BFYLNwlsSNtcc", "lszAB3TzFtRaU", "ZqlvCTNHpqrio", "26n6Gx9moCgs1pUuk"],
    "excited": ["11sBLVxNs7v6WA", "xUPJPB7DuFNoa8mqqY", "MJs7EYwHyG8XC", "tsX3YMWYzDPjAARfeg"],
}

BANKS = {
    "film": dict(
        size=(5, 10),
        comments=[
            "The way the light hits the robot arm here 😮‍💨",
            "Tears of Steel still holds up so well. The Blender team was cooking",
            "That old Amsterdam setting gets me every time",
            "ok the colour grade in this one is unreal",
            "Rewatched this three times just for the compositing",
            "Who else paused to look at all the background details?",
            "the practical set + CG blend is so clean here",
            "This is literally the scene I used for my VFX class assignment lol",
            "Need a full breakdown of how they tracked this shot",
            "the sound design in this part >>>",
            "Saving this as a framing reference 🔖",
            "How long did this edit take you? The pacing is 🔥",
            "Didn't know this whole film was made with open-source tools. Wild.",
            "watching this at 2am and the atmosphere hits different",
            "This would look insane in 4K",
            "the mech design though 🤖🔥",
            "Lowkey better VFX than some big-budget movies",
            "Do the dome scene next pls!",
            "Shared this with my film club, we're doing a whole session on it",
            "The vertical crop actually works really well for this moment",
            "Every frame of this could be a wallpaper",
            "Came for the sci-fi, stayed for the cinematography",
        ],
        questions=[
            ("What do you edit on?", ["DaVinci Resolve for the grade, cuts in Premiere 🙌",
                                      "Resolve for everything now, the free version is plenty"],
             ["pretty sure it's Resolve, they mentioned it in an older post"]),
            ("Is the full film available somewhere?", ["Yes! It's free on the Blender Foundation site, CC BY licensed 🎬",
                                                       "It's on the Blender Foundation site and YouTube, totally free"],
             ["It's free on the Blender Foundation site 🎬", "Yep, it's on YouTube, the whole thing is free"]),
            ("Can you do a breakdown of the green screen shots next?", ["On it, part 2 drops this weekend 👀",
                                                                        "Noted! That's next on my list"],
             ["+1 would watch that", "yes pls, I need this too"]),
            ("Around what minute is this in the film?", ["This is from the first half, right before the bridge sequence",
                                                         "About 5 minutes in, just after the intro"],
             ["around the 5 minute mark I think", "first half, before the bridge scene"]),
            ("How do you make the vertical crop look this good?", ["Manual subject tracking + a bit of reframing in post. Takes forever 😅",
                                                                   "Keyframing the crop by hand, no shortcuts sadly"],
             ["they said it's tracked by hand, insane patience"]),
        ],
        replies=["Facts", "Literally came here to say this", "This!!", "same 😭", "hard agree",
                 "Agreed, the second half is even better", "you should check out Sintel too, same team",
                 "true lol", "right?? I noticed that too", "bro yes 🔥"],
        owner=["Thank you so much! 🙏", "Means a lot, more coming soon", "haha right?? 😂",
               "Glad you noticed that!", "Appreciate you watching ❤️", "That's my favourite part too"],
        gifs=["mindblown", "wow", "clap"],
        stickers=["surprised", "excited", "happy", "thinking"],
        media="film",
    ),
    "social": dict(
        size=(2, 6),
        comments=["This is so good 🔥", "Love this!", "Need more of this content", "The quality on this 😍",
                  "Okay this made my day", "underrated post fr", "Following for more",
                  "Can't stop looking at this", "This deserves way more reach", "Obsessed with this ✨",
                  "Saving this for later 🔖", "Such a vibe"],
        questions=[("Where was this?", ["Will share the details soon!", "Somewhere special 😉 more coming"],
                    ["I was wondering the same!"]),
                   ("How did you make this?", ["Took a lot of trial and error haha", "Happy to share a breakdown soon"],
                    ["following for the answer 👀"])],
        replies=["Same thought!", "100%", "agreed 🙌", "fr", "this!!"],
        owner=["Thank you!! 🙏", "Appreciate it ❤️", "More coming soon!", "haha thanks"],
        gifs=["clap", "wow", "excited"],
        stickers=["happy", "excited", "hello"],
        media=None,
    ),
    "shop": dict(
        size=(2, 6),
        comments=["Got this last week, quality is way better than I expected",
                  "Delivered in 2 days 🙌", "Bit pricey but honestly worth it",
                  "Bought one for my sister's birthday, she loved it", "Waiting for the sale 👀",
                  "Using it daily for a month now, no complaints", "Packaging was super neat too",
                  "Adding to cart before it sells out again", "Second time ordering this. Says enough.",
                  "Looks even better in person", "Exactly what I was looking for"],
        questions=[("Does this come in other colours?", ["I saw a couple of other options on the store page",
                                                         "There was a darker variant last month, check again"]),
                   ("Is cash on delivery available?", ["yes, I paid on delivery", "COD worked for me in Pune"]),
                   ("How's the build quality?", ["Solid, feels premium honestly", "Better than the photos tbh"]),
                   ("How long did delivery take?", ["Took 3 days for me in Bengaluru", "Next day in Mumbai!"])],
        replies=["Same experience here", "agree, totally worth it", "good to know!", "ordering now 😅", "+1"],
        photo_lines=["Mine arrived today! Looks exactly like the pictures", "Unboxed it last night 😍",
                     "Here's mine after a week of use"],
        gifs=["money", "wow", "excited"],
        stickers=["happy", "excited", "thinking"],
        media="product",
    ),
    "book": dict(
        size=(2, 5),
        comments=["Went last Saturday, totally worth it!", "The vibe here is unmatched ✨",
                  "Took my parents, they loved it", "Tickets sold out so fast last time 😭",
                  "Go early, it gets crowded by evening", "Totally recommend the evening slot",
                  "One of the best weekends I've had in a while", "Booking again next month for sure"],
        questions=[("Anyone going this weekend?", ["I'm going Sunday!", "Saturday evening, see you there 🙌"]),
                   ("Is there parking nearby?", ["there's paid parking right next door", "Parking fills up fast, take a cab"]),
                   ("Is it kid friendly?", ["Took my 6 year old, she had a blast", "Yes! Lots of families there"])],
        replies=["Same here!", "+1", "Agreed!", "need to go soon", "adding this to my list"],
        photo_lines=["Was here last weekend 📸", "Sharing a pic from my visit"],
        gifs=["excited", "wow"],
        stickers=["excited", "happy", "hello"],
        media="listing",
    ),
    "book_food": dict(
        size=(3, 6),
        comments=["The food here 🤤", "Try the dessert, thank me later",
                  "Came for dinner, stayed for three hours", "Service was quick even on a Friday night",
                  "Their coffee is so good ☕", "Portions are huge, go hungry",
                  "Booked a table for our anniversary, perfect evening"],
        questions=[("Do they take reservations?", ["Yes, book here a day earlier on weekends", "Walk-ins wait ~30 mins on weekends"]),
                   ("Any veg options?", ["Plenty! The paneer starter is amazing", "Loads, half the menu is veg"])],
        replies=["Agreed!", "adding to my list", "omg yes", "need to go back"],
        photo_lines=["What we ordered last night 😍", "Dessert was a 10/10"],
        gifs=["yum", "excited"],
        stickers=["happy", "coffee", "excited"],
        media="listing",
    ),
    "stream_music": dict(
        size=(3, 7),
        comments=["This has been on repeat all week 🎧", "The bridge in this one 😮‍💨",
                  "Perfect for late-night drives", "Added to my playlist instantly",
                  "this beat is so underrated", "Found this on a random playlist and now I'm hooked",
                  "Volume all the way up for this one", "Study playlist essential"],
        questions=[("Anyone know similar songs?", ["Check out the 'Late Night' playlist here", "The artist's older album is just as good"])],
        replies=["same!!", "facts", "so good", "on repeat here too"],
        gifs=["vibe", "excited"],
        stickers=["happy", "excited", "sleepy"],
        media=None,
    ),
    "stream_watch": dict(
        size=(3, 7),
        comments=["The ending had me speechless", "Binged the whole thing in one night",
                  "That twist in the middle 😳", "The cinematography is gorgeous",
                  "Watched it with family, everyone loved it", "Rewatching this for the third time",
                  "The soundtrack carries so many scenes", "Underrated gem honestly"],
        questions=[("Worth watching?", ["100%, the second half is the best part", "Yes, just give it 20 minutes"]),
                   ("Is there a sequel?", ["Not yet, but there are rumours", "Not that I know of 😭"])],
        replies=["agreed", "same reaction 😂", "this!!", "so true"],
        gifs=["wow", "mindblown", "laugh"],
        stickers=["surprised", "excited", "sad"],
        media=None,
    ),
    "news": dict(
        size=(2, 5),
        comments=["Interesting read, I'd love to see the data behind this",
                  "Finally someone is talking about this", "Glad this is getting coverage",
                  "Not sure I agree with the conclusion here", "Sharing this with my team",
                  "Great explainer, very clear", "This changes things for a lot of people"],
        questions=[("What's the source for the numbers?", ["they linked the report at the end", "It's in the last paragraph"])],
        replies=["fair point", "agreed", "same thought", "good question"],
        gifs=["mindblown", "clap"],
        stickers=["thinking", "surprised"],
        media=None,
    ),
}


def category(obj):
    platform, _, sub = obj["object_type"].partition(".")
    if platform == "social":
        title = (obj.get("title") or "").lower()
        return "film" if "tears of steel" in title or "film study" in title else "social"
    if platform == "book":
        return "book_food" if sub == "restaurant" else "book"
    if platform == "stream":
        return "stream_music" if sub in {"track", "creator"} else "stream_watch"
    return platform


def parse_time(value, fallback):
    try:
        moment = dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return moment if moment.tzinfo else moment.replace(tzinfo=dt.UTC)
    except (TypeError, ValueError):
        return fallback


def make_scene_gifs(media_root):
    """Short reaction GIFs cut from the licensed clips (needs ffmpeg)."""
    source_dir = media_root / "licensed_social"
    out = media_root / "social_comments"
    out.mkdir(parents=True, exist_ok=True)
    gifs = []
    for i in range(20):
        clip = source_dir / f"tears-clip-{i:02}.mp4"
        target = out / f"scene-reaction-{i:02}.gif"
        if not target.exists() and clip.exists():
            try:
                subprocess.run(
                    ["ffmpeg", "-nostdin", "-v", "error", "-y", "-ss", "8", "-t", "2.6", "-i", str(clip),
                     "-vf", "fps=12,scale=240:-2:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse",
                     "-loop", "0", str(target)], check=True, timeout=60)
            except (OSError, subprocess.SubprocessError):
                target.unlink(missing_ok=True)
        if target.exists():
            gifs.append("/media/social_comments/" + target.name)
    return gifs


async def reset(c):
    removed = 0
    for row in await c.graph.store.rows("content_comment", {"seed": SEED}):
        for reaction in await c.graph.store.rows("comment_reaction", {"comment_id": row["id"]}):
            await c.graph.store.delete(reaction["id"])
        await c.graph.store.delete(row["id"])
        removed += 1
    return removed


async def remove_old_placeholder_comments(c):
    """The first seed wrote four near-identical remarks under every video."""
    removed = 0
    for index in range(20):
        for kind in ("video", "clip"):
            for n in range(4):
                cid = key("content_comment", "licensed-demo-v1", f"demo_{kind}_{index:02}", str(n))
                if await c.graph.store.get(cid):
                    for reaction in await c.graph.store.rows("comment_reaction", {"comment_id": cid}):
                        await c.graph.store.delete(reaction["id"])
                    await c.graph.store.delete(cid)
                    removed += 1
    return removed


async def main(do_reset=False):
    c = await build_container(settings)
    now = dt.datetime.now(dt.UTC)
    try:
        if do_reset:
            print(f"Removed {await reset(c)} seeded comments.")
        print(f"Removed {await remove_old_placeholder_comments(c)} placeholder comments.")
        members = {}
        for i in range(100):
            person = await c.identity_repository.get_by_id(f"demo_{i:03}")
            if person and person.is_test_user:
                members[person.id] = c.graph.profile(person)
        if len(members) < 10:
            raise SystemExit("Seed the community accounts first (Start-GraphDemo.ps1 -Seed).")
        member_ids = sorted(members)
        creators = [uid for uid in member_ids if int(uid[-3:]) < 20]
        scene_gifs = make_scene_gifs(media_root_path(c.settings))
        stills = [f"/media/licensed_social/tears-clip-{i:02}.jpg" for i in range(20)]

        objects = [o for o in await c.graph.store.rows("phlio_object")
                   if o.get("platform") in PLATFORMS and o.get("audience") == "public"
                   and o.get("state", "active") == "active"]
        chosen = []
        for platform in sorted(PLATFORMS):
            rows = sorted((o for o in objects if o["platform"] == platform),
                          key=lambda o: hashlib.sha256(o["id"].encode()).hexdigest())
            chosen += rows if platform == "social" else rows[:CATALOG_CAP]

        written = likes = threads = 0
        for obj in chosen:
            marker = key("content_comment", SEED, obj["id"], "0")
            if await c.graph.store.get(marker):
                continue
            rng = random.Random(hashlib.sha256((SEED + obj["id"]).encode()).hexdigest())
            bank = BANKS[category(obj)]
            owner = obj.get("owner")
            owner_is_member = owner in members
            owner_replies = obj["platform"] == "social" and owner_is_member
            published = parse_time(obj.get("created_at"), now - dt.timedelta(days=rng.randint(3, 30)))
            start = max(min(published, now - dt.timedelta(hours=6)), now - dt.timedelta(days=60))
            span = (now - start).total_seconds()
            pool = [uid for uid in member_ids if uid != owner]
            # Creators show up in each other's Social comments more often.
            weights = [3 if (obj["platform"] == "social" and uid in creators) else 1 for uid in pool]
            detail = await c.graph.store.get(key("platform_content", obj["platform"], obj["domain_ref"])) or {}
            picture = detail.get("image_url")
            count = rng.randint(*bank["size"])
            if category(obj) == "social" and not owner_is_member:
                count = rng.randint(2, 4)  # a real person's post: a handful of friendly comments
            texts = rng.sample(bank["comments"], min(count, len(bank["comments"])))
            questions = list(bank["questions"])
            rng.shuffle(questions)
            authors = []
            n = 0

            async def put(text, author, when, parent=None, sticker=None, image=None, mention=None):
                nonlocal n, written, likes
                cid = key("content_comment", SEED, obj["id"], str(n))
                n += 1
                mentions = []
                if mention:
                    text = f"@{mention['username']} {text}"
                    mentions = [mention]
                await c.graph.store.put(cid, dict(
                    parent_id=parent, object_id=obj["id"], author_id=author, text=text,
                    sticker_id=sticker, image_url=image, mentions=mentions,
                    created_at=when.isoformat(), seed=SEED))
                written += 1
                hearts = rng.choices([0, rng.randint(1, 3), rng.randint(4, 9), rng.randint(10, 25)],
                                     weights=[35, 42, 18, 5] if parent is None else [60, 33, 7, 0])[0]
                fans = [uid for uid in member_ids if uid != author]
                for fan in rng.sample(fans, min(hearts, len(fans))):
                    await c.graph.store.put(key("comment_reaction", fan, cid),
                                            dict(user_id=fan, comment_id=cid, seed=SEED))
                    likes += 1
                return cid

            def when_top():
                return start + dt.timedelta(seconds=span * rng.random() ** 2.2 + 120)

            def when_reply(parent_time):
                room = max(60.0, (now - parent_time).total_seconds() - 60)
                return parent_time + dt.timedelta(seconds=min(room, rng.uniform(180, 2 * 86400)))

            plan = []
            for text in texts:
                plan.append(("text", text))
            if questions and rng.random() < 0.85:
                plan.insert(rng.randrange(len(plan) + 1), ("question", questions[0]))
            if len(questions) > 1 and count >= 6 and rng.random() < 0.5:
                plan.insert(rng.randrange(len(plan) + 1), ("question", questions[1]))
            if rng.random() < 0.35:
                plan.insert(rng.randrange(len(plan) + 1), ("gif", rng.choice(bank["gifs"])))
            if rng.random() < 0.3:
                plan.insert(rng.randrange(len(plan) + 1), ("sticker", rng.choice(bank["stickers"])))
            media = bank["media"]
            if media and rng.random() < (0.45 if media == "film" else 0.35):
                plan.insert(rng.randrange(len(plan) + 1), ("photo", None))

            for kind, value in plan:
                author = rng.choices(pool, weights=weights)[0]
                for _ in range(4):
                    if author not in authors:
                        break
                    author = rng.choices(pool, weights=weights)[0]
                authors.append(author)
                moment = when_top()
                sticker = image = None
                text = value if kind == "text" else ""
                if kind == "question":
                    text = value[0]
                elif kind == "gif":
                    sticker = "giphy:gif:" + rng.choice(GIFS[value])
                    text = rng.choice(["", "", "me watching this", "literally me", "🔥🔥", "this is it"])
                elif kind == "sticker":
                    sticker = value
                    text = rng.choice(["", "", "😂", "love it", "same energy"])
                elif kind == "photo":
                    if media == "film":
                        if scene_gifs and rng.random() < 0.5:
                            image = rng.choice(scene_gifs)
                            text = rng.choice(["this moment on loop 🔁", "made a little gif of my fav part",
                                               "can't stop watching this bit"])
                        else:
                            image = rng.choice(stills)
                            text = rng.choice(["this frame though 👇", "screenshotted this one, look at the light",
                                               "my favourite still from the film"])
                    elif picture:
                        image = picture
                        text = rng.choice(bank.get("photo_lines") or ["📸"])
                    else:
                        continue
                cid = await put(text, author, moment, sticker=sticker, image=image)

                # Threads: questions always get an answer; others sometimes.
                replies = []
                if kind == "question":
                    if owner_replies and rng.random() < 0.75:
                        replies.append((owner, rng.choice(value[1]), False))
                    else:
                        helper = rng.choice([u for u in pool if u != author])
                        voice = value[2] if len(value) > 2 else value[1]
                        replies.append((helper, rng.choice(voice), True))
                    if rng.random() < 0.4:
                        replies.append((author, rng.choice(["Thanks!", "thank you 🙏", "ahh got it, thanks",
                                                            "perfect, thanks!"]), False))
                elif owner_replies and rng.random() < 0.4:
                    replies.append((owner, rng.choice(bank["owner"]), False))
                if kind != "question" and rng.random() < 0.3:
                    for _ in range(rng.randint(1, 2)):
                        helper = rng.choice([u for u in pool if u != author])
                        replies.append((helper, rng.choice(bank["replies"]), rng.random() < 0.5))
                parent_time = moment
                for who, line, mention_author in replies:
                    reply_time = when_reply(parent_time)
                    sticker = None
                    if rng.random() < 0.1:
                        sticker = rng.choice(bank["stickers"])
                    await put(line, who, reply_time, parent=cid, sticker=sticker,
                              mention=members[author] if mention_author and who != author else None)
                    parent_time = reply_time
                    threads += 1
        print(f"Added {written} comments ({threads} replies) and {likes} comment likes "
              f"across {len(chosen)} items. Local scene GIFs: {len(scene_gifs)}.")
    finally:
        await c.cache.close()
        await c.graph.store.db.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--reset", action="store_true", help="remove this seed's comments first")
    asyncio.run(main(parser.parse_args().reset))
