#!/usr/bin/env python3
"""Check that README.md and README.ja.md list exactly the skills that exist.

Every skill under skills/<name>/SKILL.md must appear as a
'](./skills/<name>/)' link in both README files, and every such link in the
READMEs must point at a skill that actually exists. This is the structural
check for the mistake this repository shipped in practice: a new skill
(circleci-cli, cursor-chunk-sidecar-setup) was added without ever being added
to the README table.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILLS_DIR = REPO_ROOT / "skills"
README_FILES = [REPO_ROOT / "README.md", REPO_ROOT / "README.ja.md"]

LINK_RE = re.compile(r"\]\(\./skills/([a-zA-Z0-9._-]+)/\)")


def actual_skill_names() -> set[str]:
    return {p.parent.name for p in SKILLS_DIR.glob("*/SKILL.md") if p.is_file()}


def readme_skill_names(readme: Path) -> set[str]:
    text = readme.read_text(encoding="utf-8")
    return set(LINK_RE.findall(text))


def main() -> int:
    actual = actual_skill_names()
    if not actual:
        print(f"No skills found under {SKILLS_DIR}", file=sys.stderr)
        return 1

    had_error = False
    for readme in README_FILES:
        if not readme.is_file():
            print(f"{readme}: file not found", file=sys.stderr)
            had_error = True
            continue

        listed = readme_skill_names(readme)
        missing = actual - listed
        stale = listed - actual

        if missing:
            had_error = True
            print(
                f"{readme}: missing entries for: {', '.join(sorted(missing))}",
                file=sys.stderr,
            )
        if stale:
            had_error = True
            print(
                f"{readme}: lists skill(s) that no longer exist under "
                f"skills/: {', '.join(sorted(stale))}",
                file=sys.stderr,
            )
        if not missing and not stale:
            print(f"OK   {readme.relative_to(REPO_ROOT)} lists all {len(actual)} skill(s)")

    if had_error:
        return 1

    print(f"\nBoth READMEs are consistent with skills/ ({len(actual)} skill(s)).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
