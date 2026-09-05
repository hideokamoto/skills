#!/usr/bin/env python3
"""Search WordPress official handbooks via REST API."""

import sys
import json
import urllib.request
import urllib.parse
import urllib.error

# Shortname to subtype mapping
HANDBOOK_MAP = {
    "plugin": "plugin-handbook",
    "theme": "theme-handbook",
    "block": "blocks-handbook",
    "rest-api": "rest-api-handbook",
    "apis": "apis-handbook",
    "coding": "wpcs-handbook",
    "admin": "adv-admin-handbook",
}

ALL_HANDBOOKS = ",".join(HANDBOOK_MAP.values())


def search_handbook(query: str, handbook: str = None, limit: int = 5) -> str:
    """
    Search WordPress handbooks.
    
    Args:
        query: Search keywords
        handbook: Shortname (plugin, theme, block, rest-api, apis, coding, admin)
                  or None for all handbooks
        limit: Max results (1-20)
    
    Returns:
        JSON string of results or error
    """
    base_url = "https://developer.wordpress.org/wp-json/wp/v2/search"
    
    # Validate and convert handbook shortname
    if handbook:
        if handbook not in HANDBOOK_MAP:
            return json.dumps({
                "error": f"Invalid handbook: {handbook}",
                "valid_options": list(HANDBOOK_MAP.keys())
            }, ensure_ascii=False, indent=2)
        subtype = HANDBOOK_MAP[handbook]
    else:
        subtype = ALL_HANDBOOKS
    
    # Clamp limit
    limit = max(1, min(20, limit))
    
    params = {
        "search": query,
        "subtype": subtype,
        "per_page": limit,
        "_fields": "id,title,url,subtype"
    }
    
    url = f"{base_url}?{urllib.parse.urlencode(params)}"
    
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "WordPress-Handbook-Skill/1.0"})
        with urllib.request.urlopen(req, timeout=30) as response:
            data = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
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
    
    # Transform results
    results = []
    for item in data:
        subtype_raw = item.get("subtype", "")
        # Convert subtype back to shortname for readability
        handbook_name = subtype_raw
        for short, full in HANDBOOK_MAP.items():
            if full == subtype_raw:
                handbook_name = short
                break
        
        results.append({
            "id": item.get("id"),
            "title": item.get("title", ""),
            "url": item.get("url", ""),
            "handbook": handbook_name,
            "subtype": subtype_raw  # Keep original for fetch_content.py
        })
    
    if not results:
        return json.dumps({"message": "No results found", "results": []}, ensure_ascii=False, indent=2)
    
    return json.dumps(results, ensure_ascii=False, indent=2)


def main():
    if len(sys.argv) < 2:
        print(json.dumps({
            "error": "Usage: search.py <query> [handbook|all] [limit]",
            "handbooks": list(HANDBOOK_MAP.keys()) + ["all"]
        }, indent=2))
        sys.exit(1)
    
    query = sys.argv[1]
    handbook = None
    limit = 5
    
    if len(sys.argv) > 2:
        arg2 = sys.argv[2]
        # If arg2 is a number, treat it as limit (for "search.py query 10" usage)
        if arg2.isdigit():
            limit = int(arg2)
        elif arg2.lower() == "all":
            handbook = None  # Explicit all-handbook search
        else:
            handbook = arg2
    
    if len(sys.argv) > 3:
        limit = int(sys.argv[3])
    
    print(search_handbook(query, handbook, limit))


if __name__ == "__main__":
    main()
