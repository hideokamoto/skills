#!/usr/bin/env bash
# Cursor の beforeShellExecution フックから呼ばれるラッパー。
# `git commit` を実行しようとしたときだけ、Cloud Agent VM 上でローカルの
# 速いゲート（npm ci && npm test）を走らせる。sidecar 上の
# `chunk validate --remote`（本番 CI に近い検証）は stop フック側の役割なので、
# ここでは重複させず軽量チェックに留める。
#
# stdin JSON には command（実行しようとしているコマンド文字列全体）に加えて
# cwd、sandbox も含まれる（cursor.com/docs/hooks 記載、command のみ使用）。
#
# 出力仕様: beforeShellExecution はフックが JSON を返さない／異常終了した
# 場合はコマンドを通してしまう fail-open がデフォルト（hooks.json 側で
# failClosed を明示しない限り）。そのため、ここでは単に exit 1 するのではなく
# 必ず {"permission": "allow"|"deny", ...} を stdout に JSON で出す。
# exit code 2 も deny と等価に扱われる（Claude Code の PreToolUse 互換のため
# 用意されている仕様）ので、deny 時は JSON と exit 2 の両方を返し、
# どちらの解釈でもブロックされるようにしている。
# gate 自体の出力（npm ci / npm test のログ）は stdout の JSON を汚さないよう
# 常に stderr へ流す。

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
    if npm ci >&2 && npm test >&2; then
      echo "[pre-commit-check] local gate passed." >&2
      echo '{"permission":"allow"}'
      exit 0
    else
      echo "[pre-commit-check] local gate failed. Blocking commit." >&2
      python3 -c "
import json
print(json.dumps({
    'permission': 'deny',
    'user_message': 'npm ci / npm test failed, so the commit was blocked.',
    'agent_message': 'The local gate (npm ci && npm test) failed. Fix the failing tests before running git commit again.',
}))
"
      exit 2
    fi
    ;;
  *)
    # git commit 以外のコマンドはそのまま素通しする。
    echo '{"permission":"allow"}'
    exit 0
    ;;
esac
