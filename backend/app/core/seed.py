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
from app.domains.identity.entities import User
from app.domains.rooms.entities import Room, RoomCategory, RoomMessage
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

    logger.info(
        "seed.completed users=3 rooms=3 products=3 sellers=2 posts=3",
    )
