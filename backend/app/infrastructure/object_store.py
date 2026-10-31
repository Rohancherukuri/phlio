"""Minimal S3-compatible object storage client (Cloudflare R2, Backblaze B2, MinIO…).

Only what Phlio needs to keep a free, disk-less host (Render) in sync with a
bucket: PUT a file, GET a file, HEAD a key and list a prefix. Requests are
signed with AWS Signature Version 4 using ``httpx`` (already a dependency),
so no AWS SDK is required.

Configure with the ``OBJECT_STORE_*`` settings (see ``app/config.py``). For
Cloudflare R2 the endpoint is ``https://<ACCOUNT_ID>.r2.cloudflarestorage.com``
and the region is ``auto``.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import hmac
import mimetypes
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, Iterator
from urllib.parse import quote

import httpx

_UNSIGNED = "UNSIGNED-PAYLOAD"  # body hash placeholder; fine over HTTPS (R2, B2 and S3 accept it)
_EMPTY_SHA256 = hashlib.sha256(b"").hexdigest()


def _sign(key: bytes, msg: str) -> bytes:
    """One HMAC-SHA256 step of the SigV4 key derivation."""
    return hmac.new(key, msg.encode(), hashlib.sha256).digest()


def _encode_key(key: str) -> str:
    """URI-encodes an object key, keeping the ``/`` separators (SigV4 canonical form)."""
    return quote(key, safe="/~")


@dataclass(frozen=True)
class StoredObject:
    """One entry of a bucket listing."""

    key: str
    size: int


class ObjectStore:
    """Signed requests against one bucket of an S3-compatible service."""

    def __init__(self, endpoint: str, bucket: str, access_key: str, secret_key: str,
                 region: str = "auto", timeout: float = 120) -> None:
        """``endpoint`` is the service URL without the bucket (path-style requests)."""
        self.endpoint = endpoint.rstrip("/")
        self.bucket = bucket
        self.access_key = access_key
        self.secret_key = secret_key
        self.region = region
        self.host = httpx.URL(self.endpoint).host
        self._http = httpx.Client(timeout=timeout)

    # -- signing ----------------------------------------------------------------

    def _headers(self, method: str, key: str, query: dict[str, str] | None = None,
                 payload_hash: str = _UNSIGNED, extra: dict[str, str] | None = None) -> tuple[str, dict[str, str]]:
        """Returns the request URL and SigV4-signed headers for one request."""
        now = dt.datetime.now(dt.UTC)
        amz_date = now.strftime("%Y%m%dT%H%M%SZ")
        day = now.strftime("%Y%m%d")
        path = f"/{self.bucket}/{_encode_key(key)}" if key else f"/{self.bucket}"
        canonical_query = "&".join(
            f"{quote(k, safe='-_.~')}={quote(v, safe='-_.~')}" for k, v in sorted((query or {}).items()))
        headers = {"host": self.host, "x-amz-content-sha256": payload_hash, "x-amz-date": amz_date,
                   **{k.lower(): v for k, v in (extra or {}).items()}}
        signed = sorted(headers)
        canonical = "\n".join([
            method, path, canonical_query,
            "".join(f"{h}:{headers[h].strip()}\n" for h in signed),
            ";".join(signed), payload_hash,
        ])
        scope = f"{day}/{self.region}/s3/aws4_request"
        to_sign = "\n".join(["AWS4-HMAC-SHA256", amz_date, scope, hashlib.sha256(canonical.encode()).hexdigest()])
        k = _sign(_sign(_sign(_sign(("AWS4" + self.secret_key).encode(), day), self.region), "s3"), "aws4_request")
        signature = hmac.new(k, to_sign.encode(), hashlib.sha256).hexdigest()
        headers["authorization"] = (f"AWS4-HMAC-SHA256 Credential={self.access_key}/{scope}, "
                                    f"SignedHeaders={';'.join(signed)}, Signature={signature}")
        url = self.endpoint + path + (f"?{canonical_query}" if canonical_query else "")
        return url, headers

    # -- operations ---------------------------------------------------------------

    def put_file(self, key: str, path: Path, content_type: str | None = None) -> None:
        """Uploads a local file (streamed) to ``key``. Raises on HTTP errors."""
        size = path.stat().st_size
        ctype = content_type or mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        url, headers = self._headers("PUT", key, extra={"content-type": ctype, "content-length": str(size)})
        with path.open("rb") as body:
            self._http.put(url, headers=headers, content=_chunks(body)).raise_for_status()

    def get_file(self, key: str, path: Path) -> bool:
        """Downloads ``key`` to ``path`` (written atomically). False if the key doesn't exist."""
        url, headers = self._headers("GET", key, payload_hash=_EMPTY_SHA256)
        with self._http.stream("GET", url, headers=headers) as response:
            if response.status_code == 404:
                return False
            response.raise_for_status()
            path.parent.mkdir(parents=True, exist_ok=True)
            partial = path.with_name(path.name + ".part")
            with partial.open("wb") as out:
                for chunk in response.iter_bytes(1 << 20):
                    out.write(chunk)
            partial.replace(path)
        return True

    def head(self, key: str) -> int | None:
        """Size of ``key`` in bytes, or None when it doesn't exist."""
        url, headers = self._headers("HEAD", key, payload_hash=_EMPTY_SHA256)
        response = self._http.head(url, headers=headers)
        if response.status_code == 404:
            return None
        response.raise_for_status()
        return int(response.headers.get("content-length", 0))

    def list(self, prefix: str = "") -> Iterator[StoredObject]:
        """Every object under ``prefix`` (ListObjectsV2, following continuation tokens)."""
        token: str | None = None
        while True:
            query = {"list-type": "2", "prefix": prefix, "max-keys": "1000"}
            if token:
                query["continuation-token"] = token
            url, headers = self._headers("GET", "", query=query, payload_hash=_EMPTY_SHA256)
            response = self._http.get(url, headers=headers)
            response.raise_for_status()
            root = ET.fromstring(response.content)
            ns = {"s3": root.tag.split("}")[0].strip("{")} if root.tag.startswith("{") else {}
            find = (lambda e, t: e.find(f"s3:{t}", ns)) if ns else (lambda e, t: e.find(t))
            for item in root.iter(f"{{{ns['s3']}}}Contents" if ns else "Contents"):
                yield StoredObject(find(item, "Key").text or "", int(find(item, "Size").text or 0))
            truncated = find(root, "IsTruncated")
            if truncated is None or truncated.text != "true":
                return
            token = find(root, "NextContinuationToken").text

    def close(self) -> None:
        """Closes the HTTP connection pool."""
        self._http.close()


def _chunks(body: BinaryIO, size: int = 1 << 20) -> Iterator[bytes]:
    """Reads a file object in 1 MB pieces (keeps big videos out of memory)."""
    while chunk := body.read(size):
        yield chunk
