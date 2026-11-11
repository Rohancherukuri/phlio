"""Checks what the R2 keys in backend/.env.publish can do on each bucket.

    uv run python -m scripts.check_r2

Prints, per bucket, whether listing (read) and writing work, with R2's own
error code (AccessDenied, InvalidAccessKeyId, NoSuchBucket, ...). Secrets are
never printed; only the first characters of the access key id are shown so
you can match it with the token in the Cloudflare dashboard.
"""
from __future__ import annotations

import os
import re
import tempfile
from pathlib import Path

import httpx

from app.infrastructure.object_store import ObjectStore
from scripts.publish_local_data import BACKEND, load_publish_env, need


def r2_code(error: httpx.HTTPStatusError) -> str:
    """R2's <Code> from the XML error body, e.g. AccessDenied."""
    found = re.search(r"<Code>([^<]+)</Code>", error.response.text or "")
    return f"{error.response.status_code} {found.group(1) if found else ''}".strip()


def main() -> None:
    os.chdir(BACKEND)
    load_publish_env(BACKEND / ".env.publish")
    endpoint, key, secret = need("OBJECT_STORE_ENDPOINT"), need("OBJECT_STORE_ACCESS_KEY"), need("OBJECT_STORE_SECRET_KEY")
    shown = re.sub(r"//([0-9a-f]{6})[0-9a-f]+", lambda m: "//" + m.group(1) + "…", endpoint)
    print(f"Endpoint:       {shown}")
    print(f"Access key id:  {key[:6]}… ({len(key)} chars; R2 keys are 32)")
    print(f"Secret:         {len(secret)} chars (R2 secrets are 64)")
    buckets = [need("OBJECT_STORE_BUCKET"), os.environ.get("OBJECT_STORE_STATE_BUCKET", "").strip()]
    for name in filter(None, buckets):
        store = ObjectStore(endpoint, name, key, secret, os.environ.get("OBJECT_STORE_REGION", "auto"))
        try:
            try:
                next(iter(store.list("_state/")), None)
                read = "ok"
            except httpx.HTTPStatusError as error:
                read = r2_code(error)
            try:
                with tempfile.TemporaryDirectory() as tmp:
                    probe = Path(tmp) / "probe"
                    probe.write_bytes(b"ok")
                    store.put_file("_state/.write-check", probe, "text/plain")
                    store.delete("_state/.write-check")
                write = "ok"
            except httpx.HTTPStatusError as error:
                write = r2_code(error)
            print(f"Bucket {name!r}: read {read} · write {write}")
        finally:
            store.close()


if __name__ == "__main__":
    main()
