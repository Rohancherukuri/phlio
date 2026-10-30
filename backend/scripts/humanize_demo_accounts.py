"""Give the 100 seeded community accounts believable public profiles.

The seed creates accounts with ids ``demo_000``..``demo_099`` and handles such
as ``demo_creator_001``. This keeps the internal ids (every post, follow, like
and room membership points at them) but replaces everything people see:
username, display name, bio and email, so nobody shows up as ``demo_…``.

Names are matched to the RandomUser.me portrait each account already uses
(even index = women's portrait, odd = men's). Accounts 090-099 never got a
portrait, so one is downloaded for them. Idempotent: re-running only fixes
accounts that still look like seed data.
"""

import asyncio
import json
from pathlib import Path

import httpx

from app.core.container import build_container, media_root_path
from scripts.run_graph_demo import settings

TOPICS = ["Design", "Gaming", "Music", "Code", "Travel", "Food", "Fitness", "Photography", "Books", "Science"]

# (full name, username) — even indexes use women's portraits, odd use men's.
WOMEN = [
    ("Ananya Rao", "ananyadesigns"), ("Meera Kapoor", "meera_makes_music"),
    ("Tara Fernandes", "tarawanders"), ("Ishita Banerjee", "ishita_moves"),
    ("Sana Qureshi", "sana_reads"), ("Kavya Nair", "kavyaframes"),
    ("Riya Malhotra", "riya_onkeys"), ("Zoya Sheikh", "zoyagoesplaces"),
    ("Nikita Joshi", "nikita_lifts"), ("Aditi Kulkarni", "aditi_marginalia"),
    ("Priya Menon", "priyamenon_"), ("Sneha Reddy", "snehareddy"),
    ("Pooja Iyer", "poojaiyer"), ("Divya Pillai", "divyapillai_"),
    ("Nisha Verma", "nishaverma92"), ("Anjali Deshmukh", "anjali_d"),
    ("Shreya Ghosh", "shreyaghosh"), ("Lavanya Krishnan", "lavanya_k"),
    ("Neha Saxena", "nehasaxena"), ("Aishwarya Hegde", "aish_hegde"),
    ("Rhea D'Souza", "rheadsouza"), ("Simran Kaur", "simrankaur_"),
    ("Mansi Agarwal", "mansi_agarwal"), ("Tanvi Bhatt", "tanvibhatt"),
    ("Ira Chatterjee", "ira_chatterjee"), ("Kriti Sharma", "kritisharma_"),
    ("Pallavi Joshi", "pallavij"), ("Swati Mishra", "swatimishra"),
    ("Madhuri Patil", "madhuri_patil"), ("Gauri Sawant", "gaurisawant"),
    ("Fatima Khan", "fatimakhan_"), ("Emma Clarke", "emmaclarke"),
    ("Sofia Martinez", "sofiamtz"), ("Hana Kim", "hanakim_"),
    ("Chloe Bennett", "chloebennett"), ("Leah Thomas", "leahthomas_"),
    ("Naomi Okafor", "naomiokafor"), ("Yuki Tanaka", "yukitanaka"),
    ("Elena Rossi", "elenarossi"), ("Amara Singh", "amarasingh"),
    ("Ritika Chopra", "ritikachopra"), ("Bhavna Shetty", "bhavnashetty"),
    ("Charu Arora", "charu_arora"), ("Esha Bajaj", "eshabajaj"),
    ("Jhanvi Rathod", "jhanvi_r"), ("Komal Yadav", "komalyadav"),
    ("Mitali Sen", "mitalisen"), ("Pari Thakur", "pari_thakur"),
    ("Ruhi Mirza", "ruhimirza"), ("Vaani Kohli", "vaanikohli"),
]
MEN = [
    ("Kabir Mehta", "kabirplays"), ("Arjun Iyer", "arjun_codes"),
    ("Vikram Shah", "vikram_cooks"), ("Aditya Sen", "adityasenphoto"),
    ("Neil D'Costa", "neil_explains"), ("Dev Malhotra", "dev_respawns"),
    ("Siddharth Rao", "sid_ships"), ("Farhan Ali", "farhan_eats"),
    ("Ishaan Kapoor", "ishaanshoots"), ("Aryan Bose", "aryan_bose"),
    ("Rahul Nair", "rahulnair_"), ("Karthik Subramanian", "karthik_s"),
    ("Varun Sethi", "varunsethi"), ("Nikhil Jain", "nikhiljain"),
    ("Pranav Kulkarni", "pranav_k"), ("Aman Gupta", "aman_g"),
    ("Harsh Vardhan", "harshvardhan_"), ("Yash Thakkar", "yashthakkar"),
    ("Manav Arora", "manavarora"), ("Kunal Bhatia", "kunalbhatia"),
    ("Abhishek Pandey", "abhishekpandey"), ("Ritesh Shetty", "riteshshetty"),
    ("Omkar Joshi", "omkar_j"), ("Sameer Khan", "sameerkhan_"),
    ("Tushar Mehra", "tusharmehra"), ("Akash Reddy", "akashreddy"),
    ("Vivek Menon", "vivek_menon"), ("Gaurav Bhalla", "gauravbhalla"),
    ("Rajat Kumar", "rajatkumar_"), ("Mihir Desai", "mihirdesai"),
    ("Zaid Ansari", "zaidansari"), ("Lucas Silva", "lucassilva"),
    ("Daniel Park", "danielpark"), ("Oliver Hughes", "oliverhughes"),
    ("Mateo Garcia", "mateogarcia"), ("Kenji Watanabe", "kenjiw"),
    ("Samuel Adeyemi", "samadeyemi"), ("Ethan Brooks", "ethanbrooks"),
    ("Arnav Saxena", "arnavsaxena"), ("Dhruv Chawla", "dhruvchawla"),
    ("Parth Vyas", "parthvyas"), ("Rudra Pratap", "rudrapratap"),
    ("Shaurya Malik", "shauryamalik"), ("Tejas Rane", "tejasrane"),
    ("Uday Kiran", "udaykiran"), ("Vedant Joshi", "vedantjoshi"),
    ("Yuvraj Gill", "yuvrajgill"), ("Ayaan Siddiqui", "ayaansiddiqui"),
    ("Neeraj Bisht", "neerajbisht"), ("Ojas Kelkar", "ojaskelkar"),
]

# Creators (000-019) post the open-film studies, so their bios mix their own
# craft with film breakdowns. Index = topic order in TOPICS, twice over.
CREATOR_BIOS = [
    "Product designer by day, frame-by-frame film nerd by night 🎬 Breaking down open movies one still at a time.",
    "Streams on weekends 🎮 Cutting cinematic moments from open films between ranked matches.",
    "Composer & sound designer 🎧 I listen to movies more than I watch them.",
    "Frontend dev · Blender hobbyist · posting VFX breakdowns of open-source films 💻",
    "Travel filmmaker ✈️ Location scouting through every frame. Currently: Amsterdam on screen.",
    "Home cook, food stylist and lighting obsessive 🍳 Good light makes everything look delicious.",
    "Strength coach 🏋️ + action-scene choreography fan. Slow-mo is my love language.",
    "Photographer 📷 Stills, colour grading and the occasional film study.",
    "Reading 52 books this year 📚 Writing about stories on the page and on the screen.",
    "Science communicator 🔭 Explaining the tech behind sci-fi, one scene at a time.",
    "UI/UX designer · Mumbai 🎨 Collecting beautiful frames for my moodboards.",
    "Indie game dev 🕹️ Studying film pacing to make better cutscenes.",
    "Pianist & beat maker 🎹 Scoring short films for fun.",
    "Backend engineer by profession, editor by passion ✂️ Open-source everything.",
    "Backpacker 🎒 42 cities and counting. Sharing what I'm watching on the road.",
    "Chef in training 👨‍🍳 Plating, food photography and late-night movie breaks.",
    "Runner & yoga teacher 🧘 Finding calm in long takes.",
    "Visual storyteller 📸 Weddings, streets and cinematic frames.",
    "Book reviewer & bookstagrammer 📖 Adaptations are my favourite argument.",
    "Physics grad 🧪 Making sense of how sci-fi worlds would actually work.",
]
CITIES = ["Mumbai", "Bengaluru", "Pune", "Delhi", "Hyderabad", "Chennai", "Kolkata", "Jaipur", "Goa",
          "Ahmedabad", "Kochi", "Indore", "London", "Toronto", "Singapore", "Dubai"]
LIKES = {
    "Design": "good typography", "Gaming": "co-op games", "Music": "live gigs", "Code": "side projects",
    "Travel": "weekend getaways", "Food": "street food", "Fitness": "morning runs",
    "Photography": "golden-hour walks", "Books": "slow Sunday reads", "Science": "space documentaries",
}
VIEWER_BIOS = [
    "{a} & {b} · {city}",
    "{city} 📍 into {a_low} and {b_low}",
    "Here for {a_like} and {b_like} ✨",
    "{a} enthusiast. Probably talking about {b_like}.",
    "{city} | {a} | {b} | coffee ☕",
    "Weekdays: work. Weekends: {a_like}.",
    "Saving every {a_low} post I see 🔖 {city}",
    "{b} on my mind, {a_low} in my feed.",
]


def profile_for(i: int):
    name, username = (WOMEN if i % 2 == 0 else MEN)[i // 2]
    a, b = TOPICS[i % 10], TOPICS[(i + 3) % 10]
    if i < 20:
        bio = CREATOR_BIOS[i]
    else:
        bio = VIEWER_BIOS[i % len(VIEWER_BIOS)].format(
            a=a, b=b, a_low=a.lower(), b_low=b.lower(), a_like=LIKES[a], b_like=LIKES[b],
            city=CITIES[i % len(CITIES)])
    return name, username, bio


async def main():
    c = await build_container(settings)
    root = media_root_path(c.settings) / "demo_graph"
    renamed = []
    try:
        async with httpx.AsyncClient(timeout=30, follow_redirects=True) as client:
            for i in range(100):
                uid = f"demo_{i:03}"
                user = await c.identity_repository.get_by_id(uid)
                if not user or not user.is_test_user:
                    continue
                name, username, bio = profile_for(i)
                clash = await c.identity_repository.get_by_username(username)
                if clash and clash.id != uid:
                    username = f"{username}{i:02}"
                user.username = username
                user.full_name = name
                user.bio = bio
                user.email = f"{username.strip('_').replace('_', '.')}@example.com"
                if not (user.avatar_url or "").endswith(".jpg"):
                    # 090-099 still have generated placeholder art; give them a portrait.
                    image = root / f"portrait_{i:03}.jpg"
                    if not image.exists():
                        gender = "women" if i % 2 == 0 else "men"
                        try:
                            response = await client.get(
                                f"https://randomuser.me/api/portraits/{gender}/{i // 2}.jpg")
                            response.raise_for_status()
                            if response.content.startswith(b"\xff\xd8"):
                                image.write_bytes(response.content)
                        except httpx.HTTPError:
                            pass
                    if image.exists():
                        user.avatar_url = "/media/demo_graph/" + image.name
                await c.identity_repository.update_user(user)
                renamed.append((uid, username, name))
        # Seed posts were tagged #demo / #syntheticdemo; swap for real topic tags.
        retagged = 0
        for i in range(20):
            for j in range(3):
                pid = f"demo_post_{i:02}_{j}"
                post = await c.social_repository.get_post(pid)
                tags = list(getattr(post, "tags", None) or [])
                if not post or not {"demo", "syntheticdemo"} & set(tags):
                    continue
                fixed = ["tearsofsteel" if t == "demo" else t for t in tags if t != "syntheticdemo"]
                if j == 0 and len(fixed) < 2:
                    fixed.append(["sketchbook", "progress", "learning", "dailypractice"][i % 4])
                await c.social_repository._db.merge("post:" + pid, dict(tags=fixed))
                retagged += 1
        info = Path("data/social_graph_demo.json")
        if info.exists():
            data = json.loads(info.read_text())
            by_id = {uid: username for uid, username, _ in renamed}
            data["creator"] = by_id.get("demo_000", data.get("creator"))
            data["consumer"] = by_id.get("demo_020", data.get("consumer"))
            info.write_text(json.dumps(data, indent=2))
        print(f"Retagged {retagged} posts.")
        print(f"Updated {len(renamed)} community profiles, e.g. "
              + ", ".join(f"@{u} ({n})" for _, u, n in renamed[:4]))
    finally:
        await c.cache.close()
        await c.graph.store.db.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()


if __name__ == "__main__":
    asyncio.run(main())
