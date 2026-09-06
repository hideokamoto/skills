#!/usr/bin/env bash
# Chunk CLI と SSH 鍵を Cursor Cloud Agent VM 用にセットアップする。
#
# 背景: 公式ドキュメント
# (https://circleci.com/docs/guides/toolkit/install-and-configure-the-chunk-cli/)
# は Homebrew でのインストールしか案内していないが、Cursor Cloud Agent の VM には
# brew もこのスクリプトが生成する SSH 鍵も入っていない。そのため brew があれば
# それを使い、無ければ GitHub Releases から Linux バイナリを直接取得する。
#
# リポジトリ名は CircleCI-Public/chunk-cli （CircleCI-Public/chunk は存在しない）。
# アセット名のテンプレートは chunk-cli リポジトリの .goreleaser.yaml
# ({ProjectName}_{Os with initial capital}_{x86_64|arm64}.tar.gz、ProjectName は
# "chunk-cli"）から決まる固定形式なので、GitHub API を叩いてアセット一覧を
# JSON パースする必要はなく、latest/download の URL を直接組み立てられる。
# 404 になった場合は .goreleaser.yaml が変わった可能性があるので
# https://github.com/CircleCI-Public/chunk-cli/blob/main/.goreleaser.yaml を
# 見て命名規則を確認し、下の URL 組み立てを合わせる。

set -euo pipefail

CHUNK_REPO="CircleCI-Public/chunk-cli"
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

  OS_RAW="$(uname -s)"
  case "$OS_RAW" in
    Linux) OS_TITLE="Linux" ;;
    Darwin) OS_TITLE="Darwin" ;;
    *)
      echo "[setup-chunk] Unsupported OS: $OS_RAW" >&2
      exit 1
      ;;
  esac

  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64 | amd64) ARCH="x86_64" ;;
    aarch64 | arm64) ARCH="arm64" ;;
    *)
      echo "[setup-chunk] Unsupported architecture: $ARCH" >&2
      exit 1
      ;;
  esac

  # goreleaser のテンプレート: {ProjectName}_{Os}_{Arch}.tar.gz
  ASSET_NAME="chunk-cli_${OS_TITLE}_${ARCH}.tar.gz"
  ASSET_URL="https://github.com/${CHUNK_REPO}/releases/latest/download/${ASSET_NAME}"

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  echo "[setup-chunk] Downloading $ASSET_URL"
  if ! curl -fsSL "$ASSET_URL" -o "$TMP_DIR/chunk.tar.gz"; then
    echo "[setup-chunk] Failed to download ${ASSET_NAME}." >&2
    echo "[setup-chunk] Check https://github.com/CircleCI-Public/chunk-cli/releases for the actual asset name and adjust ASSET_NAME above if the naming template changed." >&2
    exit 1
  fi
  tar -xzf "$TMP_DIR/chunk.tar.gz" -C "$TMP_DIR"

  # アーカイブ直下に chunk バイナリが置かれる（LICENSE, README.md,
  # share/bash-completion/completions/chunk 等も同梱される）。
  # share/bash-completion/completions/chunk も同じファイル名 "chunk" なので、
  # `find -name chunk` で探すとそちらを拾ってしまうことがある。直下の
  # ファイルを直接指定する。
  CHUNK_BIN="$TMP_DIR/chunk"
  if [ ! -f "$CHUNK_BIN" ]; then
    echo "[setup-chunk] Downloaded archive did not contain a top-level 'chunk' binary." >&2
    echo "[setup-chunk] Check https://github.com/CircleCI-Public/chunk-cli/releases and the archive layout." >&2
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
