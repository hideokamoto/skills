#!/usr/bin/env bash
# Chunk CLI と SSH 鍵を Cursor Cloud Agent VM 用にセットアップする。
#
# 背景: 公式ドキュメント
# (https://circleci.com/docs/guides/toolkit/install-and-configure-the-chunk-cli/)
# は Homebrew でのインストールしか案内していないが、Cursor Cloud Agent の VM には
# brew もこのスクリプトが生成する SSH 鍵も入っていない。そのため brew があれば
# それを使い、無ければ GitHub Releases から Linux バイナリを直接取得する。
#
# 要検証: GitHub Releases のアセット名（OS/arch の表記ゆれ）は変わりうる。
# 一致するアセットが見つからずに失敗した場合は、
# https://github.com/CircleCI-Public/chunk/releases を開いて
# ASSET マッチングの正規表現（下の python3 部分）を実際のファイル名に合わせて直すこと。

set -euo pipefail

CHUNK_REPO="CircleCI-Public/chunk"
INSTALL_DIR="${CHUNK_INSTALL_DIR:-$HOME/.local/bin}"
SSH_KEY="$HOME/.ssh/chunk_ai"

mkdir -p "$INSTALL_DIR"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) export PATH="$INSTALL_DIR:$PATH" ;;
esac

if command -v chunk >/dev/null 2>&1; then
  echo "[setup-chunk] chunk CLI is already installed: $(chunk --version)"
elif command -v brew >/dev/null 2>&1; then
  echo "[setup-chunk] Installing chunk via Homebrew"
  brew install CircleCI-Public/circleci/chunk
else
  echo "[setup-chunk] brew not found. Installing chunk from GitHub Releases."

  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64 | amd64) ARCH="x86_64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    *)
      echo "[setup-chunk] Unsupported architecture: $ARCH" >&2
      exit 1
      ;;
  esac

  API_URL="https://api.github.com/repos/${CHUNK_REPO}/releases/latest"
  ASSET_URL="$(
    curl -fsSL "$API_URL" | python3 -c "
import json, sys
data = json.load(sys.stdin)
os_name = '${OS}'
arch = '${ARCH}'
for asset in data.get('assets', []):
    name = asset['name'].lower()
    if os_name in name and arch in name:
        print(asset['browser_download_url'])
        break
"
  )"

  if [ -z "$ASSET_URL" ]; then
    echo "[setup-chunk] Could not find a release asset matching ${OS}/${ARCH}." >&2
    echo "[setup-chunk] Check https://github.com/${CHUNK_REPO}/releases and fix the matching logic above." >&2
    exit 1
  fi

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  echo "[setup-chunk] Downloading $ASSET_URL"
  curl -fsSL "$ASSET_URL" -o "$TMP_DIR/chunk.tar.gz"
  tar -xzf "$TMP_DIR/chunk.tar.gz" -C "$TMP_DIR"

  CHUNK_BIN="$(find "$TMP_DIR" -type f -name chunk | head -n1)"
  if [ -z "$CHUNK_BIN" ]; then
    echo "[setup-chunk] Downloaded archive did not contain a 'chunk' binary." >&2
    exit 1
  fi
  install -m 0755 "$CHUNK_BIN" "$INSTALL_DIR/chunk"
fi

command -v chunk >/dev/null 2>&1 || {
  echo "[setup-chunk] chunk still not on PATH after install (checked $INSTALL_DIR)." >&2
  exit 1
}
echo "[setup-chunk] $(chunk --version)"

# SSH 鍵: chunk sidecar add-ssh-key が使う鍵ペアを事前に用意する。
# 既にあれば何もしない。鍵の sidecar への登録自体は
# chunk-sidecar スキルの sync/validate ループの中で必要になった時に行われる。
if [ ! -f "$SSH_KEY" ]; then
  if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "[setup-chunk] ssh-keygen not found. Install openssh-client (e.g. 'apt-get install -y openssh-client')." >&2
    exit 1
  fi
  echo "[setup-chunk] Generating SSH key: $SSH_KEY"
  ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "chunk-ai@cursor-cloud-agent" -q
else
  echo "[setup-chunk] SSH key already present: $SSH_KEY"
fi

echo "[setup-chunk] Done. Run 'chunk config show' to confirm orgID / circleCIToken resolve correctly."
