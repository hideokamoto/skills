#!/usr/bin/env python3
"""Fetch full content of a WordPress handbook article."""

import sys
import json
import urllib.request
import urllib.parse
import urllib.error

# Valid handbook subtypes
VALID_SUBTYPES = {
    "plugin-handbook",
    "theme-handbook",
    "blocks-handbook",
    "rest-api-handbook",
    "apis-handbook",
    "wpcs-handbook",
    "adv-admin-handbook",
}


def fetch_content(subtype: str, article_id: int) -> str:
    """
    Fetch full content of a handbook article.
    
    Args:
        subtype: Full subtype (e.g., plugin-handbook)
        article_id: Article ID from search results
    
    Returns:
        JSON string with article content or error
    """
    if subtype not in VALID_SUBTYPES:
        return json.dumps({
            "error": f"Invalid subtype: {subtype}",
            "valid_subtypes": sorted(VALID_SUBTYPES)
        }, ensure_ascii=False, indent=2)
    
    base_url = f"https://developer.wordpress.org/wp-json/wp/v2/{subtype}/{article_id}"
    params = {"_fields": "id,title,content,link,excerpt"}
    url = f"{base_url}?{urllib.parse.urlencode(params)}"
    
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "WordPress-Handbook-Skill/1.0"})
        with urllib.request.urlopen(req, timeout=30) as response:
            data = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return json.dumps({"error": f"Article not found: {subtype}/{article_id}"}, ensure_ascii=False, indent=2)
        error_body = e.read().decode("utf-8") if e.fp else ""
        try:
            error_data = json.loads(error_body)
            return json.dumps({"error": error_data.get("message", str(e))}, ensure_ascii=False, indent=2)
        except json.JSONDecodeError:
            return json.dumps({"error": str(e)}, ensure_ascii=False, indent=2)
    except urllib.error.URLError as e:
        return json.dumps({"error": f"Network error: {e.reason}"}, ensure_ascii=False, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)}, ensure_ascii=False, indent=2)
    
    # Check for API error response
    if isinstance(data, dict) and "code" in data:
        return json.dumps({"error": data.get("message", "Unknown API error")}, ensure_ascii=False, indent=2)
    
    # Extract nested rendered values
    title = data.get("title", {})
    if isinstance(title, dict):
        title = title.get("rendered", "")
    
    content = data.get("content", {})
    if isinstance(content, dict):
        content = content.get("rendered", "")
    
    excerpt = data.get("excerpt", {})
    if isinstance(excerpt, dict):
        excerpt = excerpt.get("rendered", "")
    
    result = {
        "id": data.get("id"),
        "title": title,
        "url": data.get("link", ""),
        "excerpt": excerpt,
        "content": content
    }
    
    return json.dumps(result, ensure_ascii=False, indent=2)


def main():
    if len(sys.argv) < 3:
        print(json.dumps({
            "error": "Usage: fetch_content.py <subtype> <id>",
            "example": "fetch_content.py plugin-handbook 11070",
            "valid_subtypes": sorted(VALID_SUBTYPES)
        }, indent=2))
        sys.exit(1)
    
    subtype = sys.argv[1]
    try:
        article_id = int(sys.argv[2])
    except ValueError:
        print(json.dumps({"error": "ID must be an integer"}, indent=2))
        sys.exit(1)
    
    print(fetch_content(subtype, article_id))


if __name__ == "__main__":
    main()
