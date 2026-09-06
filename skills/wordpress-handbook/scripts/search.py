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
    WordPress のハンドブックを検索し、結果またはエラーを JSON 文字列で返す。
    
    Parameters:
        query (str): 検索キーワード
        handbook (str, optional): 検索対象のハンドブック略称。省略時はすべてのハンドブックを対象とする。
        limit (int): 取得する結果数。CLI経由（main()）では範囲外の値は呼び出し前にエラーとして
            拒否されるため、ここに渡る値は通常 1〜20 に収まっている。この関数自身は
            プログラムから直接呼び出された場合の安全策として、値を 1〜20 の範囲に丸める。
    
    Returns:
        str: 検索結果またはエラー情報を含む整形済み JSON 文字列
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
    
    return json.dumps(results, ensure_ascii=False, indent=2)


def main():
    """
    コマンドライン引数を解析してハンドブックを検索し、JSON形式の結果を標準出力に出力する。
    """
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
        try:
            limit = int(sys.argv[3])
        except ValueError:
            print(json.dumps({"error": "Limit must be an integer"}, ensure_ascii=False, indent=2))
            sys.exit(1)

    if not (1 <= limit <= 20):
        print(json.dumps({"error": "Limit must be between 1 and 20"}, ensure_ascii=False, indent=2))
        sys.exit(1)

    print(search_handbook(query, handbook, limit))


if __name__ == "__main__":
    main()
