"""/media files missing on disk are streamed from the bucket (proxy mode),
so phones never need to reach the bucket's own domain."""

from __future__ import annotations

import httpx
import pytest
from fastapi import FastAPI

from app.main import MediaFiles

pytestmark = pytest.mark.asyncio

BODY = bytes(range(256)) * 40


def upstream(request: httpx.Request) -> httpx.Response:
    if request.url.path.endswith("/missing.mp4"):
        return httpx.Response(404)
    rng = request.headers.get("range")
    if rng:
        start, end = (int(x) for x in rng.removeprefix("bytes=").split("-"))
        part = BODY[start:end + 1]
        return httpx.Response(206, stream=httpx.ByteStream(part), headers={
            "content-type": "video/mp4", "content-range": f"bytes {start}-{end}/{len(BODY)}",
            "accept-ranges": "bytes", "content-length": str(len(part))})
    return httpx.Response(200, stream=httpx.ByteStream(BODY), headers={
        "content-type": "video/mp4", "accept-ranges": "bytes", "content-length": str(len(BODY))})


def make(tmp_path, delivery: str) -> httpx.AsyncClient:
    media = MediaFiles(directory=tmp_path, fallback="https://pub-x.r2.dev/", delivery=delivery)
    media._client = httpx.AsyncClient(transport=httpx.MockTransport(upstream))
    app = FastAPI()
    app.mount("/media", media)
    return httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")


async def test_proxy_streams_and_supports_ranges(tmp_path) -> None:
    (tmp_path / "local.txt").write_text("on disk")
    async with make(tmp_path, "proxy") as client:
        assert (await client.get("/media/local.txt")).text == "on disk"
        r = await client.get("/media/open_long/a.mp4")
        assert r.status_code == 200 and r.content == BODY
        assert "max-age" in r.headers["cache-control"]
        r = await client.get("/media/open_long/a.mp4", headers={"Range": "bytes=10-19"})
        assert r.status_code == 206 and r.content == BODY[10:20]
        assert r.headers["content-range"] == f"bytes 10-19/{len(BODY)}"
        assert (await client.get("/media/missing.mp4")).status_code == 404


async def test_redirect_mode(tmp_path) -> None:
    async with make(tmp_path, "redirect") as client:
        r = await client.get("/media/open_long/a.mp4")
        assert r.status_code == 307 and r.headers["location"] == "https://pub-x.r2.dev/open_long/a.mp4"
