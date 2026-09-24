```
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