#!/usr/bin/env python3
"""Validate every skills/*/SKILL.md against the agentskills.io frontmatter spec.

Written as a small standalone script instead of depending on the "skills-ref"
package from PyPI: at the time this was written, the PyPI project named
"skills-ref" is not owned by an Anthropic-controlled account (its listed
owner is unrelated to the agentskills.io/anthropics source repository that
documents the tool), so installing it in CI would mean trusting an unverified
third party for something that is easy to implement directly from the
published spec (https://agentskills.io/specification). PyYAML is used here
because it is a long-established, widely audited dependency, and SKILL.md
frontmatter needs real YAML parsing (e.g. circleci-cli's `description` field
is a multi-line YAML block scalar).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
SKILLS_DIR = REPO_ROOT / "skills"

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
MAX_NAME_LEN = 64
MAX_DESCRIPTION_LEN = 1024
MAX_COMPATIBILITY_LEN = 500


def find_skill_dirs() -> list[Path]:
    if not SKILLS_DIR.is_dir():
        return []
    return sorted(
        p.parent for p in SKILLS_DIR.glob("*/SKILL.md") if p.is_file()
    )


def split_frontmatter(text: str) -> str | None:
    """Return the raw YAML frontmatter text, or None if the file has none.

    Per spec, frontmatter is only recognized when the very first line is
    exactly '---'.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            return "\n".join(lines[1:i])
    return None


def validate_skill(skill_dir: Path) -> list[str]:
    errors: list[str] = []
    skill_md = skill_dir / "SKILL.md"
    text = skill_md.read_text(encoding="utf-8")

    raw_frontmatter = split_frontmatter(text)
    if raw_frontmatter is None:
        errors.append(f"{skill_md}: file must start with a '---' frontmatter block")
        return errors

    try:
        frontmatter = yaml.safe_load(raw_frontmatter)
    except yaml.YAMLError as exc:
        errors.append(f"{skill_md}: frontmatter is not valid YAML: {exc}")
        return errors

    if not isinstance(frontmatter, dict):
        errors.append(f"{skill_md}: frontmatter must be a YAML mapping")
        return errors

    # name
    name = frontmatter.get("name")
    if not name or not isinstance(name, str):
        errors.append(f"{skill_md}: 'name' is required and must be a string")
    else:
        if len(name) > MAX_NAME_LEN:
            errors.append(
                f"{skill_md}: 'name' exceeds {MAX_NAME_LEN} characters: {name!r}"
            )
        if not NAME_RE.match(name):
            errors.append(
                f"{skill_md}: 'name' must be lowercase alphanumeric with single "
                f"hyphens, no leading/trailing/consecutive hyphens: {name!r}"
            )
        if name != skill_dir.name:
            errors.append(
                f"{skill_md}: 'name' ({name!r}) must match its directory name "
                f"({skill_dir.name!r})"
            )

    # description
    description = frontmatter.get("description")
    if not description or not isinstance(description, str):
        errors.append(f"{skill_md}: 'description' is required and must be a string")
    elif len(description) > MAX_DESCRIPTION_LEN:
        errors.append(
            f"{skill_md}: 'description' exceeds {MAX_DESCRIPTION_LEN} characters "
            f"({len(description)})"
        )

    # optional: compatibility
    compatibility = frontmatter.get("compatibility")
    if compatibility is not None:
        if not isinstance(compatibility, str):
            errors.append(f"{skill_md}: 'compatibility' must be a string")
        elif len(compatibility) > MAX_COMPATIBILITY_LEN:
            errors.append(
                f"{skill_md}: 'compatibility' exceeds {MAX_COMPATIBILITY_LEN} "
                f"characters ({len(compatibility)})"
            )

    # optional: license
    license_field = frontmatter.get("license")
    if license_field is not None and not isinstance(license_field, str):
        errors.append(f"{skill_md}: 'license' must be a string")

    # optional: metadata
    metadata = frontmatter.get("metadata")
    if metadata is not None and not isinstance(metadata, dict):
        errors.append(f"{skill_md}: 'metadata' must be a mapping")

    return errors


def main() -> int:
    skill_dirs = find_skill_dirs()
    if not skill_dirs:
        print(f"No skills found under {SKILLS_DIR}", file=sys.stderr)
        return 1

    all_errors: list[str] = []
    for skill_dir in skill_dirs:
        errors = validate_skill(skill_dir)
        if errors:
            all_errors.extend(errors)
        else:
            print(f"OK   {skill_dir.relative_to(REPO_ROOT)}")

    if all_errors:
        print("\nValidation failures:", file=sys.stderr)
        for error in all_errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print(f"\nAll {len(skill_dirs)} skill(s) passed frontmatter validation.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
