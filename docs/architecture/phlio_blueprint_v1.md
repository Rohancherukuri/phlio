# Phlio — Final Product, Architecture & Growth Blueprint

**Version:** 2.0  
**Date:** 20 September 2026  
**Status:** Product strategy + production architecture draft  
**Primary market:** India-first, globally extensible

> **People. Places. Possibilities.**

---

## 1. Executive Summary

Phlio is a unified consumer platform designed to connect **social interaction, communities, payments, commerce, bookings, entertainment, news, and real-world experiences** through one identity and one intelligent orchestration layer.

The central idea is not to place copies of Instagram, Discord, Amazon, a payments app, an OTT platform, and a booking app inside one application. Phlio is differentiated by making the **objects and actions from those domains interoperable**.

A user can discover something in Social, discuss it in Rooms, buy it in Shop, book an experience through Book, pay through Pay, watch or listen through Stream, read contextual news through News, and let the Phlio Agent coordinate the workflow.

The earlier architecture blueprint established the core intent-driven principle: Phlio should connect capabilities around what the user wants to accomplish rather than requiring users to manually switch between applications. The original blueprint also established the modular-monolith approach, FastAPI backend, SurrealDB/Redis/Meilisearch data layer, separate AI service, and selective Rust core. This document keeps those principles while updating the product domains and naming based on the latest product decisions.

### Core product loop

```text
Discover
   ↓
Understand
   ↓
Share / Note / Discuss
   ↓
Plan
   ↓
Book / Buy / Watch / Listen
   ↓
Pay
   ↓
Experience
   ↓
Capture
   ↓
Share / Remix
   ↓
Discover again
```

### Product thesis

> **Phlio should feel like one product to the user while behaving like a modular platform underneath.**

The most important architectural concept is the **Phlio Object**. A product, movie, song, event, booking, place, news story, Click, Scene, Experience, Room, or payment request can be referenced and moved through the Phlio ecosystem without duplicating the underlying object.

---

# 2. What Phlio Is — and What It Is Not

## Phlio is

A consumer platform where people can:

- express themselves;
- build and join communities;
- communicate one-to-one and in groups;
- discover products, entertainment, news, people, places, and experiences;
- buy and sell products;
- book entertainment, transport, services, travel, and meetups;
- send and receive money;
- consume video and audio entertainment;
- create collaborative memories and Experiences;
- use an AI agent to coordinate cross-domain tasks;
- use a common security and trust layer across the ecosystem.

## Phlio is not

- a collection of unrelated mini-apps;
- an AI chatbot with every capability hidden behind one prompt;
- a replacement for regulated payment, banking, brokerage, healthcare, or other licensed infrastructure;
- a social feed where every other domain is forced into the same UI;
- an unlimited file-storage system inside Social;
- an autonomous financial agent that can spend money without explicit authorization;
- a news publisher that decides what users should politically believe.

---

# 3. Final Phlio Domain Map

Phlio's current top-level consumer domains are intentionally limited to **eight**:

```text
PHLIO
│
├── 1. PHLIO PAY
│      Money & financial actions
│
├── 2. PHLIO SOCIAL
│      Personal social identity, publishing & communication
│
├── 3. PHLIO ROOMS
│      Communities, servers, spaces & group interaction
│
├── 4. PHLIO BOOK
│      Experiences, reservations, mobility, services & travel
│
├── 5. PHLIO SHOP
│      Commerce & marketplace
│
├── 6. PHLIO STREAM
│      Video + audio entertainment
│
├── 7. PHLIO NEWS
│      News discovery, source context & community notes
│
└── 8. PHLIO AGENT
       Cross-domain manager + intelligence + security layer
```

### Cross-platform primitives

These are **not separate top-level platforms**:

```text
Phlio Object       → universal reference model
Phlio Note         → contextual sharing object
Clicks             → photo-first Social content
Scenes             → short-form immersive Social content
Moments            → individual/personal memories
Experiences        → collaborative multimedia memory/timeline
Comments           → discussion attached to content
Stickers           → reusable visual reactions/media
Collections/Stacks → cross-domain curation
```

### Platform capabilities rather than consumer domains

```text
Identity
Search
Notifications
Media processing
File storage
Delivery/fulfillment
Recommendations
Trust & Safety
Analytics
Observability
External integrations
```

These capabilities power multiple domains rather than becoming separate consumer destinations.

---

# 4. Phlio Pay

## Purpose

**Phlio Pay = transact.**

Pay is the financial infrastructure users can access from anywhere in Phlio, not just a standalone payment screen.

```text
PHLIO PAY
│
├── Send Money
├── Receive Money
├── UPI / payment-rail integrations
├── QR Scan & Pay
├── Merchant Payments
├── Payment Requests
├── P2P Transfers
├── Group / Split Payments
├── Bills & Recharge
│   ├── Electricity
│   ├── Water
│   ├── Gas
│   ├── Mobile
│   ├── Broadband
│   ├── DTH
│   └── Other supported billers
├── Transaction History
├── Statements / Receipts
├── Refunds
├── Recurring Payments
├── Financial Insights
├── Investments
│   ├── Stocks
│   └── Mutual Funds
└── Offline-payment capability where legally and technically supported
```

## Pay everywhere

```text
Social → Pay
Rooms → Pay
Book → Pay
Shop → Pay
Note → Payment Trigger → Pay
```

## Chat payment

A Social conversation can contain a QR or supported payment object. Phlio may detect the payment object and present the payment flow, but it must **not silently execute a transaction**.

```text
QR / payment object
      ↓
Detect / parse
      ↓
Show payee
      ↓
Show amount if present
      ↓
User reviews
      ↓
Authentication / authorization
      ↓
Payment provider / rail
      ↓
Confirmation
```

## Payment trigger inside Phlio Note

A Note may contain a payment trigger such as:

> "Your share for dinner 😂"

> ₹750

> **[Review Payment]**

The trigger opens the relevant Phlio Pay payment portal. It **does not perform the transaction**. The user must explicitly confirm and authorize the payment.

## Offline payment

Offline payments are a specialized, regulated feature. A future implementation may involve secure local credentials/tokens, device-to-device protocols, transaction limits, replay protection, double-spend controls, later reconciliation, and provider/regulatory constraints.

Do not build an unrestricted private-money system by exchanging locally generated balances.

## Financial safety boundary

AI can explain, prepare, detect, classify, and recommend. It should not independently authorize high-impact financial actions.

Actual financial execution should sit behind:

```text
Agent
 ↓
Proposed action
 ↓
Policy engine
 ↓
User confirmation when required
 ↓
Authentication / authorization
 ↓
Deterministic payment execution
```

Real-money payments, brokerage, mutual funds, bill-payment rails, and related financial products must be implemented through the appropriate regulated partners, licenses, payment rails, and compliance processes for the markets in which Phlio operates.

---

# 5. Phlio Social

## Purpose

**Phlio Social = personal social identity + publishing + lightweight communication.**

The product combines visual social content, public conversation, short-form video, live interaction, direct messaging, calls, creative profiles, and cross-domain content sharing.

### Social structure

```text
PHLIO SOCIAL
│
├── Home Feed
│   ├── Following
│   ├── For You
│   └── Friends / relevant activity surfaces
│
├── Clicks
│   └── Instant photo-first content
│
├── Scenes
│   └── Short-form immersive content
│
├── Stories
│
├── Live
│
├── Discover
│   ├── Creators
│   ├── Topics
│   ├── Trending
│   └── Cross-Phlio discovery
│
├── Messages
│   ├── DMs
│   ├── Group Chats
│   ├── Voice Messages
│   ├── Images
│   ├── Videos
│   ├── GIFs
│   └── Phlio Objects / Notes
│
├── Calls
│   ├── Audio
│   ├── Video
│   └── Group Calls
│
└── Profile
    ├── Posts / Clicks / Scenes
    ├── Moments
    ├── Experiences
    ├── Saved
    └── Custom identity
```

## Clicks

**Clicks** are Phlio's instant photo-first content format, captured directly through the Phlio camera.

A Click can support:

- photo;
- caption;
- tags;
- location;
- music where licensing/feature rules allow;
- comments;
- reactions;
- Add Note;
- sharing;
- saving;
- custom stickers/effects where supported.

The key identity is:

> **Click = instant visual capture and sharing.**

## Scenes

**Scenes** are the working name for the short-form immersive content format that replaces a direct copy of the word “Reel.”

A Scene can support:

- short video;
- multiple visual elements;
- music/audio;
- captions;
- filters/effects;
- stickers;
- tags;
- locations;
- Phlio Object attachments;
- Notes;
- comments;
- sharing and remixing.

> **Click = photo. Scene = short-form visual story.**

The naming can still be revisited during brand testing, but “Scene” is preferred here because it is broad enough to evolve beyond a simple Reels clone.

## Live

```text
PHLIO LIVE
├── Solo Live
├── Guest Live
├── Multi-guest Live
├── Group Live
├── Live Chat
├── Reactions
├── Polls
├── Q&A
└── Replay where supported
```

## Audio and video calls

Social supports one-to-one and group calling.

```text
DM
├── Audio Call
├── Video Call
└── Group Call
```

DM calls may eventually support:

- voice/video;
- screen sharing;
- reactions;
- call recording only where legally/technically supported and explicitly disclosed;
- noise suppression;
- optional transcription;
- shared media;
- camera filters/effects.

## Camera-first DM creation

Inside a Social DM, users can open the Phlio Camera and create temporary media with:

- Snapchat-like effects;
- filters;
- custom stickers;
- user-created sticker overlays;
- GIFs;
- voice messages;
- photos/videos.

A sticker can serve as a visual base and camera effects can be rendered over it or around it. This is specifically a **DM/camera feature**, not a reason to turn the public comment system into a full media editor.

---

# 6. Phlio Social Comments vs DMs

These are intentionally different systems.

## Comments under content

Comments belong to the content object.

Supported lightweight content:

- text;
- emoji;
- GIF;
- image;
- Phlio Sticker;
- custom sticker;
- mentions;
- reactions.

The comment section should remain fast and readable.

## DMs / Chat

Private conversations can be richer:

- text;
- voice messages;
- images;
- video;
- GIFs;
- stickers;
- custom stickers;
- camera effects;
- Phlio Notes;
- Phlio Objects;
- payment triggers;
- audio/video calls.

### Boundary

> **Comment = discussion attached to content.**  
> **DM = private interpersonal communication.**

---

# 7. Social Profile Customization

Phlio profiles are designed as **personal spaces**, not only a grid of posts.

Users can optionally customize:

- profile color;
- background;
- accent color;
- typography within controlled design-system limits;
- profile music;
- animations;
- avatar treatment;
- featured Experience;
- Moments collections;
- selected links and identity details.

The implementation should remain performance-aware and accessible. Customization should not allow a profile to become unusable on lower-end devices.

---

# 8. Phlio Rooms

## Purpose

**Phlio Rooms = communities + organized group communication.**

It combines the useful primitives of Discord, Reddit, X-style public conversation, and large-file/community communication without making every concept identical.

## Core hierarchy

```text
Phlio Rooms
   ↓
Community
   ↓
Server
   ↓
Space
   ↓
Channel
   ↓
Post / Message
   ↓
Thread
```

### Community

The **public-facing topic or interest identity**.

Example:

> Indian Gaming

A Community is what people discover and follow.

### Server

The **organized group environment** where members operate.

Example:

> Indian Gaming Official

A Server manages membership, roles, permissions, moderation, and Spaces.

### Space

A **functional/topic area** inside a Server.

Example:

> PC Gaming Space

A Space groups related interaction modes around a purpose.

### Channel

The **specific communication surface** within a Space.

Example:

> #hardware

Channels can be:

- text;
- forum;
- voice;
- video;
- media;
- file;
- stage;
- streaming/live interaction.

### Thread

A focused conversation attached to a post/message inside a Channel.

## Example

```text
COMMUNITY: Indian Gaming
   ↓
SERVER: Indian Gaming Official
   ↓
SPACE: PC Gaming
   ├── #general
   ├── #hardware
   ├── #game-news
   ├── #recommendations
   ├── 🔊 Voice Lounge
   └── 🎥 Watch Party
```

## Public/private controls

Communities, Servers, and Spaces can support appropriate visibility models such as:

- public;
- private;
- invite-only;
- restricted;
- role-based;
- contributor/moderator-only.

## Rooms capabilities

- posts;
- threaded discussions;
- real-time chat;
- voice channels;
- video rooms;
- screen sharing;
- streaming;
- polls;
- roles;
- permissions;
- moderation;
- community discovery;
- announcements;
- community events;
- large-file sharing;
- searchable resources;
- temporary spaces;
- online meetings.

## Large file model

Rooms intentionally supports heavier files than Social, similar to the role Telegram/Discord communities can play.

Potential supported formats include:

- image;
- audio;
- video;
- GIF;
- PDF;
- DOC/DOCX;
- XLS/XLSX;
- PPT/PPTX;
- CSV;
- JSON;
- ZIP;
- code/text files;
- other explicitly supported formats.

Exact file limits are infrastructure, abuse, storage-cost, and security decisions and should not be hard-coded into product doctrine prematurely.

### Boundary

> **Social = public/personal publishing + interpersonal communication.**  
> **Rooms = persistent communities + group interaction + heavyweight communication.**

---

# 9. Phlio Book

## Purpose

**Phlio Book = reserve, schedule, rent, hire, attend, travel, or experience something.**

The key boundary is:

> **Shop = acquire products.**  
> **Book = acquire access to an experience/service/transport/venue/time slot.**

## Categories

```text
PHLIO BOOK
│
├── Entertainment
│   ├── Movies
│   ├── Shows
│   ├── Concerts
│   ├── Festivals
│   ├── Theatre
│   └── Comedy / other events
│
├── Sports & Activities
│   ├── Badminton
│   ├── Football
│   ├── Cricket
│   ├── Tennis
│   ├── Swimming
│   ├── Gyms / Classes
│   ├── Bowling
│   ├── Adventure
│   └── Other activities
│
├── Mobility
│   ├── Cabs
│   ├── Auto / bike taxi
│   ├── Bike rental
│   ├── Scooter rental
│   ├── Car rental
│   └── Other transport integrations
│
├── Services
│   ├── Cleaning
│   ├── Plumbing
│   ├── Electrical
│   ├── Appliance repair
│   ├── Beauty / salon
│   ├── Photography
│   ├── Tutors
│   └── Professional services
│
├── Meet
│   ├── Date
│   ├── Walk & Talk
│   ├── Coffee
│   ├── Dinner
│   ├── Movie Date
│   ├── Activity Date
│   ├── Group Hangout
│   └── Nearby places / free places
│
├── Travel
│   ├── Flights
│   ├── Hotels
│   ├── Trains
│   ├── Buses
│   ├── Vacation packages
│   ├── Attractions
│   ├── Tours
│   └── Travel activities
│
└── My Bookings
```

## Meet

Meet is intentionally a **Book category**, not a standalone social network.

It helps users discover places and activities suitable for meeting people in real life.

Use cases include:

- first dates;
- coffee dates;
- dinner dates;
- movie dates;
- sports dates;
- Walk & Talk;
- outdoor meetups;
- group hangouts;
- activity-based meetings.

The distinction is:

```text
Social → who you interact with
Rooms  → which group/community you belong to
Book → where/what you experience together
Pay → how the transaction is completed
```

### Free experiences

Meet and Book do not imply that every destination costs money.

Discovery can include:

- parks;
- public spaces;
- tourist destinations;
- walking routes;
- free events;
- museums/places with free entry periods;
- community activities.

The UI should support **Free** as a first-class budget filter.

## Booking abstraction

All Book subdomains should use a shared booking abstraction:

```text
Booking
├── Customer
├── Provider
├── Experience / Service / Vehicle / Ticket
├── Date
├── Time
├── Location
├── Participants
├── Price
├── Payment
├── Cancellation policy
├── Confirmation
└── Status
```

This allows the same backend mechanics to power a movie ticket, badminton court, hotel, cab, bike rental, home service, or date experience.

---

# 10. Phlio Shop

## Purpose

**Phlio Shop = universal marketplace + local/quick commerce.**

The product combines broad catalog commerce with local availability and speed-sensitive fulfillment.

```text
PHLIO SHOP
│
├── Fashion
│   ├── Shirts
│   ├── T-Shirts
│   ├── Pants
│   ├── Jeans
│   ├── Dresses
│   ├── Shoes
│   └── Accessories
│
├── Food & Grocery
├── Pharma & Wellness
├── Electronics
├── Home & Living
├── Art & Handmade
├── Sports & Fitness
├── Books & Education
├── Beauty & Personal Care
├── Toys & Games
├── Automotive
├── Pet Supplies
├── Digital Products
└── More categories
```

## Art is a Shop category

There is no separate top-level Phlio Art domain in the current architecture.

```text
Phlio Shop
   ↓
Art & Handmade
```

The category can include:

- paintings;
- sculptures;
- handmade decor;
- woodwork;
- metalwork;
- ceramics;
- handmade jewelry;
- 3D-printed objects;
- digital art;
- prints;
- photography;
- custom commissions;
- collectibles.

Artists can have storefronts, portfolios, product listings, and social creator identities.

## Marketplace roles

Phlio Shop supports:

- brands;
- retailers;
- local shops;
- creators;
- artists;
- small businesses;
- individual sellers where supported.

## Product lifecycle

```text
Discover
  ↓
Product page
  ↓
Save / Compare / Share / Add Note
  ↓
Cart or Buy Now
  ↓
Checkout
  ↓
Phlio Pay
  ↓
Order
  ↓
Fulfillment
  ↓
Delivery
  ↓
Return / Refund / Review
```

## Fulfillment types

A product can have a fulfillment profile such as:

- standard marketplace fulfillment;
- local delivery;
- rapid/quick-commerce fulfillment;
- made-to-order;
- custom manufacturing;
- scheduled delivery.

Delivery ETA can factor in:

- inventory location;
- seller location;
- customer area;
- seller processing time;
- fulfillment mode;
- distance;
- courier capacity;
- operational disruptions;
- inventory availability.

The displayed ETA should be a **range/estimate**, not an unqualified promise.

## Deals

- flash deals;
- daily deals;
- bundles;
- buy-more-save-more;
- local deals;
- creator offers;
- seasonal campaigns;
- personalized price alerts.

## Used / new / handmade

Where applicable:

- new;
- like new;
- good;
- used;
- refurbished;
- handmade;
- custom made.

## Social commerce

A Product can be referenced from:

- Clicks;
- Scenes;
- Live streams;
- Rooms;
- Notes;
- Experiences.

---

# 11. Phlio Stream

## Purpose

**Phlio Stream = video + audio entertainment consumption.**

It is not simply an OTT service. It combines a streaming-video catalog with music, podcasts, audio stories, audiobooks where licensed, and live entertainment.

```text
PHLIO STREAM
│
├── Video
│   ├── Movies
│   ├── Web Series
│   ├── TV Shows
│   ├── Anime
│   ├── Cartoons
│   ├── Documentaries
│   ├── Originals
│   └── Kids
│
├── Music
│   ├── Songs
│   ├── Albums
│   ├── Artists
│   ├── Playlists
│   └── Music Videos
│
├── Audio
│   ├── Podcasts
│   ├── Audio podcasts
│   ├── Audio stories
│   ├── Audiobooks where licensed
│   └── Talk shows
│
├── Live
│   ├── Live sports
│   ├── Concerts
│   ├── Live shows
│   └── Other licensed live events
│
└── My Stream
    ├── Continue Watching
    ├── Continue Listening
    ├── Watchlist
    ├── Likes
    ├── Playlists
    ├── History
    └── Downloads where supported
```

## Stream object sharing

Every Stream object can be:

- saved;
- shared;
- recommended;
- tagged to users;
- attached to a Note;
- discussed in a Room;
- added to an Experience.

Example:

> @Alex — “You HAVE to watch this 😂”

The shared item is a native Stream object, and clicking it opens the appropriate Stream page.

## Stream + Rooms

Potential experiences:

- Watch Party;
- Listening Party;
- Live Sports Room;
- Podcast discussion;
- community screening.

The Stream service owns playback/content delivery; Rooms owns group interaction.

## Stream + Book

Where licensing and provider integrations support it:

```text
Movie
├── Watch on Stream
└── Attend in person → Book
```

A concert or live event can similarly have:

```text
Watch Live → Stream
Attend → Book
```

---

# 12. Phlio News

## Purpose

**Phlio News = compact news discovery + source context + community fact-checking.**

The product should remain intentionally simpler than Social and Rooms.

```text
PHLIO NEWS
│
├── Home
├── Trending
├── India
├── World
├── Business
├── Technology
├── Science
├── Sports
├── Entertainment
├── Politics
├── Culture
└── Saved
```

Each story provides:

- image/video;
- headline;
- short summary;
- source list;
- publication time;
- source perspective information;
- community notes where available;
- link to original source.

## Source perspective

The product may visualize the political orientation of **sources covering a story**, using a transparent methodology and preferably independent assessments.

For example:

```text
Source distribution

Left ───────── Center ───────── Right
      ██████░████████░████
```

The UI should avoid implying that a left/center/right source label is itself a factuality verdict. Bias/orientation and factual reliability are separate dimensions.

Ground News is a direct reference for this product pattern: it groups coverage of the same story, provides publisher-level bias/factuality context, and visualizes the distribution of sources across the political spectrum. citeturn648385search0turn648385search4turn648385search10

## Community Notes

Phlio News can support a Community Notes-style evidence layer for claims that may need context or correction.

A note should:

- identify a specific claim;
- provide evidence/source links;
- explain the relevant context;
- distinguish verified facts from interpretation;
- avoid turning disagreement into a factual correction.

The Phlio Agent may assist with source retrieval, duplicate detection, claim extraction, and evidence organization. Human/community review should remain important.

## News boundary

News should not become another social feed. Discussion can move into **Phlio Rooms**.

```text
News story
   ↓
Discuss
   ↓
Relevant Phlio Room / Space
```

---

# 13. Phlio Agent

## Purpose

**Phlio Agent = cross-domain manager + intelligence layer + security assistant.**

It is represented by the Phlio fox and acts as a contextual companion rather than a generic chatbot.

The Agent's job is to understand **intent**, identify which domains are required, prepare actions, execute permitted low-risk tasks, and request confirmation where needed.

### Example

> “Plan a Saturday evening for four friends under ₹5,000.”

```text
Intent
 ↓
Preferences / context
 ↓
Book: activities / restaurants / movies
 ↓
Rooms: group conversation / coordination
 ↓
Shop: required products if relevant
 ↓
Pay: prepare split / checkout
 ↓
Experience: create shared plan
 ↓
Notifications
```

## Agent architecture

```text
User
 ↓
Intent Understanding
 ↓
Context Retrieval
 ↓
Planner
 ↓
Supervisor
 ↓
Specialized Agent / Tool
 ↓
Policy Validation
 ↓
Execution
 ↓
Verification
 ↓
Response / UI state
```

## Specialized capabilities

- Social assistance
- Rooms assistance
- Shop assistant
- Book assistant
- Stream discovery
- News summarization/context
- Payment assistance
- Travel planning
- Recommendation
- Search
- Memory
- Notification prioritization
- Security investigation
- Safety/moderation assistance

## Agent as security layer

The Agent can assist with:

- scam detection;
- suspicious links;
- suspicious QR/payment requests;
- account takeover signals;
- suspicious seller behavior;
- malicious-file warnings;
- community safety;
- moderation assistance.

But the LLM should **not be the final authority for high-impact security or financial decisions**. Deterministic policy engines, authorization controls, human review paths, and domain-specific systems remain authoritative.

---

# 14. Phlio Object Model

The **Phlio Object** is one of the most important platform primitives.

```text
Phlio Object
│
├── Product
├── Movie
├── Series
├── Song
├── Podcast
├── News Story
├── Event
├── Place
├── Booking
├── Room
├── Community
├── Post
├── Click
├── Scene
├── Moment
├── Experience
└── Payment Request
```

A Phlio Object has:

- object ID;
- object type;
- owner/domain;
- canonical URL/deep link;
- visibility;
- permissions;
- metadata;
- lifecycle status.

Any other domain can **reference** the object without copying its underlying data.

### Example

```text
Shop Product
   ↓
Phlio Note
   ↓
Social DM
   ↓
Tap object
   ↓
Open canonical Shop product
```

This design reduces duplication and creates a consistent cross-platform architecture.

---

# 15. Phlio Note

## Definition

> **Phlio Note is a contextual sharing object attached to a Phlio Object.**

It is not another feed and does not inherently belong to Social or Rooms.

A Note can contain:

- message;
- tagged users;
- image;
- GIF;
- audio;
- emoji/reactions;
- location;
- music snippet;
- payment trigger;
- referenced Phlio Object;
- visibility;
- expiration.

## Music attachment

A Note can attach a music snippet of **up to 30 seconds** from supported sources such as:

- Phlio Stream;
- Spotify through supported mechanisms;
- user's permitted local audio.

Phlio should not extract/re-host Spotify audio. External music integrations should comply with the provider's official API/SDK, playback, licensing, and sharing requirements.

## Note lifetime

Users can choose:

- 24 hours;
- 7 days;
- 30 days;
- custom;
- until deleted.

The underlying Phlio Object remains even after the Note expires.

## Note visibility

Potential destinations:

```text
👤 People
    → send individually to selected users

👥 Group Chat
    → existing private group conversation

🏠 Phlio Rooms
    → existing Server/Space or create a new one

🌎 Public Social
    → explicit conversion/public publication when supported
```

The product should not infer that “several tagged users” means Rooms. A user deliberately chooses the delivery context.

## Shop example

```text
Phlio Shop
   ↓
Product
   ↓
Share
   ↓
Add Note
   ↓
“Bro 😂 should I buy this?”
   + GIF
   + 30-sec music
   + tags
   ↓
Send Note
   ├── selected people individually
   ├── group chat
   └── Phlio Room / Space
```

## Payment trigger

A Note may contain:

> **₹750 — Review Payment**

Clicking it opens **Phlio Pay**. It does not execute the transaction.

### Boundary

> **A Note is communication around an object, not a new copy of the object.**

---

# 16. Phlio Comments and Stickers

## Comments

Comments are attached to Social/other content and support lightweight reactions:

- text;
- emojis;
- GIFs;
- images;
- stickers;
- custom stickers;
- mentions;
- reactions.

## Sticker system

Users can:

- save stickers;
- favorite stickers;
- organize sticker collections;
- create stickers from local images;
- cut out subjects/backgrounds;
- add text/effects;
- create animated stickers/GIFs where supported;
- reuse stickers in comments and DMs.

### Comment creation bar

```text
Comment...

😀  GIF  🖼️  ✨Create  ➤
```

The Create tool can support a native Phlio workflow inspired by visual-cutout/collage tooling:

```text
Image
 ↓
Subject cutout
 ↓
Text / effects
 ↓
Sticker
 ↓
Save to sticker library
```

Pinterest's current visual-search system includes object-level search and cutout-to-collage capabilities, which are useful references for this interaction pattern. citeturn193997search1

Where third-party integrations are used, such as GIPHY, use official APIs and licensing/attribution requirements rather than scraping.

---

# 17. Phlio Moments

## Definition

**Moment = individual memory/highlight.**

A Moment can contain:

- Clicks;
- Scenes;
- photos;
- videos;
- audio;
- music;
- text;
- location;
- dates;
- tags;
- descriptions;
- Phlio Objects.

Moments can be grouped into profile collections and used in Experiences.

The user can explicitly allow Book context to suggest metadata such as a visited venue or trip, but location information should never be published automatically without the user's permission.

---

# 18. Phlio Experience

## Definition

> **Experience = a multimedia, chronological, optionally collaborative story built from Moments and other Phlio Objects.**

Experience is deliberately different from Instagram Stories/Highlights.

### Story

Short-lived update.

### Moment

One memory.

### Experience

A longer-lived, editable, collaborative story.

## Experience components

```text
Experience
│
├── Cover / Poster
├── Title
├── Description
├── Timeline
├── Moments
├── Clicks
├── Scenes
├── Video
├── Audio
├── Music
├── GIFs
├── Stickers
├── Text
├── Posters
├── Effects
├── Transitions
├── Locations
├── User Tags
├── Phlio Notes
├── Phlio Objects
└── Contributors
```

## Editing

Experience can include:

- transitions;
- filters;
- effects;
- cinematic/vintage/glitch styles;
- music/audio;
- overlays;
- posters;
- captions;
- timeline segments;
- map/location views.

## Collaborative Experience

Multiple users can contribute Moments to the same Experience.

```text
Experience
 ├── Rohan → Moments
 ├── Sarah → Moments
 ├── Alex  → Moments
 └── Rahul → Moments
```

Contributor permissions should be explicit.

## Experience template

An Experience can be shared as a **template**.

A user can choose:

> **Use this Experience**

Phlio creates a new Experience from the structure without copying the original owner's private media.

Templates can define:

- layout;
- sections;
- effects;
- transitions;
- posters;
- placeholders;
- music slots;
- object slots;
- timeline structure.

## Experience Pack

A creator can package a template for:

- trips;
- birthdays;
- graduation;
- weddings;
- concerts;
- sports tournaments;
- festivals;
- portfolio stories;
- creator campaigns.

Eventually, Experience Packs can become a creator/commerce category in Shop.

## Experience Notes

An Experience can contain many Notes referencing other Phlio Objects:

```text
Japan Trip Experience
│
├── 📝 Stream Note → Movie
├── 📝 Book Note → Flight
├── 📝 Book Note → Hotel
├── 📝 Book Note → Restaurant
├── 📝 Shop Note → Camera
└── 📝 Stream Note → Playlist
```

Clicking each object opens its native Phlio domain.

---

# 19. Cross-Platform Sharing, Recommendation and Remix

Every major Phlio Object should support some combination of:

- Save;
- Share;
- Recommend;
- Tag;
- Comment;
- Add Note;
- Add to Collection;
- Add to Experience;
- Remix where the source permits it.

## Remix

Inspired by the useful part of Tumblr's reblog model, Phlio can support **Remix** while preserving attribution. Tumblr's reblogs can include additional commentary, images, and GIFs; Phlio can generalize that idea across Clicks, Scenes, Experiences, and other eligible social objects. citeturn648385search12

```text
Original Click
   ↓
Remix by Rohan
   ↓
Remix by Sarah
```

A Remix should preserve:

- original creator;
- content lineage;
- contribution history;
- permissions.

## Remix Chain

Users can inspect the lineage of a Remix without duplicating ownership.

---

# 20. Collections and Stacks

## Collections

Users can save and organize cross-domain objects.

Example:

```text
My Japan Trip
├── Flight
├── Hotel
├── Restaurant
├── Anime
├── Song
├── Camera
└── Experiences
```

## Stacks

A Stack is a richer curated collection where each object can have context.

Example:

```text
Cyberpunk Inspiration Stack
├── Artwork       → “Color reference”
├── Scene         → “Editing inspiration”
├── Song          → “Soundtrack”
├── News story    → “Research”
├── Shop product  → “Lighting reference”
└── Experience    → “Real-world inspiration”
```

This borrows the strongest idea from visual curation platforms without simply cloning their boards.

---

# 21. Search and Discovery

Phlio Search should be cross-domain by design.

```text
One search box
     ↓
People
Posts
Clicks
Scenes
Rooms
Communities
Products
Artists
Art & Handmade
Events
Places
Restaurants
Bookings
Stream content
News
Experiences
```

Long-term retrieval can combine:

- keyword search;
- faceted filters;
- typo tolerance;
- structured ranking;
- semantic retrieval;
- personalization;
- safety filters.

Meilisearch is the initial application-search engine, while a later hybrid retrieval layer can add embeddings/reranking where justified.

---

# 22. Complete Production Repository Architecture

The actual Flutter project root is **`frontend/ui/`**. There is no `frontend/ui/flutter/` directory.

```text
phlio/
│
├── README.md
├── LICENSE
├── SECURITY.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── CHANGELOG.md
├── .gitignore
├── .editorconfig
├── .env.example
├── Makefile
├── docker-compose.yml
│
├── frontend/
│   │
│   ├── ui/                              ← ACTUAL FLUTTER PROJECT ROOT
│   │   ├── lib/
│   │   │   ├── main.dart
│   │   │   ├── app/
│   │   │   │   ├── app.dart
│   │   │   │   ├── router/
│   │   │   │   ├── theme/
│   │   │   │   ├── config/
│   │   │   │   └── localization/
│   │   │   ├── core/
│   │   │   │   ├── networking/
│   │   │   │   ├── storage/
│   │   │   │   ├── auth/
│   │   │   │   ├── permissions/
│   │   │   │   ├── security/
│   │   │   │   ├── analytics/
│   │   │   │   ├── errors/
│   │   │   │   ├── logging/
│   │   │   │   └── utils/
│   │   │   ├── design_system/
│   │   │   │   ├── colors/
│   │   │   │   ├── typography/
│   │   │   │   ├── spacing/
│   │   │   │   ├── icons/
│   │   │   │   ├── buttons/
│   │   │   │   ├── cards/
│   │   │   │   ├── dialogs/
│   │   │   │   ├── navigation/
│   │   │   │   └── components/
│   │   │   ├── features/
│   │   │   │   ├── home/
│   │   │   │   ├── onboarding/
│   │   │   │   ├── authentication/
│   │   │   │   ├── social/
│   │   │   │   │   ├── feed/
│   │   │   │   │   ├── clicks/
│   │   │   │   │   ├── scenes/
│   │   │   │   │   ├── stories/
│   │   │   │   │   ├── live/
│   │   │   │   │   ├── comments/
│   │   │   │   │   ├── messages/
│   │   │   │   │   ├── calls/
│   │   │   │   │   ├── profile/
│   │   │   │   │   ├── moments/
│   │   │   │   │   ├── experiences/
│   │   │   │   │   ├── stickers/
│   │   │   │   │   └── notes/
│   │   │   │   ├── rooms/
│   │   │   │   │   ├── communities/
│   │   │   │   │   ├── servers/
│   │   │   │   │   ├── spaces/
│   │   │   │   │   ├── channels/
│   │   │   │   │   ├── threads/
│   │   │   │   │   ├── voice/
│   │   │   │   │   ├── video/
│   │   │   │   │   ├── streaming/
│   │   │   │   │   └── files/
│   │   │   │   ├── book/
│   │   │   │   │   ├── entertainment/
│   │   │   │   │   ├── sports/
│   │   │   │   │   ├── mobility/
│   │   │   │   │   ├── services/
│   │   │   │   │   ├── meet/
│   │   │   │   │   ├── travel/
│   │   │   │   │   └── bookings/
│   │   │   │   ├── shop/
│   │   │   │   │   ├── catalog/
│   │   │   │   │   ├── categories/
│   │   │   │   │   ├── search/
│   │   │   │   │   ├── product/
│   │   │   │   │   ├── cart/
│   │   │   │   │   ├── checkout/
│   │   │   │   │   ├── seller/
│   │   │   │   │   ├── orders/
│   │   │   │   │   ├── deals/
│   │   │   │   │   └── delivery/
│   │   │   │   ├── stream/
│   │   │   │   │   ├── video/
│   │   │   │   │   ├── music/
│   │   │   │   │   ├── podcasts/
│   │   │   │   │   ├── audio/
│   │   │   │   │   ├── live/
│   │   │   │   │   ├── player/
│   │   │   │   │   └── library/
│   │   │   │   ├── news/
│   │   │   │   │   ├── feed/
│   │   │   │   │   ├── story/
│   │   │   │   │   ├── sources/
│   │   │   │   │   ├── comparison/
│   │   │   │   │   └── community_notes/
│   │   │   │   ├── pay/
│   │   │   │   │   ├── p2p/
│   │   │   │   │   ├── qr/
│   │   │   │   │   ├── bills/
│   │   │   │   │   ├── split/
│   │   │   │   │   ├── transactions/
│   │   │   │   │   ├── investments/
│   │   │   │   │   └── offline/
│   │   │   │   ├── search/
│   │   │   │   ├── notifications/
│   │   │   │   ├── settings/
│   │   │   │   └── phlio_agent/
│   │   │   └── shared/
│   │   │       ├── phlio_objects/
│   │   │       ├── note_composer/
│   │   │       ├── media/
│   │   │       ├── widgets/
│   │   │       ├── models/
│   │   │       └── extensions/
│   │   │
│   │   ├── android/
│   │   ├── ios/
│   │   ├── web/
│   │   ├── macos/
│   │   ├── windows/
│   │   ├── linux/
│   │   ├── test/
│   │   ├── integration_test/
│   │   ├── assets/
│   │   │   ├── images/
│   │   │   ├── icons/
│   │   │   ├── logos/
│   │   │   ├── fonts/
│   │   │   ├── animations/
│   │   │   ├── illustrations/
│   │   │   ├── agent/
│   │   │   ├── stickers/
│   │   │   └── localization/
│   │   ├── shaders/
│   │   │   ├── backgrounds/
│   │   │   ├── effects/
│   │   │   ├── transitions/
│   │   │   ├── camera/
│   │   │   └── agent/
│   │   ├── pubspec.yaml
│   │   └── analysis_options.yaml
│   │
│   ├── design/
│   │   ├── brand/
│   │   ├── ux/
│   │   ├── prototypes/
│   │   ├── icons/
│   │   └── design_tokens/
│   │
│   ├── marketing/
│   │   ├── website/
│   │   ├── landing_pages/
│   │   ├── campaigns/
│   │   ├── social_media/
│   │   ├── brand/
│   │   ├── press/
│   │   ├── app_store/
│   │   ├── play_store/
│   │   ├── seo/
│   │   ├── email/
│   │   ├── creator_campaigns/
│   │   └── analytics/
│   │
│   └── admin/
│       ├── dashboard/
│       ├── moderation/
│       ├── support/
│       ├── risk/
│       ├── merchants/
│       ├── creators/
│       └── operations/
│
├── backend/
│   ├── app/
│   │   ├── main.py
│   │   ├── api/
│   │   │   ├── router.py
│   │   │   └── v1/
│   │   ├── websocket/
│   │   │   ├── chat.py
│   │   │   ├── rooms.py
│   │   │   ├── presence.py
│   │   │   ├── calls.py
│   │   │   └── notifications.py
│   │   ├── domains/
│   │   │   ├── identity/
│   │   │   ├── social/
│   │   │   ├── communication/
│   │   │   ├── notes/
│   │   │   ├── experiences/
│   │   │   ├── rooms/
│   │   │   ├── payments/
│   │   │   ├── commerce/
│   │   │   ├── booking/
│   │   │   ├── stream/
│   │   │   ├── news/
│   │   │   ├── discovery/
│   │   │   ├── media/
│   │   │   ├── notifications/
│   │   │   ├── recommendations/
│   │   │   └── security/
│   │   ├── infrastructure/
│   │   │   ├── database/
│   │   │   ├── redis/
│   │   │   ├── search/
│   │   │   ├── object_storage/
│   │   │   ├── messaging/
│   │   │   ├── payments/
│   │   │   ├── booking/
│   │   │   ├── maps/
│   │   │   ├── streaming/
│   │   │   ├── webrtc/
│   │   │   └── external/
│   │   ├── middleware/
│   │   └── common/
│   ├── workers/
│   │   ├── notifications/
│   │   ├── media_processing/
│   │   ├── video_transcoding/
│   │   ├── search_indexing/
│   │   ├── recommendation/
│   │   ├── fraud_analysis/
│   │   ├── file_scanning/
│   │   ├── payment_reconciliation/
│   │   ├── booking_updates/
│   │   ├── delivery_updates/
│   │   └── ai_tasks/
│   ├── migrations/
│   ├── tests/
│   ├── pyproject.toml
│   └── uv.lock
│
├── ai_service/
│   ├── app/
│   │   ├── main.py
│   │   ├── api/
│   │   ├── agents/
│   │   │   ├── supervisor/
│   │   │   ├── social/
│   │   │   ├── rooms/
│   │   │   ├── shop/
│   │   │   ├── book/
│   │   │   ├── stream/
│   │   │   ├── news/
│   │   │   ├── finance_assistant/
│   │   │   └── security/
│   │   ├── orchestration/
│   │   ├── tools/
│   │   ├── memory/
│   │   │   ├── short_term/
│   │   │   ├── long_term/
│   │   │   ├── episodic/
│   │   │   ├── semantic/
│   │   │   ├── preferences/
│   │   │   └── privacy/
│   │   ├── models/
│   │   │   ├── llm/
│   │   │   ├── embeddings/
│   │   │   ├── reranker/
│   │   │   ├── classifiers/
│   │   │   └── multimodal/
│   │   ├── guardrails/
│   │   └── evaluation/
│   ├── prompts/
│   ├── configs/
│   ├── tests/
│   ├── pyproject.toml
│   └── uv.lock
│
├── phlio_core/
│   ├── Cargo.toml
│   ├── crates/
│   │   ├── crypto/
│   │   ├── transaction_engine/
│   │   ├── offline_payment/
│   │   ├── risk_features/
│   │   ├── serialization/
│   │   ├── media_primitives/
│   │   └── common/
│   ├── python/
│   │   └── phlio_core/
│   └── flutter/
│       └── phlio_core/
│
├── data/
│   ├── surrealdb/
│   │   ├── schema/
│   │   ├── migrations/
│   │   ├── indexes/
│   │   └── seed/
│   ├── redis/
│   │   ├── cache/
│   │   ├── sessions/
│   │   ├── rate_limits/
│   │   └── locks/
│   ├── meilisearch/
│   │   ├── indexes/
│   │   └── settings/
│   └── object_storage/
│       ├── social_media/
│       ├── rooms_files/
│       ├── experiences/
│       ├── stream_media/
│       ├── shop_media/
│       ├── documents/
│       └── temporary_uploads/
│
├── infrastructure/
│   ├── docker/
│   ├── compose/
│   ├── kubernetes/
│   ├── terraform/
│   ├── monitoring/
│   └── secrets/
│
├── security/
│   ├── threat_models/
│   ├── policies/
│   ├── compliance/
│   ├── incident_response/
│   ├── fraud/
│   ├── moderation/
│   └── privacy/
│
├── analytics/
│   ├── events/
│   ├── schemas/
│   ├── pipelines/
│   ├── experiments/
│   └── dashboards/
│
├── scripts/
│   ├── development/
│   ├── database/
│   ├── data/
│   ├── media/
│   ├── deployment/
│   ├── security/
│   └── maintenance/
│
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── api/
│   ├── e2e/
│   ├── security/
│   ├── performance/
│   ├── load/
│   └── ai/
│
├── docs/
│   ├── architecture/
│   ├── product/
│   ├── api/
│   ├── ai/
│   ├── security/
│   ├── data/
│   ├── operations/
│   └── runbooks/
│
└── .github/
    ├── workflows/
    │   ├── frontend.yml
    │   ├── backend.yml
    │   ├── ai.yml
    │   ├── rust.yml
    │   ├── security.yml
    │   └── release.yml
    ├── ISSUE_TEMPLATE/
    └── PULL_REQUEST_TEMPLATE.md
```

---

# 23. Flutter Architecture

`frontend/ui/` is the Flutter project root.

Recommended feature architecture:

```text
feature/
├── data/
├── domain/
└── presentation/
```

### Presentation

- screens;
- widgets;
- controllers/notifiers;
- UI state.

### Domain

- entities;
- use cases;
- repository contracts;
- client-side rules that are safe to reproduce.

### Data

- API clients;
- DTOs;
- serialization;
- repository implementations;
- local persistence.

Flutter must not be the authority for sensitive authorization, payment, fraud, ownership, or inventory rules.

## State management

Use one consistent approach across the project, such as Riverpod or Bloc/Cubit.

Recommended flow:

```text
UI
 ↓
Controller / Notifier
 ↓
Use Case
 ↓
Repository
 ↓
Remote API / Local data
```

## Design system

Phlio's visual direction:

- premium;
- clean;
- solid surfaces;
- restrained gradients;
- no unnecessary transparency;
- limited glassmorphism;
- strong typography;
- expressive but controlled motion;
- fox/Agent personality;
- usable for Gen Z and Millennials;
- accessible on lower-end devices.

## Shaders

Use shaders selectively for:

- premium onboarding;
- Agent transitions;
- camera effects;
- Experience transitions;
- special Shop/Stream visuals;
- interactive backgrounds.

Shaders should enhance the product rather than become the product.

---

# 24. Backend Architecture

FastAPI is the primary API framework.

```text
API Layer
   ↓
Application / Use Cases
   ↓
Domain Layer
   ↓
Repository Interfaces
   ↓
Infrastructure
   ↓
SurrealDB / Redis / Search / Providers
```

The initial backend should be a **modular monolith**, not a collection of dozens of microservices.

This provides:

- simpler local development;
- easier debugging;
- fewer distributed-failure modes;
- simpler deployment;
- strong domain boundaries;
- a path to later service extraction.

Potential future service extraction points:

```text
payments
messaging/realtime
streaming
search
commerce
booking
risk
media processing
AI
```

Extract only where scale, organizational boundaries, or reliability requirements justify it.

---

# 25. Data Architecture

## SurrealDB

Initial primary application data store for interconnected product entities and relationships.

Typical records:

```text
user
profile
social_post
click
scene
comment
message
note
moment
experience
community
server
space
channel
thread
product
seller
order
booking
stream_item
news_story
payment_request
transaction
notification
```

The graph model is useful for relationships such as:

```text
user → follows → user
user → member_of → server
user → joined → community
user → created → click
user → saved → product
user → booked → experience
user → purchased → product
user → watched → movie
user → tagged → note
experience → references → stream_item
note → references → product
```

## Financial records

The application database can hold application/payment metadata, but the authoritative financial ledger architecture must follow the actual payment partners, regulatory requirements, settlement design, audit rules, and consistency needs. A dedicated ledger or provider-side ledger may be appropriate at production financial scale.

## Redis

Use for:

- sessions;
- cache;
- rate limits;
- presence;
- temporary Agent state;
- distributed locks;
- hot recommendations;
- realtime coordination.

Redis is not the source of truth for important financial records.

## Meilisearch

Indexes may include:

```text
users
posts
clicks
scenes
rooms
communities
products
artists
artwork
bookings
places
stream_items
news
experiences
```

## Object storage

Use object storage for large files and media.

The database stores metadata and references, not giant binary payloads.

---

# 26. Media, Calls and Streaming Architecture

## Media pipeline

```text
Upload
 ↓
Auth
 ↓
Validation
 ↓
Quarantine
 ↓
Malware / policy scan where appropriate
 ↓
Object Storage
 ↓
Media processing
 ↓
Variants / thumbnails / previews
 ↓
CDN / application delivery
```

## Video streaming

Phlio Stream should use a dedicated media pipeline rather than serving large original files directly.

Conceptually:

```text
Master media
 ↓
Transcoding
 ↓
Adaptive bitrate packages
 ↓
CDN
 ↓
Phlio Player
```

FFmpeg or a managed transcoding service can be used depending on operational requirements.

## Social live / Rooms live

Live architecture should support:

- ingestion;
- transcoding;
- low-latency playback where required;
- chat;
- moderation;
- viewer counts;
- live reactions;
- optional recording/replay.

## Voice/video calls

WebRTC is the likely foundation for one-to-one and group audio/video calls, with TURN/STUN infrastructure and a signaling layer.

Discord's current voice/video architecture and its completed E2EE rollout demonstrate the scale and security expectations for realtime calling, although Phlio should design its own implementation and security model. citeturn193997search14

---

# 27. AI Service Architecture

```text
Flutter
 ↓
FastAPI
 ↓
AI Service
 ↓
Supervisor
 ↓
Planner
 ↓
Specialized Agent
 ↓
Controlled Tools
 ↓
Domain APIs
```

Potential orchestration technology:

- LangGraph for graph/stateful agent workflows;
- LangChain components where useful;
- direct model APIs where simpler;
- Pydantic schemas for strict tool contracts;
- evaluation harnesses for agent regression testing.

The exact model provider should remain replaceable behind an abstraction layer.

## Memory

Possible categories:

- short-term conversation;
- episodic experiences;
- semantic preferences;
- user-approved long-term preferences;
- privacy/retention metadata.

SurrealDB/Spectron or another suitable memory framework can be used according to the final memory implementation.

Every memory should have:

- owner;
- provenance/source;
- timestamp;
- retention policy;
- confidence where applicable;
- deletion capability;
- visibility rules.

---

# 28. Phlio Trust & Safety

Security is a platform-wide concern, not a feature of one domain.

```text
PHLIO TRUST
│
├── Identity
├── Authentication
├── Device Trust
├── Account Security
├── Payment Risk
├── Scam Detection
├── Fraud Detection
├── Malicious Link Detection
├── File Scanning
├── Marketplace Safety
├── Spam / Bot Detection
├── Moderation
├── Community Safety
├── Privacy Controls
└── Incident Response
```

## Risk pipeline

```text
Event
 ↓
Feature Extraction
 ↓
Rules
 +
ML models
 ↓
Risk Aggregation
 ↓
Graph Analysis
 ↓
Policy Engine
 ↓
Allow / Challenge / Review / Block
```

High-impact actions should not be determined by a single opaque model.

---

# 29. Recommendation System

A shared recommendation stack can serve Social, Shop, Book, Stream, News, Rooms, and Search while applying domain-specific privacy constraints.

```text
Candidate generation
 ↓
Eligibility / policy filters
 ↓
Ranking
 ↓
Personalization
 ↓
Diversity / quality constraints
 ↓
Recommendation
```

Signals can include:

- explicit interests;
- follows;
- room memberships;
- content interactions;
- shopping preferences;
- Book activity;
- Stream preferences;
- topic follows;
- location context when explicitly permitted;
- time/context.

Sensitive financial or highly personal signals should not silently become social recommendations.

---

# 30. Events and Cross-Domain Architecture

Phlio should be event-driven internally.

Examples:

```text
UserCreated
PostCreated
ClickCreated
ScenePublished
MessageSent
NoteCreated
RoomJoined
ExperienceUpdated
ProductViewed
OrderCreated
PaymentInitiated
PaymentCompleted
BookingCreated
BookingConfirmed
StreamStarted
NewsStoryPublished
CommunityNoteSubmitted
RiskDetected
```

Events can feed:

- notifications;
- analytics;
- recommendation;
- search indexing;
- Agent memory;
- fraud detection;
- moderation;
- audit systems.

A message or event should not require every downstream consumer to run synchronously.

---

# 31. Phlio Tech Stack

| Layer | Technology / direction |
|---|---|
| Mobile/Desktop UI | Flutter + Dart |
| Backend API | Python + FastAPI |
| Validation | Pydantic |
| Python package management | uv |
| Primary app database | SurrealDB |
| Cache / ephemeral state | Redis |
| Search | Meilisearch |
| Large media/files | S3-compatible object storage |
| Realtime messaging | WebSocket + event/pub-sub layer |
| Audio/video calling | WebRTC + signaling/TURN infrastructure |
| Video/audio processing | FFmpeg or managed media pipeline |
| AI orchestration | LangGraph / controlled tool orchestration |
| AI integrations | Model-provider abstraction |
| Agent memory | SurrealDB/Spectron or equivalent memory layer |
| Embeddings/reranking | Replaceable model layer |
| Performance/security core | Rust |
| Python ↔ Rust | PyO3 / native bindings |
| Flutter ↔ Rust | FFI/plugin bridge where needed |
| Infrastructure | Docker, Compose initially; Kubernetes later |
| IaC | Terraform |
| Observability | OpenTelemetry, Prometheus, Grafana, structured logs |
| CI/CD | GitHub Actions |
| CDN | Cloud/managed CDN appropriate to deployment region |
| Payments | Regulated partner/payment-rail integrations |
| Maps/location | Provider abstraction |
| GIFs | GIPHY/other licensed provider integrations |
| Music | Phlio Stream + licensed/provider integrations |

### Rust boundary

Rust should be selective rather than universal.

Good candidates:

- cryptographic primitives;
- performance-critical transaction validation;
- offline-payment primitives where appropriate;
- CPU-intensive deterministic algorithms;
- native media/security primitives;
- hot-path serialization or feature extraction after profiling.

Python remains the primary backend and AI language.

---

# 32. Marketing Strategy

## Positioning problem

Phlio should **not** market itself as:

> “Instagram + Discord + Amazon + Netflix + Paytm in one app.”

That makes Phlio sound like a bundle of clones.

Instead, the core promise should be:

> **Phlio connects the things you discover with the things you actually do.**

Possible brand language:

> **Discover. Connect. Experience.**

or:

> **People. Places. Possibilities.**

or a more action-oriented product line:

> **Tell Phlio what you want to do.**

## Competitive positioning

Phlio should compete by **connecting workflows**, not by claiming superiority at every individual category.

| Existing category | User expectation | Phlio response |
|---|---|---|
| Instagram / Reels | visual social + creators | Social + Clicks + Scenes + Moments + Experiences + Notes |
| X | public conversation + trends | Social text posts + Topics + Rooms |
| Reddit | interest communities | Rooms + Communities + Servers + Spaces |
| Discord | community + voice/video | Rooms + Channels + calls + files + streaming |
| Tumblr | fandom + reblog/tag culture | Remix + Topics + Collections + Rooms |
| Pinterest | visual inspiration | Collections + Stacks + visual discovery + Shop |
| Amazon | broad commerce | Shop + Social discovery + Notes + Agent |
| Zepto-style quick commerce | local speed | Shop local/rapid fulfillment |
| BookMyShow-style booking | tickets/events | Book across entertainment, sports, travel and services |
| Netflix | video entertainment | Stream + Rooms + Social + Book |
| Spotify | music/podcasts/audio | Stream + Social + Rooms + Notes |
| Ground News | source comparison | News + source context + Community Notes |
| Payments apps | money movement | Pay embedded across the entire platform |

Current product patterns support the strategic direction: Instagram continues to emphasize short-form video and creator-led discovery; Discord maintains server/community and voice-channel primitives; Tumblr's reblog and tag mechanics support participatory culture; Pinterest emphasizes visual discovery and object-level visual search; Netflix is expanding live events; Spotify is expanding beyond music into video podcasts, audiobooks and conversational discovery. citeturn731791search1turn731791search12turn648385search12turn648385search11turn193997search1turn193997search2turn193997search0

## Target audience

Initial product-design audience:

### Primary

**18–30**

- students;
- young professionals;
- creators;
- artists;
- gamers;
- fandom communities;
- experience seekers;
- socially active shoppers;
- people who frequently coordinate plans with friends.

### Secondary

**31–40**

- experience planners;
- travelers;
- parents/households;
- higher-value shoppers;
- creators/business owners;
- service customers.

The product should use **Gen Z personality + Millennial usability**, rather than making the entire interface look like a Gen-Z entertainment app.

## Launch wedge

Do not launch every domain as equally important.

A practical wedge is:

```text
Social
 +
Rooms
 +
Agent
 +
Pay foundation
```

Then expand the network with:

```text
Book
 ↓
Shop
 ↓
Stream
 ↓
News
```

The exact operational order can change according to partnerships, regulatory readiness, and product-market feedback.

## Growth loops

### Social loop

```text
Create
 ↓
Share
 ↓
Interact
 ↓
Follow
 ↓
Create again
```

### Community loop

```text
Join Room
 ↓
Participate
 ↓
Invite friends
 ↓
More content
 ↓
More members
```

### Commerce loop

```text
Discover product
 ↓
Share / Note
 ↓
Friend interaction
 ↓
Purchase
 ↓
Review/content
 ↓
New discovery
```

### Experience loop

```text
Book
 ↓
Experience
 ↓
Click / Scene
 ↓
Moment
 ↓
Experience
 ↓
Share / Template / Remix
```

### Entertainment loop

```text
Stream
 ↓
Share / Tag
 ↓
Room discussion
 ↓
Watch / Listen together
 ↓
Social content
```

## Creator-led marketing

Creators should be used as **distribution engines**, not only as advertisers.

Potential programs:

- creator Experiences;
- creator Room launches;
- Shop storefronts;
- custom Experience templates;
- sticker packs;
- community challenges;
- watch/listening parties;
- local Meet activities;
- Phlio-exclusive drops.

## Community-first launch

Rather than trying to acquire users through generic advertising alone, launch around **specific interests**:

- gaming;
- anime;
- AI/programming;
- college communities;
- photography;
- music;
- sports;
- travel;
- creators;
- art;
- local events.

Each vertical can simultaneously showcase:

```text
Social + Rooms + Book + Shop + Stream + Agent
```

## Marketing message

Do not lead with the number of features.

Lead with outcomes:

> “Found a concert? Send it to your friends.”

> “Turn it into a plan.”

> “Book it.”

> “Split the payment.”

> “Capture the experience.”

> “Keep the memory.”

That demonstrates the platform's connected nature far better than a feature list.

---

# 33. Monetization Strategy

Phlio can eventually use multiple monetization models.

## Commerce

- seller commissions;
- fulfillment fees;
- promoted listings;
- merchant subscriptions;
- seller tooling.

## Book

- booking commissions;
- service-provider commissions;
- partner revenue;
- premium placement.

## Stream

- subscriptions;
- advertising where appropriate;
- premium content;
- live-event partnerships.

## Social / Creator

- creator subscriptions;
- digital products;
- commerce revenue share;
- promoted creator content;
- branded experiences.

## Rooms

- premium communities;
- community subscriptions;
- paid events;
- creator/community tools.

## Agent

Possible future premium tier for:

- advanced planning;
- deeper personalization;
- expanded memory controls;
- premium tools;
- premium integrations.

## Financial products

Financial products must be monetized only through models permitted by the relevant financial partners and regulations.

---

# 34. Product Analytics

Core platform metrics:

### Activation

- profile completed;
- first Click/Scene;
- first Room joined;
- first Note sent;
- first Shop interaction;
- first Book interaction;
- first Stream session.

### Engagement

- DAU/WAU/MAU;
- sessions/user;
- comments;
- Notes sent;
- Clicks/Scenes created;
- Room participation;
- watch/listen time;
- searches;
- saves/collections.

### Cross-domain behavior

A particularly important Phlio metric is:

> **How often users cross domain boundaries successfully?**

Examples:

```text
Social → Shop
Social → Stream
Social → Rooms
News → Rooms
Stream → Rooms
Rooms → Book
Book → Pay
Shop → Pay
Experience → Shop/Book/Stream
```

### Agent metrics

- task completion rate;
- successful tool selection;
- human confirmation rate;
- hallucination rate;
- tool error rate;
- latency;
- cost/task;
- user correction rate;
- memory precision/recall where measurable.

---

# 35. Privacy and User Control

Because Phlio spans identity, social behavior, payments, commerce, location, and memories, privacy must be productized.

Users should control:

- location sharing;
- visibility of Moments/Experiences;
- Agent memory;
- personalization;
- financial data access;
- profile customization visibility;
- Room membership visibility;
- Note visibility;
- tag permissions;
- message permissions;
- recommendation controls;
- connected external services.

Sensitive data should not become a cross-domain signal merely because it exists.

Example:

> A private financial transaction should not automatically become a Social recommendation signal.

---

# 36. Administration and Operations

Internal admin tooling should cover:

```text
Admin
├── User Management
├── Identity / Verification
├── Content Moderation
├── Community Moderation
├── Fraud / Risk
├── Payment Operations
├── Merchant Management
├── Booking Operations
├── Stream Content Operations
├── News Source Operations
├── Creator Management
├── Customer Support
├── Refunds / Disputes
├── Analytics
└── System Health
```

Every sensitive administrative action should be auditable.

---

# 37. Testing Strategy

## Unit

Domain logic and pure functions.

## Integration

SurrealDB, Redis, Meilisearch, storage and provider integrations.

## API

FastAPI endpoint behavior, authorization, schema validation.

## E2E

Example:

```text
Create account
 ↓
Customize profile
 ↓
Create Click
 ↓
Join Room
 ↓
Share Shop product via Note
 ↓
Book event
 ↓
Pay
 ↓
Create Experience
 ↓
Share Experience
```

## AI evaluation

- intent accuracy;
- tool choice;
- planning quality;
- memory correctness;
- hallucination;
- privacy behavior;
- safe-action gating;
- cost;
- latency.

## Security

- authentication;
- authorization;
- rate limiting;
- file upload security;
- QR/payment safety;
- account takeover;
- session security;
- prompt injection/tool abuse;
- malicious content;
- spam/bot abuse.

---

# 38. Deployment and Observability

## Initial deployment

```text
CDN
 ↓
Flutter Web / Static assets
 ↓
Load Balancer / API Gateway
 ↓
FastAPI
 ├── Domain modules
 ├── WebSockets
 └── Workers
       │
       ├── SurrealDB
       ├── Redis
       ├── Meilisearch
       ├── Object Storage
       └── External providers

AI Service
   └── Tool APIs / domain APIs
```

## Scaling path

```text
Load Balancer
 ↓
API Gateway
 ↓
Kubernetes / equivalent orchestration
 ├── API Pods
 ├── Realtime Pods
 ├── Worker Pods
 ├── AI Pods
 ├── Media Processing
 └── Streaming services
```

## Observability

Use:

- structured logs;
- OpenTelemetry traces;
- Prometheus metrics;
- Grafana dashboards;
- error tracking;
- product analytics.

Track:

- API latency;
- error rates;
- DB latency;
- queue latency;
- WebSocket connections;
- media processing latency;
- Stream startup time;
- call quality;
- Agent latency;
- payment success/failure.

---

# 39. CI/CD

```text
Git Push
 ↓
Lint
 ↓
Formatting
 ↓
Static analysis
 ↓
Unit Tests
 ↓
Integration Tests
 ↓
Security Scan
 ↓
Build
 ↓
Container Scan
 ↓
Deploy Staging
 ↓
E2E
 ↓
Production
```

Separate pipelines can exist for:

- frontend;
- backend;
- AI;
- Rust;
- infrastructure;
- security.

Use development, testing, staging, and production environments.

Never place real production payment secrets in local development.

---

# 40. Future Product Extensions

The current eight domains should remain stable while new capabilities initially appear as features/categories before becoming independent products.

## Potential future domains

### Phlio Ride

If mobility grows beyond the Book integrations:

- ride discovery;
- scheduled rides;
- group rides;
- carpool;
- fleet tools.

### Phlio Stay

If Travel becomes large enough:

- hotels;
- homestays;
- vacation rentals;
- long-stay booking.

### Phlio Learn

- courses;
- tutoring;
- study communities;
- educational content;
- AI tutoring;
- learning Experiences.

### Phlio Work

- freelancer marketplace;
- professional communities;
- project collaboration;
- hiring;
- work Rooms.

### Phlio Health

Only under appropriate clinical, privacy, regulatory, and provider structures.

### Phlio Business

- business profiles;
- storefronts;
- CRM;
- inventory;
- merchant analytics;
- marketing;
- payment reconciliation;
- customer communities.

### Phlio Developer Platform

Eventually:

```text
Third-party developer
        ↓
Phlio SDK
        ↓
Permissions / sandbox
        ↓
Phlio Objects + APIs
        ↓
Mini apps / agents / services
```

### Phlio Agent Marketplace

Long term, specialized third-party tools or agents could operate within strict permissions, sandboxing, security, privacy, and financial-action policies.

---

# 41. Use Cases Across Sectors

## Entertainment

> “Find something for three friends tonight.”

Agent → Stream/Book → Rooms → Pay → Experience.

## Travel

> “Plan a four-day trip under ₹30,000.”

Book → transport/hotel/activities → Shop → Pay → Experience.

## Sports

> “Find four people for badminton Saturday.”

Rooms → Book → Meet → Pay → Experience.

## Education

> “Help me find an AI study community and resources.”

Rooms → Search → Stream/News → Collections → Notes.

## Creator economy

> “I want to sell my handmade lamps.”

Social → Shop → Art & Handmade → Pay → fulfillment.

## Local discovery

> “What can I do near me for free?”

Book → Meet → places/events → Rooms for people → Experience.

## News

> “Show me what different sources are reporting.”

News → source comparison → Community Notes → Rooms discussion.

## Shopping

> “Find headphones under ₹5,000 that can arrive today.”

Agent → Shop → local/quick inventory → compare → Pay.

## Events

> “Find concerts this weekend and send the best one to my group.”

Book → Note → group chat → Pay.

## Art

> “I want a handmade wall piece under ₹10,000.”

Social/Shop → Art & Handmade → creator → customization → Pay → delivery.

## Community

> “Create a private server for our college project.”

Agent → Rooms → Server → Spaces → files/calls.

---

# 42. Product Flywheel

Phlio's long-term advantage should come from the interactions between domains.

```text
                  DISCOVERY
                     │
       ┌─────────────┼─────────────┐
       │             │             │
    Social         News         Stream
       │             │             │
       └─────────────┼─────────────┘
                     ↓
                 Phlio Note
                     ↓
                Rooms / Chat
                     ↓
             Agent coordinates
                     ↓
             Book / Shop / Pay
                     ↓
                Experience
                     ↓
             Click / Scene
                     ↓
             Moment / Experience
                     ↓
               Remix / Share
                     ↓
                 Discovery
```

This is the core strategic flywheel.

---

# 43. Product Principles

## Principle 1 — One ecosystem, distinct domains

Users should not feel like they are switching apps, but each domain must still have a clear job.

## Principle 2 — Objects travel; ownership does not

A Shop product can appear in a Note or Experience without becoming Social-owned content.

## Principle 3 — Context before complexity

A Note adds context to an object. It should not become another full publishing system.

## Principle 4 — AI coordinates; systems authorize

The Agent plans and orchestrates. Deterministic domain systems control sensitive operations.

## Principle 5 — Community is different from publishing

Social publishes personal/public content. Rooms organizes communities.

## Principle 6 — Shop is for products; Book is for experiences/services/access

This prevents commerce/booking overlap.

## Principle 7 — Memories are persistent and composable

Moments are individual memories; Experiences are larger stories that can be collaborative, templated, and remixed.

## Principle 8 — Trust is cross-platform

The same identity, abuse prevention, fraud, privacy, and security principles should operate across the ecosystem.

## Principle 9 — User control beats invisible automation

Especially for location, memories, financial actions, and Agent behavior.

## Principle 10 — Don't build a feature without a reason

A feature should either:

- solve a real user problem;
- create a strong cross-domain connection;
- improve safety/trust;
- improve creator/business economics;
- or materially improve the core experience.

---

# 44. Recommended Development Strategy

Do not build every domain to maximum complexity immediately.

## Stage 1 — Platform foundation

```text
Flutter
FastAPI
SurrealDB
Redis
Meilisearch
Object Storage
Authentication
Realtime foundation
Observability
CI/CD
```

## Stage 2 — Social + Rooms

Build the social/community network:

- Profiles;
- Clicks;
- Scenes;
- Comments;
- Messages;
- Calls;
- Rooms;
- Communities;
- Servers;
- Spaces;
- Channels;
- basic Notes;
- Search.

## Stage 3 — Phlio Agent

- intent;
- search;
- planning;
- controlled tools;
- memory;
- guardrails;
- security assistance.

## Stage 4 — Pay

Integrate licensed/regulated payment partners.

Build:

- P2P;
- QR;
- requests;
- split payments;
- transaction history;
- bills;
- risk;
- Note payment triggers.

## Stage 5 — Book

- entertainment;
- sports;
- mobility;
- services;
- Meet;
- travel.

## Stage 6 — Shop

- catalog;
- seller system;
- cart;
- checkout;
- local/quick fulfillment;
- deals;
- Art & Handmade;
- delivery.

## Stage 7 — Stream + News

- media catalog;
- player;
- music/audio;
- live;
- source comparison;
- Community Notes.

## Stage 8 — Experiences / ecosystem expansion

- collaborative Experiences;
- templates;
- remix;
- Collections/Stacks;
- creator marketplace;
- advanced recommendations.

## Stage 9 — Scale

Only after genuine product-market signals:

- service extraction;
- advanced event streaming;
- specialized storage;
- multi-region;
- advanced fraud graph;
- high-scale media infrastructure;
- deeper Agent specialization;
- Rust optimization where profiling demonstrates need.

---

# 45. Final Product Architecture Philosophy

Phlio should ultimately behave like this:

```text
                         USER
                           │
                           ▼
                    PHLIO EXPERIENCE
                           │
     ┌─────────────┬──────┼──────┬─────────────┐
     │             │      │      │             │
   SOCIAL        ROOMS   BOOK   SHOP         STREAM
     │             │      │      │             │
   NEWS          PAY     NOTES  OBJECTS       MEDIA
     │             │      │      │             │
     └─────────────┴──────┼──────┴─────────────┘
                           │
                     PHLIO AGENT
                           │
               ┌──────────┴──────────┐
               │                     │
          ORCHESTRATION             TRUST
               │                     │
          Intent / Plans        Security / Fraud
          Search / Memory        Privacy / Safety
          Recommendations        Moderation
               │                     │
               └──────────┬──────────┘
                          │
                    PHLIO PLATFORM
                          │
            ┌─────────────┼──────────────┐
            │             │              │
         FastAPI       Data Layer      Events
            │             │              │
         Domain       SurrealDB       Workers
         Services     Redis           Analytics
                      Search           Notifications
                      Storage
                          │
                    PH LIO CORE
                          │
                   Rust where justified
```

The most important rule remains:

> **The UI should be modular. The backend should be domain-oriented. The AI should orchestrate. Security should authorize. The database should store state. Events should connect domains.**

The product's deepest moat is not the number of features. It is the **connected graph of people, objects, communities, places, experiences, products, media, bookings, and transactions**, combined with a permission-aware Agent that can coordinate them without hiding control from the user.

---

# 46. Final Phlio Definition

> **Phlio is an AI-native social-commerce-experience platform that connects people, communities, products, entertainment, information, bookings, and payments into one ecosystem.**

Its domains have intentionally different jobs:

```text
Phlio Pay      → Transact
Phlio Social   → Express
Phlio Rooms    → Connect
Phlio Book     → Experience
Phlio Shop     → Acquire
Phlio Stream   → Entertain
Phlio News     → Understand
Phlio Agent    → Orchestrate + Protect
```

And its cross-platform primitives make the ecosystem feel unified:

```text
Phlio Object  → what is being referenced
Phlio Note    → why you are sharing it
Click         → instant photo
Scene         → short-form visual content
Moment        → one memory
Experience    → a larger multimedia story
Remix         → build on existing content
Collection    → organize discoveries
Stack         → curate with context
```

The goal is not for Phlio to replace every major application category on day one.

The goal is to create a product where a user can say:

> **“I found something interesting, I shared it with my friends, we discussed it, Phlio helped us plan it, we booked it, paid for it, experienced it, captured it, and turned it into a memory.”**

That is the product story the architecture should serve.

---

# Appendix A — Source / Inspiration Notes

The previous Phlio architecture blueprint is the structural baseline for this document. It established the intent-driven USP, modular monolith approach, FastAPI/SurelDB/Redis/Meilisearch stack, AI service, Agent memory, security architecture, event-driven approach, and selective Rust use.

Current product-inspiration references reviewed for this revision include:

- **Instagram / Meta:** short-form video, creator tooling, sharing, Notes, and evolving location/social discovery surfaces.
- **Discord:** servers, communities, voice/video, media/file channels.
- **Reddit:** topic communities, posts, comments, voting and community moderation.
- **Tumblr:** reblogging with commentary, tags, communities, and participatory niche-interest culture.
- **Pinterest:** visual discovery, object-level visual search, cutouts and collage-like workflows.
- **Ground News:** grouping coverage around stories, publisher-level bias/factuality context, and comparison views.
- **Netflix:** video entertainment plus expanding live-event experiences.
- **Spotify:** music, podcasts, audiobooks, video podcasts, and increasingly interactive discovery.

These references are inspirations for product mechanics, not specifications to reproduce verbatim. Phlio's implementation should use its own UX, data model, branding, moderation rules, and partner contracts.

---

# Appendix B — Non-Negotiable Boundaries

```text
SOCIAL
Public/personal content + interpersonal communication

ROOMS
Persistent communities + group collaboration + large files

BOOK
Reservation / experience / mobility / service / travel

SHOP
Product commerce

PAY
Financial execution

STREAM
Licensed/authorized video + audio entertainment

NEWS
News discovery + source context + community notes

NOTE
Contextual communication around a Phlio Object

EXPERIENCE
Multimedia memory / timeline / collaborative story

AGENT
Intent, planning, orchestration, recommendations and security assistance
```

These boundaries should be treated as architectural invariants unless a future product decision explicitly changes them.
