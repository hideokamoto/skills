#!/usr/bin/env bash
# Cursor の stop フックから呼ばれるラッパー。
#
# なぜラッパーが要るか: 素の `chunk validate` は、標準入力が端末でない場合に
# Claude Code の Stop フック用ペイロード（session_id / stop_hook_active）を
# 探すために stdin を JSON デコードしようとする（chunk-cli の
# internal/cmd/validate.go の detectHook 実装）。呼び出し側が stdin を
# EOF まで送らずに開いたままにすると、この読み取りがブロックしたままになる。
# Cursor は stop フックの stdin にイベント JSON
# (`{"hook_event_name":"stop", "status":"completed", "loop_count":0, ...}`) を
# 流し込んでくるので、まずここで stdin を使い切ってから `chunk validate` を
# 呼ぶことでこの詰まりを避ける。
#
# 出力仕様（cursor.com/docs/hooks 記載）: stop フックは stdout に
# {"followup_message": "..."} を返すと、Cursor がそれを次のユーザー発言として
# 自動投稿し、エージェントに継続作業させる。followup_message を返さなければ
# セッションはそのまま終了してよいという扱いになる。exit code そのものに
# Claude Code の PreToolUse のような allow/deny の意味は無いため、ここでは
# 常に exit 0 とし、続けさせたいかどうかは followup_message の有無で制御する。
#
# ループ上限: chunk 自身の Claude Code 向け Stop フックも stopHookMaxAttempts
# のデフォルトを 3 にしている（chunk-cli docs/GETTING_STARTED.md）ので、
# それに倣い MAX_ATTEMPTS=3 とする。loop_count が上限に達したら
# followup_message を返さず（無限ループより、未検証のまま終了する方がまし）、
# stderr にだけ状況を残す。

set -uo pipefail

MAX_ATTEMPTS=3

# stdin (hook event JSON) を読み切って破棄する。ここを飛ばすと
# 後続の chunk コマンドが stdin 待ちでハングする原因になる（上記コメント参照）。
HOOK_INPUT="$(cat)"
echo "[chunk-validate-stop] hook input: ${HOOK_INPUT:-<empty>}" >&2

LOOP_COUNT="$(HOOK_INPUT="$HOOK_INPUT" python3 -c "
import json, os
try:
    data = json.loads(os.environ.get('HOOK_INPUT', ''))
    n = data.get('loop_count', 0)
    print(int(n))
except Exception:
    print(0)
")"

emit_followup() {
  # $1: message text
  python3 -c "
import json, sys
print(json.dumps({'followup_message': sys.argv[1]}))
" "$1"
}

if ! command -v chunk >/dev/null 2>&1; then
  echo "[chunk-validate-stop] chunk CLI not found. Run .cursor/setup-chunk.sh first." >&2
  # CLI が無いのはエージェントがループ内で直せる問題ではない（環境セットアップの
  # 不備）ので、無限に followup_message を出し続けない。loop_count が 0
  # （最初の stop）のときだけ一度知らせ、以降は黙って exit 0 にする。
  if [ "$LOOP_COUNT" -eq 0 ]; then
    emit_followup "chunk CLI was not found on PATH. Run .cursor/setup-chunk.sh (or check .cursor/environment.json's install step) before validating, then stop and re-run."
  fi
  exit 0
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
    # これも環境セットアップの不備であり、ループで直る話ではない。
    if [ "$LOOP_COUNT" -eq 0 ]; then
      emit_followup "No active chunk sidecar and no validation.sidecarImage is recorded in .chunk/config.json. Run the one-time sidecar setup/snapshot flow from the chunk-sidecar skill first, then stop again."
    fi
    exit 0
  fi
  echo "[chunk-validate-stop] No active sidecar. Creating from snapshot ${SIDECAR_IMAGE}."
  if ! chunk sidecar create --image "$SIDECAR_IMAGE"; then
    echo "[chunk-validate-stop] Failed to create a sidecar from snapshot ${SIDECAR_IMAGE}." >&2
    if [ "$LOOP_COUNT" -lt "$MAX_ATTEMPTS" ]; then
      emit_followup "Failed to create a chunk sidecar from snapshot ${SIDECAR_IMAGE}. Investigate and retry. Attempt $((LOOP_COUNT + 1)) of ${MAX_ATTEMPTS}."
    else
      echo "[chunk-validate-stop] Reached MAX_ATTEMPTS=${MAX_ATTEMPTS}; stopping without a followup_message to avoid an endless loop." >&2
    fi
    exit 0
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

echo "[chunk-validate-stop] validate failed." >&2
if [ "$LOOP_COUNT" -lt "$MAX_ATTEMPTS" ]; then
  echo "[chunk-validate-stop] Asking the agent to keep iterating (attempt $((LOOP_COUNT + 1)) of ${MAX_ATTEMPTS})." >&2
  emit_followup "chunk validate --remote failed on the sidecar. Fix the failing checks and re-run \`chunk sidecar sync && chunk validate --remote\`. Attempt $((LOOP_COUNT + 1)) of ${MAX_ATTEMPTS}."
else
  echo "[chunk-validate-stop] Reached MAX_ATTEMPTS=${MAX_ATTEMPTS}; stopping without a followup_message to avoid an endless loop. Validation is still failing." >&2
fi
exit 0
