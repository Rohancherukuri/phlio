"""
Seed data for `DATABASE_BACKEND=memory`.

Populates the in-memory repositories with a small, coherent demo dataset so
the API — and the Flutter app pointed at it — has something real to show
immediately after `uv run uvicorn app.main:app --reload`, with no manual
setup. The content intentionally echoes the reference screenshots (Arjun,
the Tech & AI room, the wooden lamp / sunset horizons products) so the
running app visually matches the product brief, while the domain shape
underneath follows Phlio_Final_Product_Blueprint.md — these are `Product`s
in the `art_and_handmade` Shop category, not a separate Art domain.

Only runs when `settings.database_backend == "memory"`; production/staging
with `DATABASE_BACKEND=surreal` should seed through
`data/surrealdb/seed/` instead (see that directory's README).
"""

from __future__ import annotations

import datetime as dt
import logging

from app.core.container import Container
from app.domains.activity.entities import ActivityItem, ActivityKind
from app.domains.book.entities import BookCategory, BookListing, Booking
from app.domains.identity.entities import User
from app.domains.pay.entities import Transaction, TransactionType, Wallet
from app.domains.rooms.entities import (
    MessageAttachment,
    MessageReaction,
    Room,
    RoomCategory,
    RoomMessage,
)
from app.domains.shop.entities import Product, ProductCondition, Seller, ShopCategory
from app.domains.social.entities import Post
from app.infrastructure.security.password import hash_password

logger = logging.getLogger("phlio.seed")


async def seed_memory_backend(container: Container) -> None:
    identity_repo = container.identity_repository
    social_repo = container.social_repository
    rooms_repo = container.rooms_repository
    shop_repo = container.shop_repository

    now = dt.datetime.now(dt.UTC)

    # -- Users --------------------------------------------------------
    arjun = User(
        id="usr_arjun",
        username="arjun",
        full_name="Arjun Sharma",
        email="arjun@example.com",
        hashed_password=hash_password("password123"),
        avatar_url=None,
        bio="Building things, one weekend project at a time.",
        interests=["tech", "art", "travel"],
        is_verified=True,
    )
    kiara = User(
        id="usr_kiara",
        username="artbykiara",
        full_name="Kiara Mehta",
        email="kiara@example.com",
        hashed_password=hash_password("password123"),
        avatar_url=None,
        bio="Turning scraps into stories. Handmade lighting & decor.",
        interests=["art", "sustainability"],
        is_verified=True,
    )
    neha = User(
        id="usr_neha",
        username="neha",
        full_name="Neha Kapoor",
        email="neha@example.com",
        hashed_password=hash_password("password123"),
        avatar_url=None,
        bio="Local LLM tinkerer.",
        interests=["tech", "gaming"],
    )
    for user in (arjun, kiara, neha):
        await identity_repo.create_user(user)

    # -- Rooms ----------------------------------------------------------
    tech_room = Room(
        id="rm_tech_ai",
        name="Tech & AI",
        slug="tech-ai",
        description="A space to share, learn and build together. Be kind, be curious.",
        category=RoomCategory.TECH,
        icon="💻",
        member_count=482,
        created_by=neha.id,
    )
    art_room = Room(
        id="rm_art_creators",
        name="Art & Creators",
        slug="art-creators",
        description="Show your work-in-progress, trade techniques, find collaborators.",
        category=RoomCategory.ART,
        icon="🎨",
        member_count=311,
        created_by=kiara.id,
    )
    local_room = Room(
        id="rm_local_nearby",
        name="Hitech City Locals",
        slug="hitech-city-locals",
        description="Meetups, courts, and recommendations around Hitech City.",
        category=RoomCategory.LOCAL,
        icon="📍",
        member_count=156,
        created_by=arjun.id,
    )
    for room in (tech_room, art_room, local_room):
        await rooms_repo.create_room(room)
    for room_id in (tech_room.id, art_room.id, local_room.id):
        await rooms_repo.join_room(room_id, arjun.id)
        await rooms_repo.join_room(room_id, neha.id)

    await rooms_repo.add_message(
        RoomMessage(
            id="msg_seed_1",
            room_id=tech_room.id,
            author_id=neha.id,
            text="Just finished setting up a local LLM with Ollama. The performance is awesome!",
        )
    )
    await rooms_repo.add_message(
        RoomMessage(
            id="msg_seed_2",
            room_id=tech_room.id,
            author_id=arjun.id,
            text="That's great! Mind sharing your setup?",
        )
    )
    await rooms_repo.add_message(
        RoomMessage(
            id="msg_seed_3",
            room_id=local_room.id,
            author_id=arjun.id,
            text="Anyone up for a badminton session this weekend? Found a great court near "
            "Hitech City. All skill levels welcome!",
        )
    )

    # A document drop in the tech room: the setup guide as a PDF card plus a
    # snapshot of the rig, with a couple of reactions riding on the documents
    # (Foxy sticker + emoji) so the previews don't render bare.
    await rooms_repo.add_message(
        RoomMessage(
            id="msg_seed_4",
            room_id=tech_room.id,
            author_id=neha.id,
            text="Full write-up of the Ollama setup — model choices, quant settings, everything:",
            attachments=[
                MessageAttachment(
                    id="att_seed_1",
                    kind="document",
                    name="local-llm-setup-guide.pdf",
                    size=1_874_432,
                    mime="application/pdf",
                ),
                MessageAttachment(
                    id="att_seed_2",
                    kind="image",
                    name="rig-photo.png",
                    size=482_560,
                    mime="image/png",
                    value="emoji_foxy_good_job",
                ),
            ],
            reactions=[
                MessageReaction(kind="emoji", value="🔥", user_id=arjun.id),
                MessageReaction(kind="sticker", value="costume_wizard", user_id=arjun.id),
            ],
        )
    )

    # -- Shop (Art & Handmade category) ------------------------------------
    kiara_seller = Seller(
        id="sel_kiara",
        user_id=kiara.id,
        display_name="artbykiara",
        handle="@artbykiara",
        specialty="Handmade Decor",
        bio="Light finds a home everywhere.",
        followers_count=2140,
    )
    aria_seller = Seller(
        id="sel_aria",
        user_id="usr_aria",
        display_name="Aria Khan",
        handle="@ariakhan",
        specialty="Paintings",
        bio="Colour, mood, and a lot of coffee.",
        followers_count=1870,
    )
    await shop_repo.seed_seller(kiara_seller)
    await shop_repo.seed_seller(aria_seller)

    lamp = Product(
        id="prd_wooden_lamp",
        seller_id=kiara_seller.id,
        title="Handcrafted Wooden Lamp",
        description="Sculpted from reclaimed teak, warm ambient glow.",
        category=ShopCategory.ART_AND_HANDMADE,
        condition=ProductCondition.HANDMADE,
        price_minor_units=2_499_00,
        currency="INR",
        image_urls=[],
    )
    sunset = Product(
        id="prd_sunset_horizons",
        seller_id=aria_seller.id,
        title="Sunset Horizons",
        description="Acrylic on canvas, 24x36in, framed.",
        category=ShopCategory.ART_AND_HANDMADE,
        condition=ProductCondition.NEW,
        price_minor_units=8_000_00,
        currency="INR",
        image_urls=[],
    )
    lantern = Product(
        id="prd_leaf_lantern",
        seller_id=kiara_seller.id,
        title="Folded Leaf Lantern",
        description="Laser-cut layered wood, battery LED insert included.",
        category=ShopCategory.ART_AND_HANDMADE,
        condition=ProductCondition.HANDMADE,
        price_minor_units=1_899_00,
        currency="INR",
        image_urls=[],
    )
    for product in (lamp, sunset, lantern):
        await shop_repo.seed_product(product)

    # -- Social -----------------------------------------------------------
    await social_repo.create_post(
        Post(
            id="pst_seed_1",
            author_id=kiara.id,
            text="Turning scraps into stories. Handmade lighting, now live on Phlio Shop ✨",
            tags=["phlioshop", "handmade", "sustainable"],
            created_at=now - dt.timedelta(hours=2),
        )
    )
    await social_repo.create_post(
        Post(
            id="pst_seed_2",
            author_id=arjun.id,
            text="Anyone up for a badminton session this weekend? All skill levels welcome!",
            tags=["local", "sports"],
            created_at=now - dt.timedelta(hours=5),
        )
    )
    await social_repo.create_post(
        Post(
            id="pst_seed_3",
            author_id=neha.id,
            text="Local LLMs are getting genuinely good. Ask me anything in #tech-ai.",
            tags=["tech", "ai"],
            created_at=now - dt.timedelta(hours=8),
        )
    )

    # -- Book listings (echo the reference Agent plan: movie → dinner →
    # -- hangout, plus a local activity) ------------------------------------
    book_repo = container.book_repository
    sat_7pm = now.replace(hour=19, minute=0, second=0, microsecond=0)
    listings = [
        BookListing(
            id="bl_movie_kingdom",
            title="Movie: Kingdom",
            category=BookCategory.ENTERTAINMENT,
            venue="PVR Nexus",
            location_note="7:00 PM show",
            description="Prime-time screening, recliner seats available.",
            price_min_minor_units=1_200_00,
            price_max_minor_units=1_500_00,
            duration_label="~3h",
            rating=4.6,
            starts_at=sat_7pm,
            tags=["movie", "weekend"],
        ),
        BookListing(
            id="bl_dinner_courtyard",
            title="Dinner: The Courtyard",
            category=BookCategory.MEET,
            venue="The Courtyard",
            location_note="1.5 km from PVR",
            description="Alfresco dinner, great for groups.",
            price_min_minor_units=1_800_00,
            price_max_minor_units=2_200_00,
            duration_label="~2h",
            rating=4.7,
            tags=["dinner", "group"],
        ),
        BookListing(
            id="bl_hangout_brewboard",
            title="Post-movie hangout",
            category=BookCategory.MEET,
            venue="Brew & Board (Café)",
            location_note="Great for late-night chats",
            description="Board games, brews and bites.",
            price_min_minor_units=450_00,
            price_max_minor_units=700_00,
            duration_label="~1.5h",
            rating=4.4,
            tags=["cafe", "games"],
        ),
        BookListing(
            id="bl_badminton_court",
            title="Badminton Court · Hitech City",
            category=BookCategory.SPORTS_AND_ACTIVITIES,
            venue="Smash Arena",
            location_note="Near Hitech City metro",
            description="Wooden court, all skill levels welcome.",
            price_min_minor_units=300_00,
            price_max_minor_units=300_00,
            duration_label="1h slot",
            rating=4.5,
            tags=["sports", "morning"],
        ),
        BookListing(
            id="bl_sunrise_walk",
            title="Sunrise Walk & Chai Meetup",
            category=BookCategory.MEET,
            venue="KBR Park",
            location_note="Free · every weekend",
            description="Guided walking group, chai on the house.",
            price_min_minor_units=0,
            price_max_minor_units=0,
            duration_label="1.5h",
            rating=4.8,
            is_free=True,
            tags=["free", "morning"],
        ),
    ]
    for listing in listings:
        await book_repo.seed_listing(listing)

    # A sample confirmed booking so "My Bookings" isn't empty for Arjun.
    await book_repo.create_booking(
        Booking(
            id="bkg_seed_1",
            user_id=arjun.id,
            listing_id="bl_badminton_court",
            title="Badminton Court · Hitech City",
            venue="Smash Arena",
            date=(now + dt.timedelta(days=2)).date(),
            time=dt.time(18, 30),
            participants=4,
            estimated_total_min_minor_units=300_00,
            estimated_total_max_minor_units=300_00,
        )
    )

    # -- Pay (simulated wallet for the demo user) ----------------------------
    pay_repo = container.pay_repository
    await pay_repo.seed_wallet(
        Wallet(user_id=arjun.id, balance_minor_units=4_280_50, upi_handle="arjun@phlio")
    )
    for txn in (
        Transaction(
            id="txn_seed_1",
            user_id=arjun.id,
            type=TransactionType.RECEIVE,
            counterparty="Neha Kapoor",
            amount_minor_units=650_00,
            note="Your share for dinner 😄",
            created_at=now - dt.timedelta(hours=26),
        ),
        Transaction(
            id="txn_seed_2",
            user_id=arjun.id,
            type=TransactionType.SEND,
            counterparty="Kiara Mehta",
            amount_minor_units=2_499_00,
            note="Handcrafted Wooden Lamp",
            created_at=now - dt.timedelta(days=3),
        ),
        Transaction(
            id="txn_seed_3",
            user_id=arjun.id,
            type=TransactionType.SEND,
            counterparty="Smash Arena",
            amount_minor_units=300_00,
            note="Badminton court booking",
            created_at=now - dt.timedelta(days=5),
        ),
    ):
        await pay_repo.seed_transaction(txn)

    # -- Activity feed --------------------------------------------------------
    activity_repo = container.activity_repository
    for item in (
        ActivityItem(
            id="act_seed_1",
            user_id=arjun.id,
            kind=ActivityKind.BOOK,
            title="Booking confirmed 🎾",
            body="Badminton Court · Smash Arena, 6:30 PM in 2 days.",
            icon="🎟️",
            ref_id="bkg_seed_1",
            created_at=now - dt.timedelta(hours=1),
        ),
        ActivityItem(
            id="act_seed_2",
            user_id=arjun.id,
            kind=ActivityKind.PAY,
            title="Neha sent you ₹650",
            body="Your share for dinner 😄",
            icon="💸",
            ref_id="txn_seed_1",
            created_at=now - dt.timedelta(hours=26),
        ),
        ActivityItem(
            id="act_seed_3",
            user_id=arjun.id,
            kind=ActivityKind.SOCIAL,
            title="Kiara posted in Art & Creators",
            body='"Turning scraps into stories…" — see what she made.',
            icon="✨",
            created_at=now - dt.timedelta(hours=30),
        ),
        ActivityItem(
            id="act_seed_4",
            user_id=arjun.id,
            kind=ActivityKind.AGENT,
            title="Foxy has a plan idea",
            body="A fun Saturday within ₹4,000 — movie, dinner and a hangout.",
            icon="🦊",
            created_at=now - dt.timedelta(hours=40),
        ),
    ):
        await activity_repo.seed_item(item)

    logger.info(
        "seed.completed users=3 rooms=3 products=3 sellers=2 posts=3 "
        "listings=5 bookings=1 wallet=1 transactions=3 activity=4",
    )
