"""Repository contract for the identity domain.

Implemented by `app/infrastructure/database/memory/identity_repo.py`
(default, zero-setup) and `app/infrastructure/database/surreal/identity_repo.py`
(production). The domain and API layers depend only on this interface, so
swapping storage backends never touches business logic — see architecture
doc section 39, "The database should store state," not decide behaviour.
"""

from __future__ import annotations

from typing import Protocol

from app.domains.identity.entities import User


class IdentityRepository(Protocol):
    async def create_user(self, user: User) -> User: ...

    async def get_by_id(self, user_id: str) -> User | None: ...

    async def get_by_username(self, username: str) -> User | None: ...

    async def get_by_email(self, email: str) -> User | None: ...

    async def update_user(self, user: User) -> User: ...
