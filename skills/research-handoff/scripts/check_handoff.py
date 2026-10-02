#!/usr/bin/env python3
"""research-handoff の書式関門。

意味を判定しない。存在・位置・数・完全一致だけを見る。
意味の判定を足したくなったら、検査ではなく SKILL.md の書式を直す。

使い方:
    python3 check_handoff.py <成果物.md> [--forbidden <禁止値リスト.txt>]

終了コード:
    0  すべて通過
    1  1 件以上 FAIL
    2  引数・入出力の誤り
"""
import argparse
import re
import sys

HEADER_KEYS = ["受け手:", "用途:", "字数上限:"]

# 留保より後ろに置いてよい見出し。完全一致のみ。意味で判定しない。
TRAILING_ALLOW = {"出典", "参考", "参照", "付録"}


def load(path):
    """UTF-8 でファイルを読む。読めなければ exit 2。"""
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError as e:
        print(f"ERROR  {path} を読めない: {e}")
        sys.exit(2)


def check_header(lines):
    """先頭 3 行が固定キーで始まっているか。完全一致の前方一致のみ。"""
    fails = []
    for i, key in enumerate(HEADER_KEYS):
        actual = lines[i].strip() if i < len(lines) else ""
        if not actual.startswith(key):
            fails.append(f"{i + 1} 行目が `{key}` で始まっていない（実際: {actual[:40] or '空行'}）")
    return fails


def parse_limit(lines):
    """字数上限をヘッダから読む。戻り値は (上限, エラー)。

    `字数上限:` の行が無ければ (None, None)。ヘッダ欠落は check_header が FAIL にする。
    行があるのに値が数値だけでなければ (None, エラー文)。
    """
    for line in lines[:3]:
        s = line.strip()
        if s.startswith("字数上限:"):
            value = s[len("字数上限:"):].strip()
            if re.fullmatch(r"\d[\d,]*", value):
                return int(value.replace(",", "")), None
            return None, f"字数上限が数値のみで書かれていない（実際: {value[:20] or '空'}）"
    return None, None


def h2_headings(text):
    """`## ` で始まる見出しを出現順に返す。"""
    return [m.group(1).strip() for m in re.finditer(r"^##[ \t]+(.+?)[ \t]*$", text, re.M)]


def check_position(text):
    fails = []
    hs = h2_headings(text)
    if not hs:
        return ["`## ` 見出しが 1 つもない"]
    if hs[0] != "判定":
        fails.append(f"最初の `## ` 見出しが `判定` ではない（実際: `{hs[0]}`）")
    tail = [h for h in reversed(hs) if h not in TRAILING_ALLOW]
    if not tail or tail[0] != "留保":
        actual = tail[0] if tail else "（許可見出しのみ）"
        fails.append(
            f"`留保` が最後の本文見出しになっていない（実際: `{actual}`。"
            f"後置できるのは {'/'.join(sorted(TRAILING_ALLOW))} のみ）")
    return fails


def check_length(text, limit):
    """本文の字数を上限と比べる。上限が読めなかった場合の扱いは呼び出し側で決める。"""
    if limit is None:
        return [], ["字数上限をヘッダから読めなかったため未検査"]
    body = re.sub(r"\A(?:.*\n){0,3}", "", text, count=1)  # ヘッダ 3 行を除く
    n = len(body)
    if n > limit:
        return [f"字数 {n:,} > 上限 {limit:,}（超過 {n - limit:,}）"], []
    return [], [f"字数 {n:,} / 上限 {limit:,}"]


def check_owners(text):
    """各 `## 留保` 節の `- [未確定]` 行に `担当:` があるか。次の `## ` 見出しで節を閉じる。"""
    fails = []
    in_reserve = False
    for line in text.splitlines():
        m = re.match(r"##[ \t]+(.+?)[ \t]*$", line)
        if m:
            in_reserve = m.group(1) == "留保"
            continue
        s = line.strip()
        if in_reserve and s.startswith("- [未確定]") and "担当:" not in s:
            fails.append(f"未確定項目に担当がない: {s[:50]}")
    return fails


def check_forbidden(text, path):
    """禁止値リストの各行が本文に完全一致で現れていないか。"""
    if not path:
        return [], ["禁止値リストが渡されなかったため未検査"]
    raw = load(path)
    values = [v.strip() for v in raw.splitlines() if v.strip() and not v.startswith("#")]
    if not values:
        return [], ["禁止値リストが空のため未検査"]
    fails = [f"禁止値が印字されている: {v}" for v in values if v in text]
    return fails, [f"禁止値 {len(values)} 件を照合"]


def main():
    """引数を読み、各検査を走らせて結果を出力する。FAIL があれば 1 を返す。"""
    ap = argparse.ArgumentParser()
    ap.add_argument("target")
    ap.add_argument("--forbidden", default=None,
                    help="転記禁止・出典未確定の値を 1 行 1 件で並べたファイル")
    args = ap.parse_args()

    text = load(args.target)
    lines = text.splitlines()

    fails, notes = [], []
    fails += check_header(lines)
    fails += check_position(text)
    limit, limit_error = parse_limit(lines)
    if limit_error:
        fails.append(limit_error)
    f, n = check_length(text, limit)
    fails += f
    notes += [] if limit_error else n
    fails += check_owners(text)
    f, n = check_forbidden(text, args.forbidden)
    fails += f
    notes += n

    print(f"check_handoff  {args.target}")
    for x in notes:
        print(f"  NOTE  {x}")
    for x in fails:
        print(f"  FAIL  {x}")
    print("  OK" if not fails else f"  {len(fails)} FAIL")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
