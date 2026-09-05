# skills

A collection of [Agent Skills](https://agentskills.io) for AI coding agents (Claude Code, Cursor, Codex, and other `SKILL.md`-compatible tools).

> 🇯🇵 日本語版は [README.ja.md](./README.ja.md) をご覧ください。

## Included skills

| Skill | Description | License |
|-------|-------------|---------|
| [`wordpress-handbook`](./skills/wordpress-handbook/) | Searches the official WordPress Developer Handbooks (Plugin / Theme / Block Editor / REST API / Common APIs / Coding Standards / Advanced Administration) on developer.wordpress.org and fetches full article content on demand. | Apache-2.0 |

Each skill directory may carry its own `license` field in `SKILL.md`'s frontmatter; where it differs from this repository's top-level [LICENSE](./LICENSE) (MIT), the skill directory's own license governs that skill.

## Install

Built on the open [`SKILL.md`](https://agentskills.io) standard.

```bash
# GitHub CLI
gh skill install hideokamoto/skills wordpress-handbook

# Vercel skills CLI
npx skills add hideokamoto/skills --skill wordpress-handbook
```

## License

[MIT](./LICENSE) for this repository's own files. See each skill's `SKILL.md` for its individual license.
