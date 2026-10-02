#!/usr/bin/env bash
# Claude Code on the web のコンテナで chunk sidecar の ssh と sync を両方使えるようにする。
#
# 何度実行しても同じ結果になる（冪等）。やることは3つ:
#
# 1. rsync と OpenSSH クライアントを入れる。
#    `chunk sidecar sync` は内部で外部コマンドの
#      rsync --archive --delete --filter=":- .gitignore" \
#        -e "ssh -p <中継ポート> ... -i ~/.ssh/chunk_ai" <git ルート>/ user@127.0.0.1:<git ルート>
#    を呼ぶ。一方 `chunk sidecar ssh` は外部の ssh を使わないので、web のコンテナでは
#    「ssh は通るのに sync だけ失敗する」状態になる。
#    また web のコンテナはパッケージ一覧が古いことがあり、apt-get update なしだと
#    openssh-client の取得が 404 になった（2026-10 時点で実際に発生）。
#
# 2. chunk CLI が無ければ GitHub Releases から入れる。
#    導入処理は hideokamoto/skills の cursor-chunk-sidecar-setup/assets/setup-chunk.sh
#    から流用した（スキルは個別にインストールされるのでファイルは共有できない）。
#    web のコンテナでは releases/latest/download/<アセット名> の直接 URL は取得できたが、
#    Releases のページや api.github.com は 403 だった。
#
# 3. ~/.ssh/chunk_ai を OpenSSH が読める形式にそろえる。
#    chunk（v0.7.192）が自分で作る鍵は PKCS#8 形式の ed25519
#    （先頭行が "-----BEGIN PRIVATE KEY-----"）で、OpenSSH 9.6 はこれを
#    "invalid format" として読めない。chunk 自身は OpenSSH 形式の鍵も読めるので、
#    OpenSSH 形式にそろえれば ssh と sync の両方が動く。鍵を作り直しても、
#    古い鍵で作った既存の sidecar に add-ssh-key なしで接続できることを実機で確認済み。

set -euo pipefail

log() { echo "[setup-claude-web] $*" >&2; }

SSH_DIR="$HOME/.ssh"
SSH_KEY="$SSH_DIR/chunk_ai"
CHUNK_REPO="CircleCI-Public/chunk-cli"

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  log "CLAUDE_CODE_REMOTE=true ではない（Claude Code on the web 以外の可能性）。処理は続けるが、このスクリプトは web のコンテナ（Ubuntu・root）向けに検証している。"
fi

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  fi
fi

# ---- 1. rsync / openssh-client -------------------------------------------
missing=()
command -v rsync >/dev/null 2>&1 || missing+=(rsync)
command -v ssh >/dev/null 2>&1 || missing+=(openssh-client)

if [ "${#missing[@]}" -gt 0 ]; then
  if ! command -v apt-get >/dev/null 2>&1; then
    log "apt-get が無いため ${missing[*]} を入れられない。手動で導入してから再実行する。"
    exit 1
  fi
  log "導入する: ${missing[*]}"
  export DEBIAN_FRONTEND=noninteractive
  if ! $SUDO apt-get install -y -q "${missing[@]}" >/dev/null 2>&1; then
    log "初回の導入に失敗した。パッケージ一覧が古い可能性があるので apt-get update してやり直す。"
    $SUDO apt-get update -q >/dev/null
    $SUDO apt-get install -y -q "${missing[@]}" >/dev/null
  fi
fi
log "rsync: $(rsync --version | head -1)"
log "ssh: $(ssh -V 2>&1)"

# ---- 2. chunk CLI ---------------------------------------------------------
if command -v chunk >/dev/null 2>&1; then
  log "chunk は導入済み: $(chunk --version)"
else
  # root なら PATH に最初から入っている /usr/local/bin に置く。
  # ~/.local/bin は Claude Code の Bash ツールの PATH に入っていないことがある。
  if [ -n "${CHUNK_INSTALL_DIR:-}" ]; then
    INSTALL_DIR="$CHUNK_INSTALL_DIR"
  elif [ -w /usr/local/bin ]; then
    INSTALL_DIR="/usr/local/bin"
  else
    INSTALL_DIR="$HOME/.local/bin"
  fi
  mkdir -p "$INSTALL_DIR"

  case "$(uname -m)" in
    x86_64 | amd64) ARCH="x86_64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    *) log "未対応のアーキテクチャ: $(uname -m)"; exit 1 ;;
  esac
  # goreleaser のテンプレート {ProjectName}_{Os}_{Arch}.tar.gz（ProjectName は chunk-cli）
  ASSET_URL="https://github.com/${CHUNK_REPO}/releases/latest/download/chunk-cli_Linux_${ARCH}.tar.gz"

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  log "chunk を取得する: $ASSET_URL"
  if ! curl -fsSL "$ASSET_URL" -o "$TMP_DIR/chunk.tar.gz"; then
    log "chunk の取得に失敗した。ネットワークの許可設定で github.com と release-assets.githubusercontent.com が通るか確認する。"
    exit 1
  fi
  tar -xzf "$TMP_DIR/chunk.tar.gz" -C "$TMP_DIR"
  # アーカイブには share/bash-completion/completions/chunk も入っているので、
  # find で探さず直下のファイルを直接指定する。
  if [ ! -f "$TMP_DIR/chunk" ]; then
    log "アーカイブの直下に chunk バイナリが無い。リリースの構成が変わった可能性がある。"
    exit 1
  fi
  install -m 0755 "$TMP_DIR/chunk" "$INSTALL_DIR/chunk"
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *) log "注意: $INSTALL_DIR が PATH に入っていない。export PATH=\"$INSTALL_DIR:\$PATH\" が必要。"
       export PATH="$INSTALL_DIR:$PATH" ;;
  esac
  log "chunk を導入した: $(chunk --version)"
fi

# ---- 3. ~/.ssh/chunk_ai を OpenSSH 形式にそろえる ---------------------------
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

fingerprint() { ssh-keygen -lf "$1" 2>/dev/null | awk '{print $2}'; }

regenerate_key() {
  rm -f "$SSH_KEY" "$SSH_KEY.pub"
  ssh-keygen -q -t ed25519 -N "" -C "chunk-ai@claude-code-web" -f "$SSH_KEY"
  log "OpenSSH 形式の鍵を作った: $(fingerprint "$SSH_KEY.pub")"
}

if [ ! -f "$SSH_KEY" ]; then
  # 鍵が無いまま chunk を使うと、chunk が PKCS#8 形式で作ってしまうので先に作る。
  log "鍵が無いので作る: $SSH_KEY"
  regenerate_key
elif ssh-keygen -y -P "" -f "$SSH_KEY" >/dev/null 2>&1; then
  log "鍵は OpenSSH で読める形式: $(fingerprint "$SSH_KEY.pub")"
else
  BACKUP="$SSH_KEY.bak.$(date +%Y%m%d%H%M%S)"
  cp -p "$SSH_KEY" "$BACKUP"
  [ -f "$SSH_KEY.pub" ] && cp -p "$SSH_KEY.pub" "$BACKUP.pub"
  log "鍵が OpenSSH で読めない（chunk が作る PKCS#8 形式とみられる）。元の鍵を退避した: $BACKUP"

  converted="no"
  if head -1 "$SSH_KEY" | grep -q "BEGIN PRIVATE KEY" \
    && python3 -c "import cryptography" >/dev/null 2>&1; then
    # 同じ鍵のまま形式だけ変える。公開鍵（指紋）は変わらない。
    if SSH_KEY="$SSH_KEY" python3 - <<'PY'
import os
from cryptography.hazmat.primitives import serialization as s
path = os.environ["SSH_KEY"]
key = s.load_pem_private_key(open(path, "rb").read(), password=None)
tmp = path + ".tmp"
with open(tmp, "wb") as f:
    f.write(key.private_bytes(s.Encoding.PEM, s.PrivateFormat.OpenSSH, s.NoEncryption()))
os.chmod(tmp, 0o600)
os.replace(tmp, path)
PY
    then
      ssh-keygen -y -f "$SSH_KEY" > "$SSH_KEY.pub.new"
      if [ ! -f "$SSH_KEY.pub" ] || [ "$(fingerprint "$SSH_KEY.pub.new")" = "$(fingerprint "$SSH_KEY.pub")" ]; then
        mv "$SSH_KEY.pub.new" "$SSH_KEY.pub"
        converted="yes"
        log "同じ鍵を OpenSSH 形式に変換した: $(fingerprint "$SSH_KEY.pub")"
      else
        rm -f "$SSH_KEY.pub.new"
        log "変換後の指紋が元の公開鍵と一致しなかったので、作り直しに切り替える。"
      fi
    fi
  fi

  if [ "$converted" != "yes" ]; then
    # python の cryptography が無い・形式が想定外などの場合は作り直す。
    # 作り直した鍵でも、既存の sidecar に add-ssh-key なしで接続できることを確認済み。
    regenerate_key
  fi
fi
chmod 600 "$SSH_KEY"

log "完了。動作確認: chunk sidecar sync を実行し、sidecar 上でファイルが届いたかを chunk sidecar ssh -- ls で見る。"
