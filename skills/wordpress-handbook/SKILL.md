---
name: wordpress-handbook
description: Search WordPress official handbooks for development guidelines, coding standards, and best practices. Use when users ask about WordPress plugin development, theme development, REST API usage, block editor (Gutenberg), coding standards, or advanced administration. Triggers on questions like "How do I create a custom post type?", "What are WordPress coding standards?", "How does the block editor work?", or any WordPress development concept questions.
license: Apache-2.0
---

# WordPress Handbook Search

Search the official WordPress Developer Handbooks at developer.wordpress.org.

## Available Handbooks

| Shortname | Subtype | Description |
|-----------|---------|-------------|
| `plugin` | `plugin-handbook` | Plugin development guide |
| `theme` | `theme-handbook` | Theme development guide |
| `block` | `blocks-handbook` | Block Editor (Gutenberg) |
| `rest-api` | `rest-api-handbook` | REST API usage |
| `apis` | `apis-handbook` | Common APIs (Settings, Options, etc.) |
| `coding` | `wpcs-handbook` | WordPress Coding Standards |
| `admin` | `adv-admin-handbook` | Advanced Administration |

## Tools

### 1. Search Handbooks

```bash
python3 scripts/search.py "<query>" [handbook|all] [limit]
```

**Arguments:**
- `query` (required): Search keywords
- `handbook` (optional): Shortname from table above, or `all`. Omit to search all handbooks.
- `limit` (optional): Number of results (default: 5, max: 20)

**Output:** JSON array of `{id, title, url, handbook, subtype}`

**Examples:**
```bash
# Search all handbooks
python3 scripts/search.py "custom post type"

# Search only plugin handbook
python3 scripts/search.py "register_post_type" plugin

# Search coding standards with limit
python3 scripts/search.py "naming conventions" coding 10
```

### 2. Fetch Content

After finding a relevant result, fetch its full content:

```bash
python3 scripts/fetch_content.py "<subtype>" <id>
```

**Arguments:**
- `subtype` (required): Full subtype from search results (e.g., `plugin-handbook`)
- `id` (required): Article ID from search results

**Output:** JSON with `{id, title, url, excerpt, content}`

**Example:**
```bash
python3 scripts/fetch_content.py plugin-handbook 11070
```

## Workflow

1. Run `search.py` to find relevant articles
2. Present titles and URLs to user
3. If detailed content needed, use `id` and `subtype` from search results to run `fetch_content.py`
4. Extract key information from HTML content

## Notes

- Search API returns titles and URLs only; use `fetch_content.py` for full text
- Content is returned as HTML; parse as needed
- Cross-handbook search (omitting handbook parameter) is useful for broad topics
