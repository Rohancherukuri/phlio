# Phlio Flutter — tests

```bash
flutter test                       # everything
flutter test test/unit             # unit tests only (fast, no widget pumping)
flutter test test/widget           # widget tests only
flutter test --coverage            # + generate coverage/lcov.info
```

## Layout

```
test/
├── unit/     Domain entities, use cases (mocktail-mocked repositories),
│             and core utilities (Result). No Flutter widgets involved —
│             these run fastest and should cover the bulk of business logic.
└── widget/   Design-system components, pumped with `testWidgets`.
```

Mirrors `lib/`'s structure 1:1 (`test/unit/features/shop/...` tests
`lib/features/shop/...`) so a failing test's location tells you exactly
what broke.

## A note on this build

This project was scaffolded in a sandbox without network access to
pub.dev, so `flutter test` itself could not be run here to confirm these
pass — every constructor call was cross-checked by hand against the real
entity/use-case signatures (see each test file's imports), but you should
run the suite as your first step after `flutter pub get` to confirm.
