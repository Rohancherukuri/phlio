"""
SurrealDB-backed repository implementations (production).

These implement the exact same Protocols as `../memory/`, wired in when
`DATABASE_BACKEND=surreal` (see `app/core/container.py`). They are written
to be correct against the `surrealdb` Python SDK's documented query API,
but — because this sandbox has no network access to run a SurrealDB
instance — they have not been exercised against a live server. Before
relying on these in a real environment:

  1. `docker compose up surrealdb` (see docker-compose.yml at the repo root)
  2. run `data/surrealdb/schema/*.surql` (referenced inline below) to
     define table/field constraints
  3. run the backend with `DATABASE_BACKEND=surreal` and the integration
     tests in `backend/tests/` against it

Graph relationships mentioned in architecture doc section 11
(`user -> follows -> user`, `user -> member_of -> room`, ...) are the
reason SurrealDB was chosen as the primary store; this initial pass uses
plain table records and simple field-based joins (e.g. `author_id`) to keep
the first implementation easy to verify, and leaves RELATE-based graph
edges as a follow-up once the social graph (`follows`, `likes` as edges
rather than a join table) is actually needed by a feature.
"""
