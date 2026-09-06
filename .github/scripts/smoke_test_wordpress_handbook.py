#!/usr/bin/env python3
"""Live smoke test for the wordpress-handbook skill's scripts.

Runs search.py and fetch_content.py against the real
developer.wordpress.org API (no mocking) to catch regressions in how the
skill talks to that API, not just whether the Python parses. Requires
outbound network access, which GitHub-hosted runners have by default.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILL_DIR = REPO_ROOT / "skills" / "wordpress-handbook"
SEARCH_PY = SKILL_DIR / "scripts" / "search.py"
FETCH_PY = SKILL_DIR / "scripts" / "fetch_content.py"


def run(args: list[str], expect_exit: int = 0) -> str:
    result = subprocess.run(
        [sys.executable, *args],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != expect_exit:
        raise AssertionError(
            f"{args} exited {result.returncode} (expected {expect_exit})\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
    return result.stdout


def main() -> int:
    # 1. search.py: a real query against the plugin handbook.
    out = run([str(SEARCH_PY), "custom post type", "plugin", "2"])
    results = json.loads(out)
    assert isinstance(results, list), f"expected a JSON array, got: {out!r}"
    assert len(results) >= 1, "search returned no results for a known query"
    for item in results:
        for key in ("id", "title", "url", "handbook", "subtype"):
            assert key in item, f"search result missing {key!r}: {item!r}"
    print(f"OK   search.py returned {len(results)} result(s)")

    # 2. search.py: out-of-range limit must be rejected, not silently clamped.
    # search.py exits 1 on this error path (see its main()), so expect that here.
    out = run([str(SEARCH_PY), "x", "plugin", "99"], expect_exit=1)
    error_payload = json.loads(out)
    assert "error" in error_payload, f"expected a range error, got: {out!r}"
    print("OK   search.py rejects out-of-range limit")

    # 3. fetch_content.py: fetch a known, stable article by id.
    first_id = results[0]["id"]
    first_subtype = results[0]["subtype"]
    out = run([str(FETCH_PY), first_subtype, str(first_id)])
    article = json.loads(out)
    assert article.get("id") == first_id, f"fetch_content id mismatch: {article!r}"
    assert article.get("content"), "fetch_content returned empty content"
    print(f"OK   fetch_content.py fetched article {first_id}")

    print("\nwordpress-handbook smoke test passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"SMOKE TEST FAILED: {exc}", file=sys.stderr)
        raise SystemExit(1)
