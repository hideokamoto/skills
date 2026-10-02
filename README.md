# skills

A collection of [Agent Skills](https://agentskills.io) for AI coding agents (Claude Code, Cursor, Codex, and other `SKILL.md`-compatible tools).

This repository is the canonical source for the skills listed here.

> 🇯🇵 日本語版は [README.ja.md](./README.ja.md) をご覧ください。

## Included skills

| Skill | Description | License |
|-------|-------------|---------|
| [`wordpress-handbook`](./skills/wordpress-handbook/) | Searches the official WordPress Developer Handbooks (Plugin / Theme / Block Editor / REST API / Common APIs / Coding Standards / Advanced Administration) on developer.wordpress.org and fetches full article content on demand. | Apache-2.0 |
| [`circleci-cli`](./skills/circleci-cli/) | Operates the CircleCI CLI (CLI v1) safely — auth/token checks, org lookup, project create/get, and config-source questions — to prevent recurring CLI mistakes. | Apache-2.0 |
| [`cursor-chunk-sidecar-setup`](./skills/cursor-chunk-sidecar-setup/) | Sets up a repository already using Chunk sidecar validation under Claude Code so the same sidecar validation also works under Cursor Cloud Agent. | MIT |
| [`claude-web-chunk-sidecar-setup`](./skills/claude-web-chunk-sidecar-setup/) | Sets up Claude Code on the web (cloud containers) so `chunk sidecar sync` works, not just `chunk sidecar ssh`: installs rsync / OpenSSH client and converts the PKCS#8 ed25519 key chunk generates (which the OpenSSH in Ubuntu 24.04 cannot read) to OpenSSH format. | MIT |
| [`export-session-log`](./skills/export-session-log/) | Hands off a Claude Code session's raw JSONL transcript (every tool_use/tool_result, not a summary) so it can be analyzed elsewhere, in another session or a script. | MIT |
| [`dialogic-learning-style`](./skills/dialogic-learning-style/) | A custom writing style that paces explanations in chunks, reading progression vs. deep-dive signals from the user's replies so it neither lectures nor over-questions. | MIT |
| [`research-handoff`](./skills/research-handoff/) | For research/analysis requests: declares who owns the conclusion, the assumed prior knowledge, and how to hand it over before starting, then checks the deliverable's format with a script (`check_handoff.py`). Also re-delivers when the reader says it is hard to follow. | MIT |
| [`stop-and-align`](./skills/stop-and-align/) | When the user rejects or corrects the previous output, stops new work, states the current understanding of the request, and waits for confirmation. | MIT |

Each skill directory may carry its own `license` field in `SKILL.md`'s frontmatter; where it differs from this repository's top-level [LICENSE](./LICENSE) (MIT), the skill directory's own license governs that skill.

## Install

Built on the open [`SKILL.md`](https://agentskills.io) standard. Skills are discovered by the `skills/*/SKILL.md` convention.

```bash
# GitHub CLI
gh skill install hideokamoto/skills <skill-name>

# Vercel skills CLI
npx skills add hideokamoto/skills --skill <skill-name>

# List every skill in this repository
npx skills add hideokamoto/skills --list
```

Where `<skill-name>` is one of `wordpress-handbook`, `circleci-cli`, `cursor-chunk-sidecar-setup`, `claude-web-chunk-sidecar-setup`, `export-session-log`, `dialogic-learning-style`, `research-handoff`, or `stop-and-align`.

## License

[MIT](./LICENSE) for this repository's own files. See each skill's `SKILL.md` for its individual license.
