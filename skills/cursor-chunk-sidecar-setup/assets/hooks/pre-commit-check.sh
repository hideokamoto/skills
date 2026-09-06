#!/usr/bin/env bash
# Cursor の beforeShellExecution フックから呼ばれるラッパー。
# `git commit` を実行しようとしたときだけ、Cloud Agent VM 上でローカルの
# 速いゲート（npm ci && npm test）を走らせる。sidecar 上の
# `chunk validate --remote`（本番 CI に近い検証）は stop フック側の役割なので、
# ここでは重複させず軽量チェックに留める。
#
# 要検証: beforeShellExecution の stdin JSON の形（コマンド文字列の
# フィールド名）と、コマンドを許可/ブロックする際の出力仕様（exit code /
# JSON のどちらで判定するか）は公式ドキュメント
# (https://cursor.com/docs/hooks.md) で必ず確認し、実際のフィールド名に
# 合わせて `COMMAND` の抽出ロジックを調整すること。ここでは
# `{"command": "..."}` という素直な形を仮定している。

set -uo pipefail

HOOK_INPUT="$(cat)"

# HOOK_INPUT を環境変数経由で渡す（文字列展開で python ソースに埋め込むと、
# コマンドにクォートが含まれた場合に壊れるため）。
COMMAND="$(HOOK_INPUT="$HOOK_INPUT" python3 -c "
import json, os
try:
    data = json.loads(os.environ.get('HOOK_INPUT', ''))
    print(data.get('command', ''))
except Exception:
    print('')
")"

case "$COMMAND" in
  *"git commit"*)
    echo "[pre-commit-check] git commit detected. Running npm ci && npm test locally." >&2
    if npm ci && npm test; then
      echo "[pre-commit-check] local gate passed." >&2
      exit 0
    else
      echo "[pre-commit-check] local gate failed. Blocking commit." >&2
      exit 1
    fi
    ;;
  *)
    # git commit 以外のコマンドはそのまま素通しする。
    exit 0
    ;;
esac
