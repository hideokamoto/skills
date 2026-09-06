---
name: cursor-chunk-sidecar-setup
description: Claude Code 向けに chunk init 済み・chunk sidecar 検証済みのリポジトリを、Cursor Cloud Agent でも同じように sidecar 検証できるようにセットアップする。Cursor Cloud Agent VM には CLI も SSH 鍵も無く、Claude Code の .claude/settings.json の hooks も読まれず、素の chunk validate は stdin JSON 待ちでハングしうる、という3つのズレを .cursor/environment.json・.cursor/hooks.json・セットアップスクリプト・stop フックラッパーで埋める。「Cursor Cloud Agent で chunk を使えるようにして」「Cursor で sidecar 検証したい」「Claude Code の hook を Cursor に移植して」「Cursor Cloud Agent が CIRCLECI_TOKEN を見つけられない」「chunk validate が Cursor でハングする」といった相談では、明示的に名指しされていなくても必ずこのスキルを使うこと。
---

# Cursor Cloud Agent × Chunk Sidecar セットアップ

Claude Code の `.claude/settings.json` hooks で `chunk validate` を回している
リポジトリを、Cursor Cloud Agent でも同じように動かすためのセットアップ手順。
`chunk-sidecar` スキル（sync → validate のループそのもの）の上に乗る、
Cursor 固有の配線を担当する。

## 背景（なぜそのままでは動かないか）

| Claude Code | Cursor Cloud Agent |
|-------------|-------------------|
| `.claude/settings.json` の hooks | **`.cursor/hooks.json` のみ**が読まれる |
| `Stop` → `chunk validate` | 素の `chunk validate` は **stdin JSON 待ちでハング**しうる |
| ローカルに CLI / SSH 鍵がある想定 | VM には **CLI も `~/.ssh/chunk_ai` も無い** |

プロダクトバグというより、**hook の前提と Cloud Agent VM の前提のずれ**。

## 前提

- CircleCI の Chunk / sidecar が使える org であること
- リポジトリに `.chunk/config.json` があること（無ければ `chunk init` が先）
- `chunk-sidecar` スキルで、少なくとも一度は sidecar のセットアップ・スナップショット作成に成功していること

## Step 0: CircleCI org ID を確認する（対話が必須・org ID は絶対にハードコードしない）

このスキルは誰の環境にも配れる汎用テンプレートであり、特定の CircleCI org ID を
コードやドキュメントに埋め込むと、他人のリポジトリで実行したときに間違った
org を叩いてしまう。`chunk-sidecar` スキルの preflight と同じ考え方で進める。

1. `cat .chunk/config.json` を見て `orgID` が非空か確認する。
2. 設定済みなら何もせず先に進む（ユーザーに聞き直す必要はない）。
3. 未設定なら、**一度だけ**ユーザーに次のメッセージで尋ねる。CircleCI ダッシュボードや
   `circleci-cli` スキルで調べてもらってよい:

   > `.chunk/config.json` に CircleCI の orgID がありません。Cursor Cloud Agent の
   > 非対話セッションでは org を選択できないため、CircleCI の org ID を教えてください。
   > 次回以降のために `chunk config set orgID <id>` で永続化します。

4. 回答を受け取ったら `chunk config set orgID <id>` を実行し、Step 1 に進む。

**絶対にしないこと**: どこかで見た org ID（自分の環境や別リポジトリの値、会話履歴に
たまたま出てきた値）を確認なしに書き込むこと。org ID は必ずこの Step で本人から
取得したものを使う。

## Step 1: ファイルを配置する

`assets/` 配下のテンプレートをリポジトリの `.cursor/` にコピーする。

```text
.cursor/
  environment.json               # install で setup を実行
  setup-chunk.sh                 # Chunk CLI + SSH 鍵
  hooks.json                     # Cursor hooks の登録
  hooks/
    pre-commit-check.sh          # beforeShellExecution: git commit をローカルゲート
    chunk-validate-stop.sh       # stop: sidecar 上で chunk validate --remote
```

コピー後、実行権限を付ける:

```bash
chmod +x .cursor/setup-chunk.sh .cursor/hooks/*.sh
```

### hooks の役割

1. **`beforeShellExecution`（`git commit`）** — `pre-commit-check.sh` が
   Cloud Agent VM 上で `npm ci && npm test`（速いローカルゲート）を走らせる。
   `git commit` 以外のコマンドはそのまま素通しする。
2. **`stop`** — `chunk-validate-stop.sh` が stdin の hook イベント JSON を
   読み切ってから sidecar 上で `chunk validate --remote`（本番 CI に近い検証）を
   実行する。stdin を読み切らずに `chunk validate` へそのまま流すとハングするので、
   このドレインが本体。

### 検証状況（正直に書いておく）

このテンプレートを書いた時点で、`cursor.com` への外部アクセスがネットワーク制限で
できず、Cursor Hooks の公式スキーマ（`hooks.json` のトップレベル構造、
`beforeShellExecution` の stdin フィールド名、ブロック判定の仕様）を一次情報で
確認できていない。`hooks.json` の形と `pre-commit-check.sh` の JSON パース部分には
「要検証」とコメントを入れてある。**このスキルを実行する Claude は、配置後に
必ず https://cursor.com/docs/hooks.md を取得して突き合わせ、フィールド名や
判定方式が違えば実際の仕様に合わせて直すこと。** シェルスクリプト自体は
`bash -n` で構文チェック済み、JSON ファイルは構文検証済みだが、実際の
Cursor Cloud Agent VM 上で hooks 経由で動かして確認したものではない。

## Step 2: Secret を設定する

Cloud Agent のダッシュボードの Secrets に:

- `CIRCLECI_TOKEN` … CircleCI Personal API Token

を追加する。`chunk config show` で `Environment variable (CIRCLECI_TOKEN)` と
表示されれば認識されている。

## Step 3: セットアップの動作確認

`.cursor/environment.json` が効いていれば、セッション開始時の install で
`npm ci && .cursor/setup-chunk.sh` が走る。効いていない場合は手動実行:

```bash
bash .cursor/setup-chunk.sh
```

確認:

```bash
chunk --version
test -f ~/.ssh/chunk_ai && echo "ssh key ok"
chunk config show   # circleCIToken / orgID が解決されること
```

stop hook を模してラッパーを直接叩いてみる（推奨・1回）:

```bash
echo '{"hook_event_name":"stop"}' | .cursor/hooks/chunk-validate-stop.sh
```

成功時の目安:

- active sidecar が無ければ `.chunk/config.json` の `validation.sidecarImage` から作成
- sync → remote `chunk validate` が走る
- exit code `0`

失敗時は exit `2`（エージェントに修正を続けさせる想定。**要検証**: この exit code の
意味づけは Cursor 側の規約と突き合わせること）。

## Step 4: 仕上げ — sidecar/snapshot の実地確認

ここから先のロジックは `chunk-sidecar` スキールにすべて委譲する。重複実装しない。

1. `chunk sidecar current` で active な sidecar があるか確認する。
2. 無ければ `chunk-sidecar` スキルの Step 2/3（sidecar の作成、`chunk validate` での
   健全性確認、`chunk sidecar snapshot create` でのスナップショット作成、
   `.chunk/config.json` の `validation.sidecarImage` への記録）を実行する。
3. 最後に、実際にテストが動くところまで確認する: `chunk validate`（または
   `chunk sidecar ssh -- npm test`）を実行し、exit code 0 になることを見る。
   ここを「たぶん動く」で済ませず、実際に走らせた出力をユーザーに見せること
   （検証主義: 仮説は実装して確かめる、推測で済ませない）。

## エージェント作業中の推奨フロー

stop hook に任せてもよいが、明示実行するなら:

```bash
chunk sidecar sync
chunk validate --remote
# または
chunk sidecar ssh -- npm test
```

**使わない方がよいもの**

| 避け方 | 理由 |
|--------|------|
| 素の `chunk validate`（stdin 未処理） | Cursor hook / TTY でハングしうる |
| `chunk sidecar exec --command "..."`（長時間） | 同期 HTTP で短いタイムアウトになりやすい |
| `.claude/settings.json` だけに依存 | Cloud Agent は読まない |

## トラブルシュート

| 症状 | 確認 |
|------|------|
| `chunk: command not found` | `.cursor/setup-chunk.sh` を実行。`environment.json` の install が走っているか |
| `SSH key not found: ~/.ssh/chunk_ai` | setup 再実行、またはラッパー実行（鍵を自動生成する） |
| `circleCIToken: (not set)` | Secret `CIRCLECI_TOKEN` を追加してセッション再起動 |
| `orgID` が解決できない / org 選択でハング | Step 0 に戻り、ユーザーに org ID を一度だけ確認して `chunk config set orgID <id>` |
| `chunk validate` が無出力で止まる | stdin を渡せているか。必ずラッパーか `cat >/dev/null` 経由で `--remote` |
| sync / validate が path で落ちる | active sidecar を `chunk sidecar current` で確認。必要なら snapshot から作り直す |
| `sidecar exec` が timeout | `chunk sidecar ssh -- <cmd>` を使う |
| hooks が発火しない / 挙動が説明と違う | `hooks.json` のスキーマが実際の Cursor 仕様とズレている可能性。`cursor.com/docs/hooks.md` を取得して突き合わせる |

## ファイル対応表（Claude → Cursor）

| Claude Code | Cursor Cloud Agent |
|-------------|-------------------|
| `.claude/settings.json` → `Stop` → `chunk validate` | `.cursor/hooks/chunk-validate-stop.sh` → `chunk validate --remote` |
| `.claude/settings.json` → `PreToolUse` / git commit | `.cursor/hooks.json` → `beforeShellExecution` / `git commit` |
| ローカル Homebrew 等の CLI | `.cursor/setup-chunk.sh`（brew があれば brew、無ければ GitHub Releases から Linux バイナリ） |

## 参考

- [Cursor Hooks](https://cursor.com/docs/hooks.md)（Cloud agent support）— **要一次情報確認**
- [Cursor Cloud Environment Setup](https://cursor.com/docs/cloud-agent/setup) — **要一次情報確認**
- [Chunk CLI](https://circleci.com/docs/guides/toolkit/install-and-configure-the-chunk-cli/)
- CircleCI: [Wire Chunk sidecars into agent hooks](https://circleci.com/blog/chunk-sidecar-agent-hooks/)
- `chunk-sidecar` スキル（sync → validate のループ、sidecar 作成・スナップショット手順の一次情報源）
