"""Phlio Book as a booking super-app: sports venues, doctor appointments,
flights, trains, buses, rides, concerts, festivals, events and meetups.

Idempotent (listings are upserted by id; rerun any time).

* Sports venues are booked by court/turf slot (Playo-style), doctors by
  appointment slot, rides by pickup/drop, trips by route/date/class, events
  by ticket tier, meetups by RSVP (Meetup-style, hosted by Phlio community
  rooms).
* Every listing is a Phlio sample listing with fictional venue, clinic and
  host names. Fares and fees are estimates, and the app labels bookings as demo
  bookings: nothing here pretends to be a real airline, railway, cab company
  or hospital. Real movies and events keep coming from import_book_catalog
  (District/Accessly, booked on the provider's site).
* Pictures are openly licensed photos found on Openverse (openverse.org),
  restricted to licences allowing commercial use and modification, cropped to
  960x540 and credited per listing (platform_content.image_credit).

* Real places from OpenStreetMap (© OpenStreetMap contributors, ODbL):
  named sports centres, pitches, gyms, pools, clinics, doctors and dentists
  in Hyderabad, fetched from the Overpass API and cached in
  media/book_catalog/osm.json. They are listed as "visit" listings (details,
  opening hours, phone, directions) — never bookable here, because Phlio
  has no booking arrangement with them.

Images: media/book_catalog/<id>-<hash>.jpg (+ credits.json).
Run: uv run python -m scripts.import_book_services [--no-images] [--refresh-osm]
The API also runs `ensure_catalog` in the background at startup (development
only) when the catalogue or the OpenStreetMap cache is missing.
"""
import argparse
import asyncio
import datetime as dt
import hashlib
import io
import json
import random

import httpx
from PIL import Image, ImageOps

from app.core.container import build_container, media_root_path
from app.domains.book.entities import BookCategory, BookListing
from app.domains.graph.service import key

SEED = "phlio-book-v1"
OPENVERSE = "https://api.openverse.org/v1/images/"
HEADERS = {"User-Agent": "PhlioDevSeed/1.0 (book demo data)"}
CITY = "Hyderabad"

SP, SV, MB, TR, EN, MT = (BookCategory.SPORTS_AND_ACTIVITIES, BookCategory.SERVICES, BookCategory.MOBILITY,
                          BookCategory.TRAVEL, BookCategory.ENTERTAINMENT, BookCategory.MEET)

# -- Sports venues (slot per hour) ----------------------------------------------
# id, name, area, km, sports, price/hr (₹), rating, amenities, photo search
VENUES = [
    ("smashpoint", "SmashPoint Badminton Arena", "Gachibowli", 2.1, ["Badminton"], 450, 4.6,
     ["Synthetic courts", "Rackets on rent", "Parking", "Washrooms"], "badminton court indoor"),
    ("feather_hub", "Feather Hub Sports", "Kondapur", 3.4, ["Badminton", "Table Tennis"], 380, 4.4,
     ["Wooden courts", "Drinking water", "Changing room"], "badminton shuttlecock racket"),
    ("dropshot", "DropShot Courts", "Madhapur", 4.0, ["Badminton"], 500, 4.7,
     ["8 courts", "AC hall", "Coaching", "Cafe"], "indoor sports hall"),
    ("kickoff_turf", "KickOff Turf", "Kokapet", 6.2, ["Football", "Box Cricket"], 1200, 4.5,
     ["5-a-side", "Floodlights", "Bibs", "Parking"], "football turf night lights"),
    ("rooftop_five", "Rooftop Five", "Jubilee Hills", 7.5, ["Football"], 1500, 4.3,
     ["Rooftop", "7-a-side", "Floodlights"], "five a side football pitch"),
    ("nets_and_bails", "Nets & Bails Academy", "Manikonda", 5.1, ["Cricket"], 600, 4.2,
     ["Bowling machine", "Turf nets", "Coaching"], "cricket nets practice"),
    ("baseline", "Baseline Tennis Club", "Banjara Hills", 8.3, ["Tennis"], 700, 4.6,
     ["Hard courts", "Ball machine", "Coaching"], "tennis court hard"),
    ("pickle_park", "Pickle Park", "HITEC City", 3.0, ["Pickleball"], 550, 4.8,
     ["4 courts", "Paddles on rent", "Beginner sessions"], "pickleball court"),
    ("blue_lane", "Blue Lane Aquatics", "Gachibowli", 2.6, ["Swimming"], 250, 4.4,
     ["25 m pool", "Lifeguard", "Lockers"], "swimming pool lanes"),
    ("climb_co", "Vertical Climb Co.", "Kukatpally", 9.4, ["Climbing"], 800, 4.7,
     ["Bouldering", "Shoes on rent", "Instructors"], "indoor climbing wall bouldering"),
    ("shuttle_station", "Shuttle Station", "Miyapur", 11.2, ["Badminton"], 350, 4.3,
     ["6 courts", "Parking", "Night slots"], "badminton players match"),
    ("goal_line", "Goal Line Arena", "Gachibowli", 2.9, ["Football", "Cricket"], 1400, 4.6,
     ["FIFA-grade turf", "Floodlights", "Showers"], "artificial turf football field"),
    ("spin_club", "Spin Club Table Tennis", "Ameerpet", 7.8, ["Table Tennis"], 200, 4.5,
     ["10 tables", "Coaching", "Robot trainer"], "table tennis match"),
    ("squash_box", "The Squash Box", "Banjara Hills", 8.0, ["Squash"], 600, 4.4,
     ["Glass-back courts", "Racquets on rent"], "squash court"),
    ("strike_lanes", "Strike Lanes Bowling", "Hitech City", 3.6, ["Bowling"], 450, 4.3,
     ["12 lanes", "Cafe", "Party packages"], "bowling alley lanes"),
    ("apex_karting", "Apex Karting Track", "Shamshabad", 24.0, ["Go-karting"], 900, 4.6,
     ["600 m track", "Timing screens", "Helmets"], "go kart racing track"),
    ("flow_yoga", "Flow Yoga Studio", "Jubilee Hills", 6.9, ["Yoga"], 300, 4.8,
     ["Mats provided", "Morning batches"], "yoga class studio"),
    ("ironhouse", "IronHouse Gym (day pass)", "Kondapur", 3.1, ["Gym"], 250, 4.2,
     ["Free weights", "Cardio", "Lockers"], "gym weights training"),
]

# -- Doctors and clinics (appointment slots) ------------------------------------
# id, clinic, doctor, speciality, years, fee, rating, area, languages, photo search
DOCTORS = [
    ("gp_sunrise", "Sunrise Family Clinic", "Dr. Kavya Reddy", "General Physician", 12, 500, 4.7, "Madhapur",
     ["English", "Telugu", "Hindi"], "doctor clinic consultation"),
    ("dent_bright", "BrightSmile Dental Studio", "Dr. Arjun Menon", "Dentist", 9, 400, 4.8, "Kondapur",
     ["English", "Malayalam", "Hindi"], "dental clinic chair"),
    ("derm_clear", "ClearSkin Dermatology", "Dr. Nisha Kapoor", "Dermatologist", 11, 700, 4.6, "Jubilee Hills",
     ["English", "Hindi"], "dermatology clinic"),
    ("peds_tiny", "TinySteps Children's Clinic", "Dr. Farhan Ali", "Paediatrician", 15, 600, 4.9, "Banjara Hills",
     ["English", "Urdu", "Telugu"], "pediatric clinic toys"),
    ("eye_vision", "VisionFirst Eye Care", "Dr. Meera Iyer", "Ophthalmologist", 18, 650, 4.7, "Begumpet",
     ["English", "Tamil", "Hindi"], "eye examination optometry"),
    ("physio_move", "MoveWell Physiotherapy", "Dr. Rahul Varma", "Physiotherapist", 8, 550, 4.5, "Gachibowli",
     ["English", "Telugu"], "physiotherapy session"),
    ("ent_clear", "ClearSound ENT Centre", "Dr. Sana Sheikh", "ENT Specialist", 10, 600, 4.6, "Ameerpet",
     ["English", "Hindi", "Urdu"], "medical stethoscope desk"),
    ("gyn_bloom", "Bloom Women's Clinic", "Dr. Priya Nair", "Gynaecologist", 14, 700, 4.8, "Kondapur",
     ["English", "Malayalam", "Telugu"], "hospital consultation room"),
    ("ortho_stride", "Stride Ortho & Sports Clinic", "Dr. Vikram Singh", "Orthopaedic", 16, 750, 4.6,
     "Gachibowli", ["English", "Hindi"], "orthopedic knee examination"),
    ("mind_calm", "CalmMind Counselling", "Dr. Aisha Khan", "Psychologist", 9, 900, 4.9, "Banjara Hills",
     ["English", "Hindi", "Urdu"], "counselling room calm"),
    ("nutri_leaf", "GreenLeaf Nutrition", "Dr. Sneha Rao", "Dietitian", 7, 500, 4.5, "Madhapur",
     ["English", "Telugu"], "healthy food vegetables bowl"),
    ("lab_home", "CarePoint Diagnostics", "Home sample collection", "Lab Tests", 0, 299, 4.4, "Citywide",
     ["English", "Telugu", "Hindi"], "laboratory blood test tubes"),
]

# -- Trips (route + class) -------------------------------------------------------
# id, mode, from, from code, to, to code, depart, minutes, base fare, classes(name, x), photo search
TRIPS = [
    ("fl_hyd_blr", "flight", "Hyderabad", "HYD", "Bengaluru", "BLR", "07:10", 75, 3900,
     [("Economy", 1.0), ("Premium economy", 1.6)], "Bengaluru city skyline"),
    ("fl_hyd_bom", "flight", "Hyderabad", "HYD", "Mumbai", "BOM", "09:35", 90, 4400,
     [("Economy", 1.0), ("Business", 3.2)], "Mumbai marine drive"),
    ("fl_hyd_del", "flight", "Hyderabad", "HYD", "New Delhi", "DEL", "18:20", 135, 5600,
     [("Economy", 1.0), ("Business", 3.0)], "India Gate Delhi"),
    ("fl_hyd_goi", "flight", "Hyderabad", "HYD", "Goa", "GOX", "11:50", 80, 4200,
     [("Economy", 1.0)], "Goa beach palm"),
    ("fl_hyd_maa", "flight", "Hyderabad", "HYD", "Chennai", "MAA", "15:05", 70, 3500,
     [("Economy", 1.0), ("Premium economy", 1.5)], "Chennai marina beach"),
    ("tr_hyd_blr", "train", "Hyderabad", "KCG", "Bengaluru", "YPR", "17:05", 690, 450,
     [("Sleeper", 1.0), ("AC 3 tier", 2.6), ("AC 2 tier", 3.8)], "Bengaluru Vidhana Soudha"),
    ("tr_hyd_maa", "train", "Hyderabad", "SC", "Chennai", "MAS", "18:10", 760, 420,
     [("Sleeper", 1.0), ("AC 3 tier", 2.6), ("AC 2 tier", 3.8)], "Chennai central station"),
    ("tr_hyd_vsk", "train", "Hyderabad", "SC", "Visakhapatnam", "VSKP", "21:45", 720, 430,
     [("Sleeper", 1.0), ("AC 3 tier", 2.6), ("AC 1st class", 6.0)], "Visakhapatnam beach"),
    ("tr_hyd_tpty", "train", "Hyderabad", "SC", "Tirupati", "TPTY", "20:30", 660, 380,
     [("Sleeper", 1.0), ("AC 3 tier", 2.6)], "Tirumala hills temple"),
    ("bus_hyd_blr", "bus", "Hyderabad", "HYD", "Bengaluru", "BLR", "21:30", 600, 1100,
     [("AC sleeper", 1.0), ("AC seater", 0.75)], "Bengaluru Lalbagh"),
    ("bus_hyd_vja", "bus", "Hyderabad", "HYD", "Vijayawada", "VJA", "06:15", 300, 550,
     [("AC seater", 1.0), ("Non-AC seater", 0.7)], "Vijayawada Krishna river"),
    ("fl_hyd_ccu", "flight", "Hyderabad", "HYD", "Kolkata", "CCU", "13:40", 130, 5200,
     [("Economy", 1.0), ("Business", 3.0)], "Kolkata Howrah bridge"),
    ("fl_hyd_cok", "flight", "Hyderabad", "HYD", "Kochi", "COK", "06:25", 95, 4600,
     [("Economy", 1.0)], "Kerala backwaters houseboat"),
    ("fl_hyd_jai", "flight", "Hyderabad", "HYD", "Jaipur", "JAI", "16:45", 125, 5900,
     [("Economy", 1.0), ("Premium economy", 1.6)], "Jaipur Hawa Mahal"),
    ("tr_hyd_pune", "train", "Hyderabad", "SC", "Pune", "PUNE", "19:20", 780, 470,
     [("Sleeper", 1.0), ("AC 3 tier", 2.6), ("AC 2 tier", 3.8)], "Pune Shaniwar Wada"),
    ("tr_hyd_del", "train", "Hyderabad", "SC", "New Delhi", "NDLS", "07:50", 1580, 820,
     [("Sleeper", 1.0), ("AC 3 tier", 2.6), ("AC 2 tier", 3.8), ("AC 1st class", 6.2)], "Qutub Minar Delhi"),
    ("bus_hyd_hampi", "bus", "Hyderabad", "HYD", "Hampi", "HMP", "20:45", 540, 1200,
     [("AC sleeper", 1.0)], "Hampi ruins boulders"),
    ("bus_hyd_goa", "bus", "Hyderabad", "HYD", "Goa", "GOA", "16:00", 780, 1500,
     [("AC sleeper", 1.0)], "Goa fort sea"),
]

# -- Rides (pickup → drop, now) ---------------------------------------------------
# id, mode, name, seats, base, per km, eta, photo search, blurb
RIDES = [
    ("ride_bike", "bike", "Bike taxi", 1, 25, 7, 3, "motorcycle city traffic", "Beat the traffic, helmet included"),
    ("ride_auto", "auto", "Auto", 3, 35, 13, 4, "auto rickshaw india", "Doorstep pickup, metered estimate"),
    ("ride_mini", "cab", "Cab · Mini", 4, 60, 15, 5, "taxi car city", "Compact AC cars"),
    ("ride_sedan", "cab", "Cab · Sedan", 4, 80, 18, 6, "sedan car night city", "Extra legroom and boot space"),
    ("ride_suv", "cab", "Cab · SUV", 6, 110, 24, 8, "suv car road", "For groups and airport runs"),
]

# -- Ticketed: concerts, festive, events -------------------------------------------
# id, vertical, title, venue, area, days ahead, hour, tiers(name, ₹), photo search, about
TICKETS = [
    ("c_indie_night", "concerts", "Indie Night: Neon Monsoon", "The Loft Stage", "Jubilee Hills", 3, 20,
     [("General", 799), ("Fan pit", 1499)], "indie concert stage lights", "Three local indie bands, one long night."),
    ("c_sufi", "concerts", "Sufi Evening under the Stars", "Courtyard Amphitheatre", "Golconda", 6, 19,
     [("General", 999), ("Front rows", 1999)], "sufi music evening", "Qawwali and sufi classics in an open-air courtyard."),
    ("c_edm", "concerts", "Bass Drop Rooftop Party", "Skyline Terrace", "HITEC City", 9, 21,
     [("Early bird", 1199), ("VIP", 2999)], "edm concert crowd lights", "Four DJs, rooftop sunset to midnight."),
    ("c_carnatic", "concerts", "Carnatic Strings Recital", "Ravindra Hall", "Nampally", 12, 18,
     [("Balcony", 300), ("Stalls", 600)], "violin concert classical", "Violin and veena duet with percussion."),
    ("c_jazz", "concerts", "Sunday Jazz Brunch", "Blue Note Courtyard", "Banjara Hills", 4, 12,
     [("Brunch + show", 1499)], "jazz band saxophone live", "A five-piece jazz band, long brunch, slow Sunday."),
    ("c_tollywood", "concerts", "Tollywood Unplugged", "Open Air Arena", "Gachibowli", 16, 19,
     [("Silver", 699), ("Gold", 1299), ("Platinum", 2499)], "concert stage crowd hands", "Film hits reimagined acoustic, with a 40-piece orchestra."),
    ("f_diwali", "festive", "Diwali Lights Mela", "Necklace Road Grounds", "Hussain Sagar", 5, 17,
     [("Entry", 150), ("Family pass (4)", 500)], "diwali lights diya", "Food stalls, lantern walk, rangoli contest and fireworks show."),
    ("f_kite", "festive", "Sankranti Kite Festival", "Parade Grounds", "Secunderabad", 14, 9,
     [("Entry", 100), ("Kite kit + entry", 350)], "kite festival sky colorful", "Kite flying, folk music and pongal stalls."),
    ("f_xmas", "festive", "Christmas Night Market", "Old Mill Courtyard", "Banjara Hills", 18, 18,
     [("Entry", 199)], "christmas market lights", "Plum cake, carols, crafts and fairy lights."),
    ("f_holi", "festive", "Holi Colour Run", "Botanical Garden Lawns", "Kondapur", 20, 8,
     [("Runner", 499), ("Runner + tee", 799)], "holi colors festival", "5K fun run with organic colours and a DJ finish."),
    ("f_bathukamma", "festive", "Bathukamma Celebrations", "Tank Bund Promenade", "Hussain Sagar", 8, 16,
     [("Entry", 0)], "flower festival india colorful", "Floral stacks, folk songs and dance by the lake."),
    ("f_ganesh", "festive", "Eco Ganesh Utsav", "Community Grounds", "Ameerpet", 22, 18,
     [("Entry", 0), ("Clay idol workshop", 299)], "ganesh festival celebration", "Clay idols, aarti and cultural evenings."),
    ("e_comedy", "events", "Open Mic Comedy Night", "Laugh Lab Cafe", "Madhapur", 2, 20,
     [("General", 349)], "comedy open mic microphone", "Ten new comics, five minutes each."),
    ("e_food", "events", "Street Food Festival", "Shilparamam Grounds", "Madhapur", 7, 16,
     [("Entry", 99), ("Tasting pass", 599)], "street food festival india", "60 stalls from across the country."),
    ("e_art", "events", "Gallery Night Art Walk", "Kalakriti Lane", "Banjara Hills", 10, 18,
     [("Free walk", 0), ("Guided walk", 299)], "art gallery exhibition", "Six galleries open late with artist talks."),
    ("e_book", "events", "Hyderabad Book Fair Weekend", "NTR Stadium Grounds", "Lower Tank Bund", 6, 11,
     [("Entry", 20)], "book fair stalls", "300 stalls, author talks and kids' corner."),
    ("e_flea", "events", "Sunday Flea & Vintage Market", "Shilpakala Vedika Lawns", "Madhapur", 3, 10,
     [("Entry", 50)], "flea market vintage stalls", "Thrift, vinyl, plants and street food."),
    ("e_planet", "events", "Night Sky Stargazing", "Ananthagiri Hills Camp", "Vikarabad", 12, 19,
     [("Transport + session", 1199)], "night sky milky way stargazing", "Telescopes, constellations and a campfire."),
    ("e_expo", "events", "Founders & Builders Expo", "HICC Hall 3", "Madhapur", 15, 10,
     [("Visitor", 499), ("Founder pass", 1499)], "tech conference hall", "Startup demos, investor office hours and workshops."),
]

# -- Meetups (RSVP; hosted by Phlio community rooms) --------------------------------
# id, title, group, room id, venue, area, days, hour, capacity, going, photo search, about
MEETUPS = [
    ("m_blender", "Blender Night: Geometry Nodes Jam", "Blender Artists", "community_blender", "T-Works Hub", "Raidurg",
     4, 18, 40, 27, "3d modeling laptop workshop", "Bring a laptop; we'll build a procedural scene together."),
    ("m_godot", "Godot Game Jam Kickoff", "Godot Engine Devs", "community_godot", "CoWork Commons", "Madhapur",
     6, 10, 60, 44, "game jam developers laptops", "Form teams, get the theme, ship by Sunday."),
    ("m_runners", "Sunday 5K Social Run", "Morning Runners", "community_runners", "KBR Park Gate 1", "Jubilee Hills",
     3, 6, 80, 52, "group running park morning", "Easy pace, coffee after."),
    ("m_boardgames", "Board Game Night", "Bengaluru Meetups", "community_blr_meetups", "Dice & Dough Cafe", "Indiranagar",
     5, 19, 24, 19, "board games friends table", "Catan, Codenames and new releases. Beginners welcome."),
    ("m_photo", "Old City Photo Walk", "Backpackers Lounge", "community_backpackers", "Charminar", "Old City",
     8, 7, 30, 21, "street photography walk", "Golden-hour walk through the bazaars."),
    ("m_cooks", "Biryani Masterclass Potluck", "Home Cooks", "community_home_cooks", "Community Kitchen", "Tolichowki",
     11, 12, 20, 16, "cooking class kitchen group", "Learn dum biryani, then share a potluck lunch."),
    ("m_linux", "Hacktoberfest Contribution Day", "Linux & Open Source", "community_linux", "Open Source Lab", "Gachibowli",
     9, 11, 50, 33, "hackathon coding laptops", "Pair up and land your first open-source PR."),
    ("m_krita", "Urban Sketchers Sunday", "Krita Painters", "community_krita", "Necklace Road", "Hussain Sagar",
     7, 7, 40, 23, "urban sketching people drawing", "Sketch the lake at sunrise, share pages over breakfast."),
    ("m_lofi", "Beat-Making Jam Session", "Lo-fi Producers", "community_lofi", "Soundbox Studio", "Jubilee Hills",
     10, 17, 25, 14, "music producers studio laptop", "Bring headphones and a loop; leave with a collab."),
    ("m_pixel", "Pixel Art Café Meetup", "Pixel Art Club", "community_pixel_art", "8-Bit Cafe", "Kondapur",
     13, 16, 30, 17, "cafe friends laptops drawing", "Draw together, swap palettes, play retro games."),
    ("m_celeste", "Retro Gaming Night", "Speedrun Hub", "community_speedrun", "Arcade Alley", "Hitech City",
     5, 20, 40, 31, "retro arcade games friends", "Speedrun races on big screens and classic co-op games."),
    ("m_study", "Silent Study Sunday", "Open Courseware Study Hall", "community_study_hall", "Reading Room Cafe", "Ameerpet",
     2, 9, 30, 18, "study group library", "Four focused pomodoros and a chai break."),
]


COMMONS = "https://commons.wikimedia.org/w/api.php"
SEARCH_CACHE: dict = {}  # query -> results, persisted in search_cache.json
_last_search = [0.0]


def _get_with_backoff(client, url, params):
    """GET with a polite pace and Retry-After handling (Openverse throttles
    anonymous clients, which left many listings without photos)."""
    import time
    for attempt in range(4):
        wait = 1.2 - (time.monotonic() - _last_search[0])
        if wait > 0:
            time.sleep(wait)
        _last_search[0] = time.monotonic()
        r = client.get(url, params=params)
        if r.status_code == 429 or r.status_code >= 500:
            time.sleep(min(60, float(r.headers.get("Retry-After") or 8 * (attempt + 1))))
            continue
        r.raise_for_status()
        return r.json()
    raise httpx.HTTPError(f"{url} kept refusing (status {r.status_code})")


def openverse(client, query, aspect="wide"):
    data = _get_with_backoff(client, OPENVERSE, dict(
        q=query, license_type="commercial,modification", aspect_ratio=aspect, page_size=20, mature="false"))
    return [x for x in data.get("results", []) if x.get("url")]


def commons(client, query):
    """Wikimedia Commons photos (CC BY / BY-SA / CC0 / public domain)."""
    import re
    data = _get_with_backoff(client, COMMONS, dict(
        action="query", format="json", generator="search", gsrsearch=f"filetype:bitmap {query}",
        gsrnamespace=6, gsrlimit=20, prop="imageinfo", iiprop="url|extmetadata|size", iiurlwidth=1280))
    out = []
    for page in (data.get("query", {}).get("pages", {}) or {}).values():
        info = (page.get("imageinfo") or [{}])[0]
        meta = info.get("extmetadata", {})
        licence = (meta.get("LicenseShortName", {}).get("value") or "").strip()
        low = licence.lower()
        if not (low.startswith("cc by") or low.startswith("cc0") or "public domain" in low) or "nc" in low.split():
            continue
        if (info.get("width") or 0) < 600:
            continue
        artist = re.sub(r"<[^>]+>", "", meta.get("Artist", {}).get("value") or "unknown").strip()
        out.append(dict(url=info.get("thumburl") or info.get("url"), title=page.get("title", "").removeprefix("File:"),
                        creator=artist[:80], license=licence, license_version="",
                        foreign_landing_url=info.get("descriptionurl"),
                        attribution=f"\"{page.get('title', '').removeprefix('File:')}\" by {artist[:80]}, {licence} (Wikimedia Commons)"))
    return out


def search(client, query):
    """Openly licensed photos for a query: Openverse, then Wikimedia Commons."""
    if query in SEARCH_CACHE and SEARCH_CACHE[query]:
        return SEARCH_CACHE[query]
    results = []
    try:
        results = openverse(client, query)
    except (httpx.HTTPError, ValueError) as exc:
        print(f"  Openverse search failed for '{query}': {exc}", flush=True)
    if len(results) < 3:
        try:
            results += commons(client, query)
        except (httpx.HTTPError, ValueError) as exc:
            print(f"  Commons search failed for '{query}': {exc}", flush=True)
    SEARCH_CACHE[query] = results
    return results


def fetch(client, query, rng, used):
    results = list(search(client, query))
    rng.shuffle(results)
    # Prefer photos no other listing uses; reuse one if the search is small.
    results = [r for r in results if r["url"] not in used] + [r for r in results if r["url"] in used]
    for item in results[:8]:
        for url in (item["url"], item.get("thumbnail")):
            if not url:
                continue
            try:
                response = client.get(url, timeout=40)
                response.raise_for_status()
                image = Image.open(io.BytesIO(response.content)).convert("RGB")
            except Exception:
                continue
            if min(image.size) < 300:
                continue
            used.add(item["url"])
            credit = item.get("attribution") or (
                f"\"{item.get('title') or 'Untitled'}\" by {item.get('creator') or 'unknown'}, "
                f"{(item.get('license') or '').upper()} {item.get('license_version') or ''}".strip())
            return ImageOps.fit(image, (960, 540), Image.LANCZOS), credit
    return None, None


def at(days, hour, minute=0):
    day = dt.datetime.now(dt.UTC).astimezone(dt.timezone(dt.timedelta(hours=5, minutes=30))).date() + dt.timedelta(days=days)
    return dt.datetime.combine(day, dt.time(hour, minute), tzinfo=dt.timezone(dt.timedelta(hours=5, minutes=30)))


GOING = {"meetups", "sports", "events", "concerts", "festive"}


async def going(c, listing, vertical, meta, members, rng):
    """Community members who booked / are going (the avatar stacks)."""
    target = {
        "meetups": meta.get("going", 15),
        "sports": rng.randint(6, 24),
        "events": rng.randint(18, 70),
        "concerts": rng.randint(25, 80),
        "festive": rng.randint(30, 90),
    }[vertical]
    obj = await c.graph.store.get(key("phlio_object", "book", listing.id))
    if not obj:
        return
    now = dt.datetime.now(dt.UTC)
    for uid in rng.sample(members, min(len(members), target)):
        aid = key("activity", uid, obj["id"], "booked")
        if await c.graph.store.get(aid):
            continue
        policy = await c.graph.policy(uid, obj, "booked")
        await c.graph.store.put(aid, {
            "in": "user:" + uid, "out": obj["id"], "verb": "booked",
            "created_at": (now - dt.timedelta(minutes=rng.randint(5, 60 * 24 * 6))).isoformat(),
            "visibility_class": policy["audience"] + "_" + policy["identity_mode"]})


def build():
    """(listing, vertical, booking kind, meta, photo search) for every service."""
    out = []
    for vid, name, area, km, sports, price, rating, amenities, q in VENUES:
        out.append((BookListing(
            id=f"pb_venue_{vid}", title=name, category=SP, venue=name, location_note=f"{area}, {CITY}",
            description=f"{' · '.join(sports)} in {area}. " + ", ".join(amenities) + ".",
            price_min_minor_units=price * 100, price_max_minor_units=int(price * 1.3) * 100,
            duration_label="per hour", rating=rating, tags=["Sports"] + sports),
            "sports", "slot",
            dict(sports=sports, area=area, distance_km=km, amenities=amenities, open="06:00", close="23:00",
                 slot_minutes=60, unit="court", peak_after="17:00"), q))
    for did, clinic, doctor, spec, years, fee, rating, area, langs, q in DOCTORS:
        lab = spec == "Lab Tests"
        out.append((BookListing(
            id=f"pb_doc_{did}", title=doctor if not lab else clinic, category=SV, venue=clinic,
            location_note=f"{area}, {CITY}",
            description=(f"{spec} · {years} years of experience. Speaks {', '.join(langs)}." if not lab else
                         "Full body checkups and individual tests with home sample collection."),
            price_min_minor_units=fee * 100, price_max_minor_units=fee * 100,
            duration_label="15 min consult" if not lab else "Home visit", rating=rating,
            tags=["Doctors", spec]),
            "doctor", "slot",
            dict(speciality=spec, clinic=clinic, experience_years=years, languages=langs, area=area,
                 open="09:00", close="20:00", slot_minutes=15 if not lab else 30, unit="appointment",
                 video_consult=not lab), q))
    for tid, mode, a, ac, b, bc, depart, minutes, fare, classes, q in TRIPS:
        h, m = map(int, depart.split(":"))
        arrive = (dt.datetime(2026, 1, 1, h, m) + dt.timedelta(minutes=minutes)).strftime("%H:%M")
        label = {"flight": "Flight", "train": "Train", "bus": "Bus"}[mode]
        out.append((BookListing(
            id=f"pb_trip_{tid}", title=f"{a} → {b}", category=TR, venue=f"{label} · {ac} → {bc}",
            location_note=f"Departs {depart}",
            description=f"{label} from {a} to {b}. About {minutes // 60}h {minutes % 60:02d}m. Fares are estimates.",
            price_min_minor_units=fare * 100, price_max_minor_units=int(fare * max(c for _, c in classes)) * 100,
            duration_label=f"{minutes // 60}h {minutes % 60:02d}m", tags=["Travel", label]),
            mode, "trip",
            dict(from_city=a, from_code=ac, to_city=b, to_code=bc, depart=depart, arrive=arrive,
                 minutes=minutes, classes=[dict(name=n, multiplier=x, fare=int(fare * x)) for n, x in classes],
                 stops="Non-stop" if mode == "flight" else ("Overnight" if minutes > 480 else "Day"),
                 seats_left=random.Random(tid).randint(3, 42)), q))
    for rid, mode, name, seats, base, per_km, eta, q, blurb in RIDES:
        out.append((BookListing(
            id=f"pb_{rid}", title=name, category=MB, venue=blurb, location_note=f"{CITY} · {eta} min away",
            description=f"{blurb}. Estimated fare ₹{base} + ₹{per_km}/km.",
            price_min_minor_units=(base + per_km * 3) * 100, price_max_minor_units=(base + per_km * 15) * 100,
            duration_label=f"{eta} min away", tags=["Rides", name.split(' ·')[0]]),
            mode, "ride", dict(seats=seats, base_fare=base, per_km=per_km, eta_min=eta), q))
    for eid, vertical, title, venue, area, days, hour, tiers, q, about in TICKETS:
        prices = [p for _, p in tiers]
        out.append((BookListing(
            id=f"pb_event_{eid}", title=title, category=EN, venue=venue, location_note=f"{area}, {CITY}",
            description=about, price_min_minor_units=min(prices) * 100, price_max_minor_units=max(prices) * 100,
            duration_label="3 hours", starts_at=at(days, hour), is_free=max(prices) == 0,
            tags=[{"concerts": "Music", "festive": "Festive", "events": "Experiences"}[vertical]]),
            vertical, "ticket", dict(tiers=[dict(name=n, price=p) for n, p in tiers], area=area), q))
    for mid, title, group, room, venue, area, days, hour, cap, going, q, about in MEETUPS:
        out.append((BookListing(
            id=f"pb_meet_{mid}", title=title, category=MT, venue=venue, location_note=area,
            description=about, duration_label="2–3 hours", starts_at=at(days, hour), is_free=True,
            tags=["Meetups", group]),
            "meetups", "rsvp",
            dict(group=group, room_id=room, capacity=cap, going=going, area=area), q))
    return out


# -- OpenStreetMap: real venues and clinics (visit listings) -----------------------
OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
BBOX = "17.28,78.30,17.56,78.60"  # Hyderabad
CENTRE = (17.4401, 78.3489)  # Gachibowli / HITEC City
SPORT_NAMES = {
    "badminton": "Badminton", "tennis": "Tennis", "table_tennis": "Table Tennis", "soccer": "Football",
    "football": "Football", "cricket": "Cricket", "basketball": "Basketball", "swimming": "Swimming",
    "squash": "Squash", "volleyball": "Volleyball", "yoga": "Yoga", "fitness": "Gym", "athletics": "Athletics",
    "skating": "Skating", "climbing": "Climbing", "bowling": "Bowling", "10pin": "Bowling", "karting": "Go-karting",
    "pickleball": "Pickleball", "multi": "Multi-sport", "kabaddi": "Kabaddi", "chess": "Chess",
}
SPECIALITIES = {
    "general": "General Physician", "paediatrics": "Paediatrician", "pediatrics": "Paediatrician",
    "dermatology": "Dermatologist", "ophthalmology": "Ophthalmologist", "gynaecology": "Gynaecologist",
    "orthopaedics": "Orthopaedic", "dentistry": "Dentist", "otolaryngology": "ENT Specialist",
    "cardiology": "Cardiologist", "physiotherapy": "Physiotherapist", "psychiatry": "Psychiatrist",
}
SPORT_PHOTO = {"Badminton": "badminton court", "Tennis": "tennis court", "Football": "football pitch",
               "Cricket": "cricket ground", "Swimming": "swimming pool", "Gym": "gym fitness",
               "Yoga": "yoga studio", "Basketball": "basketball court", "Table Tennis": "table tennis"}


def _km(lat, lon):
    import math
    dlat, dlon = math.radians(lat - CENTRE[0]), math.radians(lon - CENTRE[1])
    a = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat)) * math.cos(math.radians(CENTRE[0])) * math.sin(dlon / 2) ** 2
    return round(6371 * 2 * math.asin(math.sqrt(a)), 1)


def fetch_osm(cache, refresh=False):
    """Named sports places and clinics in Hyderabad from Overpass (cached)."""
    if cache.exists() and not refresh:
        return json.loads(cache.read_text(encoding="utf-8"))
    query = f"""[out:json][timeout:90];
(
  nwr["leisure"~"^(sports_centre|sports_hall|fitness_centre|pitch|swimming_pool|stadium)$"]["name"]({BBOX});
  nwr["amenity"~"^(clinic|doctors|dentist)$"]["name"]({BBOX});
);
out center tags 1500;"""
    for url in OVERPASS:
        try:
            r = httpx.post(url, data={"data": query}, headers=HEADERS, timeout=120)
            r.raise_for_status()
            elements = r.json().get("elements", [])
            cache.write_text(json.dumps(elements, ensure_ascii=False), encoding="utf-8")
            return elements
        except (httpx.HTTPError, ValueError) as exc:
            print(f"  Overpass {url} failed: {exc}", flush=True)
    return []


def osm_listings(elements, max_sports=40, max_clinics=30):
    """OpenStreetMap places as (listing, vertical, kind, meta, photo search)."""
    sports, clinics = [], []
    for el in elements:
        tags = el.get("tags", {})
        name = (tags.get("name:en") or tags.get("name") or "").strip()
        lat = el.get("lat") or el.get("center", {}).get("lat")
        lon = el.get("lon") or el.get("center", {}).get("lon")
        if not name or lat is None or lon is None or tags.get("access") == "private":
            continue
        osm_type, osm_id = el.get("type", "node"), el.get("id")
        area = (tags.get("addr:suburb") or tags.get("addr:neighbourhood") or tags.get("addr:street")
                or tags.get("addr:city") or CITY)
        common = dict(area=area, distance_km=_km(lat, lon), lat=lat, lon=lon,
                      phone=tags.get("phone") or tags.get("contact:phone"),
                      website=tags.get("website") or tags.get("contact:website"),
                      opening_hours=tags.get("opening_hours"),
                      osm_url=f"https://www.openstreetmap.org/{osm_type}/{osm_id}",
                      source="OpenStreetMap")
        if tags.get("amenity") in {"clinic", "doctors", "dentist"}:
            if tags.get("amenity") == "dentist":
                spec = "Dentist"
            else:
                specs = [SPECIALITIES.get(x.strip()) for x in tags.get("healthcare:speciality", "").split(";")]
                spec = next((x for x in specs if x), "Clinic")
            clinics.append((BookListing(
                id=f"osm_{osm_type}_{osm_id}", title=name, category=SV, venue=name,
                location_note=f"{area}, {CITY}",
                description=f"{spec} in {area}. Listed on OpenStreetMap; contact the clinic for appointments.",
                tags=["Doctors", spec], source_name="OpenStreetMap", source_url=common["osm_url"]),
                "doctor", "visit", dict(common, speciality=spec, clinic=name),
                {"Dentist": "dental clinic"}.get(spec, "clinic doctor consultation")))
            continue
        leisure = tags.get("leisure")
        names = [SPORT_NAMES[x.strip()] for x in tags.get("sport", "").split(";") if x.strip() in SPORT_NAMES]
        if leisure == "fitness_centre" and not names:
            names = ["Gym"]
        if leisure == "swimming_pool" and not names:
            names = ["Swimming"]
        names = list(dict.fromkeys(names))
        if not names:
            continue
        sports.append((BookListing(
            id=f"osm_{osm_type}_{osm_id}", title=name, category=SP, venue=name,
            location_note=f"{area}, {CITY}",
            description=f"{' · '.join(names)} in {area}. Listed on OpenStreetMap; call or visit to book.",
            tags=["Sports"] + names, source_name="OpenStreetMap", source_url=common["osm_url"]),
            "sports", "visit", dict(common, sports=names),
            SPORT_PHOTO.get(names[0], f"{names[0].lower()} sport")))
    # Nearest (and best-described) first.
    rank = lambda row: (row[3]["distance_km"] - 2 * bool(row[3].get("phone")) - 2 * bool(row[3].get("opening_hours")))
    return sorted(sports, key=rank)[:max_sports] + sorted(clinics, key=rank)[:max_clinics]


async def seed(c, images=True, refresh_osm=False):
    """Upsert the whole catalogue into an open container (script or API)."""
    root = media_root_path(c.settings) / "book_catalog"
    root.mkdir(parents=True, exist_ok=True)
    credits_path = root / "credits.json"
    credits = json.loads(credits_path.read_text(encoding="utf-8")) if credits_path.exists() else {}
    client = httpx.Client(headers=HEADERS, timeout=30, follow_redirects=True) if images else None
    used: set = set()
    counts: dict[str, int] = {}
    search_cache = root / "search_cache.json"
    if search_cache.exists():
        SEARCH_CACHE.update(json.loads(search_cache.read_text(encoding="utf-8")))
    elements = await asyncio.to_thread(fetch_osm, root / "osm.json", refresh_osm)
    catalogue = build() + osm_listings(elements)
    try:
        members = []
        for i in range(20, 100):
            person = await c.identity_repository.get_by_id(f"demo_{i:03}")
            if person and person.is_test_user:
                members.append(person.id)
        for listing, vertical, kind, meta, query in catalogue:
            rng = random.Random(hashlib.sha256((SEED + listing.id).encode()).hexdigest())
            # The file name carries the search, so a new search refetches.
            target = root / f"{listing.id}-{hashlib.sha1(query.encode()).hexdigest()[:6]}.jpg"
            if not target.exists() and client is not None:
                image, credit = await asyncio.to_thread(fetch, client, query, rng, used)
                if image is not None:
                    image.save(target, quality=85)
                    credits[target.name] = credit
            if target.exists():
                listing.image_url = f"/media/book_catalog/{target.name}"
            await c.book_repository.seed_listing(listing)
            object_type = {"slot": "place", "visit": "place", "ticket": "event", "rsvp": "event"}.get(kind, "activity")
            if not await c.graph.store.get(key("phlio_object", "book", listing.id)):
                await c.graph.register_object("demo_000", f"book.{object_type}", listing.id, listing.title)
            await c.graph.store.put(key("platform_content", "book", listing.id), dict(
                platform="book", domain_ref=listing.id, kind=object_type,
                object_id=key("phlio_object", "book", listing.id),
                description=listing.description, image_url=listing.image_url,
                vertical=vertical, booking_kind=kind, meta=meta,
                image_credit=credits.get(target.name), seed=SEED))
            counts[vertical] = counts.get(vertical, 0) + 1
            if vertical in GOING and kind != "visit":  # never invent visitors for real places
                await going(c, listing, vertical, meta, members, rng)
            print(f"{vertical:9} {listing.title}  {'📷' if listing.image_url else '—'}", flush=True)
        credits_path.write_text(json.dumps(credits, indent=2, ensure_ascii=False), encoding="utf-8")
        search_cache.write_text(json.dumps(SEARCH_CACHE, ensure_ascii=False), encoding="utf-8")
        missing = sum(1 for _l, *_ in catalogue if not _l.image_url)
        if missing:
            print(f"  {missing} listings still have no photo; rerun later to retry.", flush=True)
        print(f"Phlio Book catalog ready: {counts} ({len(catalogue) - len(build())} from OpenStreetMap)", flush=True)
        return counts
    finally:
        if client is not None:
            client.close()


async def ensure_catalog(c):
    """Startup hook (development): seed when the catalogue or the
    OpenStreetMap cache is missing, so Book's categories are never empty."""
    root = media_root_path(c.settings) / "book_catalog"
    have = {p.name.rsplit("-", 1)[0] for p in root.glob("*.jpg")} if root.exists() else set()
    photos_missing = any(listing.id not in have for listing, *_ in build())
    if (await c.book_repository.get_listing("pb_venue_smashpoint") and (root / "osm.json").exists()
            and not photos_missing):
        return
    await seed(c)


async def main(images=True, refresh_osm=False):
    from scripts.run_graph_demo import settings
    c = await build_container(settings)
    try:
        await seed(c, images=images, refresh_osm=refresh_osm)
    finally:
        await c.cache.close()
        if getattr(c.graph.store, "db", None):
            await c.graph.store.db.close()
        c.social_video_service.db.close()
        c.messaging_service.db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-images", action="store_true")
    parser.add_argument("--refresh-osm", action="store_true", help="fetch OpenStreetMap places again")
    args = parser.parse_args()
    asyncio.run(main(images=not args.no_images, refresh_osm=args.refresh_osm))
