# wordpress-handbook

An [Agent Skill](https://agentskills.io) that searches the official WordPress Developer Handbooks on [developer.wordpress.org](https://developer.wordpress.org/) so coding agents can answer plugin/theme/block-editor/REST API/coding-standards questions from primary sources.

Parent repository: [hideokamoto/wordpress-skills](https://github.com/hideokamoto/wordpress-skills).

## What it does

- Runs a two-step flow: **search** handbook articles, then **fetch** full HTML for a chosen article when detail is needed.
- Covers seven handbooks (plugins, themes, blocks, REST API, common APIs, coding standards, advanced administration).

## Included handbooks

| Shortname | Subtype | Description |
|-----------|---------|-------------|
| `plugin` | `plugin-handbook` | Plugin development guide |
| `theme` | `theme-handbook` | Theme development guide |
| `block` | `blocks-handbook` | Block Editor (Gutenberg) |
| `rest-api` | `rest-api-handbook` | REST API usage |
| `apis` | `apis-handbook` | Common APIs (Settings, Options, etc.) |
| `coding` | `wpcs-handbook` | WordPress Coding Standards |
| `admin` | `adv-admin-handbook` | Advanced Administration |

## Install (recommended)

Use the umbrella repo so paths and versioning match [wordpress-skills](https://github.com/hideokamoto/wordpress-skills).

### GitHub CLI (`gh skill`)

```bash
gh skill install hideokamoto/wordpress-skills wordpress-handbook

# Pin a release
gh skill install hideokamoto/wordpress-skills wordpress-handbook --pin v0.1.0
```

### Vercel skills CLI (`npx skills`)

```bash
npx skills add hideokamoto/wordpress-skills --skill wordpress-handbook
```

## Run the scripts locally

From the skill root (the directory that contains `SKILL.md` and `scripts/`):

### 1. Search

```bash
python3 scripts/search.py "<query>" [handbook|all] [limit]
```

| Argument | Required | Notes |
|----------|----------|--------|
| `query` | Yes | Keywords |
| `handbook` | No | One of the shortnames above, or `all`. Omit to search all handbooks. |
| `limit` | No | Max results (default 5, max 20) |

Output: JSON array of `{ id, title, url, handbook, subtype }`.

Examples:

```bash
python3 scripts/search.py "custom post type"
python3 scripts/search.py "register_post_type" plugin
python3 scripts/search.py "naming conventions" coding 10
```

### 2. Fetch full content

Use `subtype` and `id` from a search hit:

```bash
python3 scripts/fetch_content.py "<subtype>" <id>
```

Output: JSON with `{ id, title, url, excerpt, content }` (HTML body in `content`).

```bash
python3 scripts/fetch_content.py plugin-handbook 11070
```

## Agent workflow (summary)

1. Search with `search.py`.
2. Share titles and URLs with the user.
3. If deeper detail is required, call `fetch_content.py` with the result’s `subtype` and `id`.
4. Parse or summarize the returned HTML as needed.

## Requirements

- **Python 3.x**
- **Network** access to `developer.wordpress.org` (HTTPS)

## Notes

- Search returns metadata (titles/URLs); full text comes from `fetch_content.py`.
- Responses are HTML; downstream tooling should strip or render appropriately.
- Omitting the handbook argument searches across handbooks—useful for broad topics.

## License

Apache-2.0 (see the parent repository).
