#!/usr/bin/env bash
# Cursor の stop フックから呼ばれるラッパー。
#
# なぜラッパーが要るか: 素の `chunk validate` は追加の stdin JSON を待って
# ハングすることがある。Cursor は stop フックの stdin にイベント JSON
# (`{"hook_event_name":"stop", ...}`) を流し込んでくるが、これを
# `chunk validate` にそのまま渡すとブロックしてしまう。まずここで stdin を
# 使い切ってから `chunk validate --remote` を呼ぶ。
#
# 終了コードの意味（Cursor 側の規約は要確認 — このリポジトリの運用実績値）:
#   0 : 検証成功。stop してよい。
#   2 : 検証失敗。エージェントに修正を続けさせたい。
#
# 要検証: stop フックの exit code の意味づけは公式ドキュメント
# (https://cursor.com/docs/hooks.md) で必ず確認すること。ネットワーク制限で
# このスキル作成時には一次情報を直接確認できていない。

set -uo pipefail

# stdin (hook event JSON) を読み切って破棄する。ここを飛ばすと
# 後続の chunk コマンドが stdin 待ちでハングする原因になる。
HOOK_INPUT="$(cat)"
echo "[chunk-validate-stop] hook input: ${HOOK_INPUT:-<empty>}" >&2

if ! command -v chunk >/dev/null 2>&1; then
  echo "[chunk-validate-stop] chunk CLI not found. Run .cursor/setup-chunk.sh first." >&2
  exit 2
fi

# active な sidecar が無ければ、.chunk/config.json の
# validation.sidecarImage から作り直す（chunk-sidecar スキルの Step 2 と同じ手順）。
#
# 注意: `chunk sidecar current` は active な sidecar が無くても exit code 0 を
# 返す（メッセージだけで判別する仕様）。`--json` は無い場合に `{}` を返すので、
# こちらで判定する。
HAS_ACTIVE_SIDECAR="$(chunk sidecar current --json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
print('yes' if data else 'no')
")"
if [ "$HAS_ACTIVE_SIDECAR" != "yes" ]; then
  SIDECAR_IMAGE="$(python3 -c "
import json
try:
    with open('.chunk/config.json') as f:
        cfg = json.load(f)
    print(cfg.get('validation', {}).get('sidecarImage', ''))
except FileNotFoundError:
    print('')
")"
  if [ -z "$SIDECAR_IMAGE" ]; then
    echo "[chunk-validate-stop] No active sidecar and no validation.sidecarImage in .chunk/config.json." >&2
    echo "[chunk-validate-stop] Run the one-time sidecar setup/snapshot flow first (see chunk-sidecar skill)." >&2
    exit 2
  fi
  echo "[chunk-validate-stop] No active sidecar. Creating from snapshot ${SIDECAR_IMAGE}."
  if ! chunk sidecar create --image "$SIDECAR_IMAGE"; then
    echo "[chunk-validate-stop] Failed to create a sidecar from snapshot ${SIDECAR_IMAGE}." >&2
    exit 2
  fi
fi

sync_and_validate() {
  chunk sidecar sync && chunk validate --remote
}

if sync_and_validate; then
  echo "[chunk-validate-stop] validate passed."
  exit 0
fi

# sync/validate が SSH 鍵未登録で失敗している可能性があるので、鍵を登録して
# 1 回だけ再試行する。
SSH_PUB="$HOME/.ssh/chunk_ai.pub"
if [ -f "$SSH_PUB" ]; then
  echo "[chunk-validate-stop] Retrying once after registering SSH key."
  chunk sidecar add-ssh-key --public-key-file "$SSH_PUB" || true
  if sync_and_validate; then
    echo "[chunk-validate-stop] validate passed on retry."
    exit 0
  fi
fi

echo "[chunk-validate-stop] validate failed. Leaving it to the agent to fix and retry." >&2
exit 2
