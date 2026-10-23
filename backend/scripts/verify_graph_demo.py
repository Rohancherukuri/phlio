"""Non-destructive smoke test against the running isolated graph demo API."""

import json
import time

import httpx


def main():
    with httpx.Client(base_url="http://127.0.0.1:8002", timeout=60) as c:
        r = c.post("/api/v1/auth/login", json={"identifier": "demo_viewer_021", "password": "PhlioDemo!2026"})
        r.raise_for_status()
        h = {"Authorization": "Bearer " + r.json()["tokens"]["access_token"]}
        ids = []
        cursor = None
        while True:
            page = c.get(
                "/api/v1/social/feed",
                headers=h,
                params={"limit": 17, **({"cursor": cursor} if cursor else {})},
            )
            page.raise_for_status()
            data = page.json()
            ids.extend(p["id"] for p in data["items"])
            cursor = data["meta"]["next_cursor"]
            if cursor is None:
                break
        assert len(ids) == len(set(ids)) and len(ids) >= 60
        timings = []
        for path in [
            "/api/v1/social/feed",
            "/api/v1/social/feed",
            "/api/v1/social/videos",
            "/api/v1/social/videos",
            "/api/v1/social/following",
            "/api/v1/social/graph-status",
        ]:
            t = time.perf_counter()
            r = c.get(path, headers=h)
            r.raise_for_status()
            timings.append(
                {"path": path, "status": r.status_code, "ms": round((time.perf_counter() - t) * 1000, 1)}
            )
            if path.endswith("graph-status"):
                print(json.dumps(r.json()))
        r = c.get("/media/demo_graph/video_00.mp4", headers={"Range": "bytes=0-1023"})
        assert r.status_code == 206 and len(r.content) == 1024
        print(json.dumps({"requests": timings, "video_range": r.headers.get("content-range")}, indent=2))


if __name__ == "__main__":
    main()
