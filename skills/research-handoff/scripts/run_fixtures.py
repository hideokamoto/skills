#!/usr/bin/env python3
"""check_handoff.py をフィクスチャに対して走らせ、期待した終了コードと一致するかを判定する。

使い方:
    python3 scripts/run_fixtures.py

終了コード:
    0  全件が期待どおり
    1  1 件以上が期待と不一致
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(os.path.dirname(HERE), "references", "fixtures")
CHECKER = os.path.join(HERE, "check_handoff.py")
FORBIDDEN = os.path.join(FIX, "forbidden.txt")

# (ファイル, 期待 exit, 何を確かめるか)
CASES = [
    ("pass.md", 0, "書式に適合した成果物が誤検知なしで通ること"),
    ("fail_header.md", 1, "ヘッダ 3 行の欠落を検出すること"),
    ("fail_position.md", 1, "判定が先頭でない・留保が最後でないことを検出すること"),
    ("fail_position_head.md", 1, "判定が先頭でないことだけを検出すること"),
    ("fail_position_tail.md", 1, "留保が最後でないことだけを検出すること"),
    ("fail_heading_newline.md", 1, "`##` の次の行にある語を見出しとして扱わないこと"),
    ("fail_limit.md", 1, "字数上限が数値でないことを検出すること"),
    ("pass_appendix.md", 0, "付録の担当なし項目を留保の検査に含めないこと"),
    ("fail_owner.md", 1, "未確定項目の担当欠落を検出すること"),
    ("fail_length.md", 1, "字数上限の超過を検出すること"),
    ("fail_forbidden.md", 1, "禁止値の印字を検出すること"),
]


def main():
    """全フィクスチャを検査し、期待した終了コードと一致しない件数を数える。"""
    mismatch = 0
    for name, want, what in CASES:
        p = subprocess.run(
            [sys.executable, CHECKER, os.path.join(FIX, name), "--forbidden", FORBIDDEN],
            capture_output=True, text=True,
        )
        ok = p.returncode == want
        mismatch += 0 if ok else 1
        print(f"{'一致' if ok else '不一致'}  {name}  期待 exit={want} 実測 exit={p.returncode}  {what}")
        if not ok:
            print((p.stdout + p.stderr).rstrip())
    print(f"\n{len(CASES)} 件中、不一致 {mismatch} 件")
    return 1 if mismatch else 0


if __name__ == "__main__":
    sys.exit(main())
