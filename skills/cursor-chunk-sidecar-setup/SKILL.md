---
name: cursor-chunk-sidecar-setup
description: Claude Code 向けに chunk init 済み・chunk sidecar 検証済みのリポジトリを、Cursor Cloud Agent でも同じように sidecar 検証できるようにセットアップする。Cursor Cloud Agent VM には CLI も SSH 鍵も無く、Cloud Agent のドキュメントが挙げるのは .cursor/hooks.json のみで .claude/settings.json の hooks は前提にできず、素の chunk validate は stdin JSON 待ちでハングしうる、という3つのズレを .cursor/environment.json・.cursor/hooks.json・セットアップスクリプト・stop フックラッパーで埋める。「Cursor Cloud Agent で chunk を使えるようにして」「Cursor で sidecar 検証したい」「Claude Code の hook を Cursor に移植して」「Cursor Cloud Agent が CIRCLECI_TOKEN を見つけられない」「chunk validate が Cursor でハングする」といった相談では、明示的に名指しされていなくても必ずこのスキルを使うこと。
---

# Cursor Cloud Agent × Chunk Sidecar セットアップ

Claude Code の `.claude/settings.json` hooks で `chunk validate` を回している
リポジトリを、Cursor Cloud Agent でも同じように動かすためのセットアップ手順。
`chunk-sidecar` スキル（sync → validate のループそのもの）の上に乗る、
Cursor 固有の配線を担当する。

## 背景（なぜそのままでは動かないか）

| Claude Code | Cursor Cloud Agent |
|-------------|-------------------|
| `.claude/settings.json` の hooks | Cloud Agent のドキュメントが挙げているのは **`.cursor/hooks.json`** のみ |
| `Stop` → `chunk validate` | 素の `chunk validate` は **stdin JSON 待ちでハング**しうる |
| ローカルに CLI / SSH 鍵がある想定 | VM には **CLI も `~/.ssh/chunk_ai` も無い** |

補足: デスクトップ版の Cursor には「third-party hooks」という機能があり、有効に
すると `.claude/settings.json` の hooks を Cursor が自動的にマッピングして
使ってくれる（cursor.com のドキュメント検索結果で確認、原文は未読）。ただし
Cloud Agent 側のセットアップドキュメントが挙げているのは `.cursor/hooks.json`
だけで、Cloud Agent が third-party hooks 経由で `.claude/settings.json` も
読むかどうかはどこにも書かれていない。このスキルは確実に動く経路として
`.cursor/hooks.json` 側に寄せる。

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

`assets/` 配下のテンプレートをリポジトリの `.cursor/` にコピーする。パスは
スキルの配置場所に依存しないように書くこと。Claude Code はスキル実行時に
`${CLAUDE_SKILL_DIR}` をこの SKILL.md が置かれているディレクトリに展開する。
展開しないエージェントで実行している場合は、この SKILL.md が実際に置かれている
ディレクトリを自分で組み立てて使う。素の `assets/` だけを指定すると、
エージェントのシェルはスキルのディレクトリではなくプロジェクトのルートで
動いているため、多くの場合そこには `assets/` が存在せず失敗する。

```bash
cp -R "${CLAUDE_SKILL_DIR}/assets/." .cursor/
```

コピー後のレイアウト:

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
   Cloud Agent VM 上で `npm ci && npm test`（速いローカルゲート）を走らせ、
   結果を `{"permission": "allow"|"deny", ...}` という JSON で stdout に返す。
   `git commit` 以外のコマンドはそのまま `allow` で素通しする。
2. **`stop`** — `chunk-validate-stop.sh` が stdin の hook イベント JSON を
   読み切ってから sidecar 上で `chunk validate --remote`（本番 CI に近い検証）を
   実行する。stdin を読み切らずに `chunk validate` へそのまま流すとハングするので、
   このドレインが本体（chunk-cli の `internal/cmd/validate.go` の
   `detectHook` が、stdin が端末でないときに Claude Code の Stop フック用
   ペイロードを探して JSON デコードしようとするため）。

### 検証状況（何をどこまで確認したか）

- **chunk-cli のソースと実 CLI で確認済み**: GitHub リポジトリ名は
  `CircleCI-Public/chunk-cli`（`CircleCI-Public/chunk` は存在しない）。
  リリースアセット名のテンプレートは `.goreleaser.yaml`
  （`{ProjectName}_{Os}_{Arch}.tar.gz`）から来ており、アーカイブ直下に
  `chunk` バイナリと `share/bash-completion/completions/chunk` などが
  同梱される。stdin ブロックの原因は `internal/cmd/validate.go` の
  `detectHook`。`chunk sidecar current --json` / `chunk sidecar create` /
  `chunk sidecar add-ssh-key` / `chunk validate --remote` /
  `chunk config set orgID|validation.sidecarImage` はインストール済みの
  実 CLI（0.7.88）で確認済み。chunk 自身の Claude Code 向け Stop フックの
  リトライ上限（`stopHookMaxAttempts` デフォルト 3）は
  `docs/GETTING_STARTED.md` に明記されている。
- **cursor.com の検索結果で確認（原文は本文取得できず、要約止まり）**:
  `hooks.json` は project 単位では `.cursor/hooks.json`、user 単位では
  `~/.cursor/hooks.json` に置く。`beforeShellExecution` の stdin には
  `command` / `cwd` / `sandbox` が入り、出力は
  `{"permission": "allow"|"deny"|"ask", "user_message", "agent_message"}`。
  何も出力しない・クラッシュする・タイムアウトするとデフォルトでは
  **fail-open**（そのままコマンドが実行される）で、`failClosed: true` を
  hooks.json 側で指定した場合のみブロック側に倒れる。`exit code 2` も
  Claude Code 互換のため deny と同じ扱いになる。`stop` フックの stdin には
  `status` / `loop_count` が入り、出力の `followup_message` を返すと
  Cursor がそれを次のユーザー発言として自動投稿し、エージェントに継続作業
  させる。Cloud Agent のドキュメントは `.cursor/hooks.json` のみを挙げており、
  `.cursor/environment.json` の `install` は Build 作成時にバックグラウンドで
  一度走り、冪等であることが求められる。
- **未確認のまま残っている点**: Cloud Agent が third-party hooks 経由で
  `.claude/settings.json` も読むかどうかは、Cloud Agent 側のドキュメントに
  記述が見当たらない。また forum.cursor.com に「Cloud agent は
  `afterAgentResponse` / `stop` を実行しない」という趣旨のスレッドがあるが、
  未読・未検証（真偽不明の一情報として書いておく）。
  シェルスクリプトは `bash -n` で構文チェック済み、JSON ファイルは
  `python3 -m json.tool` で構文検証済みだが、実際の Cursor Cloud Agent VM 上で
  hooks 経由で動かして確認したものではない。

このスキルを実行する Claude は、hooks が期待通りに動かない場合は
`https://cursor.com/docs/hooks` を取得して突き合わせ、フィールド名や
判定方式が違えば実際の仕様に合わせて直すこと。

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
echo '{"hook_event_name":"stop","status":"completed","loop_count":0}' | .cursor/hooks/chunk-validate-stop.sh
```

成功時の目安:

- active sidecar が無ければ `.chunk/config.json` の `validation.sidecarImage` から作成
- sync → remote `chunk validate` が走る
- exit code は常に `0`（stop フックで exit code `2` がどう扱われるかは未確認のため、exit code には意味を持たせず、継続させるかどうかは `followup_message` の有無だけで制御する）
- stdout には `followup_message` を含む JSON は出ない（または空）

失敗時も exit code は `0` のままで、代わりに stdout に
`{"followup_message": "..."}` を返す。Cursor がこれを次のユーザー発言として
自動投稿し、エージェントに修正とリトライを続けさせる。ただし `loop_count` が
`MAX_ATTEMPTS`（3、chunk 自身の `stopHookMaxAttempts` デフォルトに合わせた値）に
達したら、無限ループを避けるために `followup_message` を返さず黙って
終了する（stderr にだけ状況を残す）。CLI 未インストールや sidecar 未設定など
エージェントがループ内で直せない設定不備は、最初の stop（`loop_count == 0`）で
一度だけ知らせ、以降は黙る。

## Step 4: 仕上げ — sidecar/snapshot の実地確認

ここから先のロジックは `chunk-sidecar` スキルにすべて委譲する。重複実装しない。

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
| `.claude/settings.json` だけに依存 | Cloud Agent のドキュメントは `.cursor/hooks.json` しか挙げておらず、third-party hooks 経由での読み込みは未確認 |

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
| hooks が発火しない / 挙動が説明と違う | `hooks.json` のスキーマが実際の Cursor 仕様とズレている可能性。`cursor.com/docs/hooks` を取得して突き合わせる |
| `git commit` が gate 失敗後も通ってしまう | `hooks.json` の `beforeShellExecution` に `failClosed: true` が付いているか確認（無いと fail-open でスルーされる） |
| stop フックが followup_message を返しても Cloud Agent が反応しない | Cloud Agent が `stop` フックを実行しない可能性の未確認情報あり（forum.cursor.com）。実機で再現するか確認する |

## ファイル対応表（Claude → Cursor）

| Claude Code | Cursor Cloud Agent |
|-------------|-------------------|
| `.claude/settings.json` → `Stop` → `chunk validate` | `.cursor/hooks/chunk-validate-stop.sh` → `chunk validate --remote` |
| `.claude/settings.json` → `PreToolUse` / git commit | `.cursor/hooks.json` → `beforeShellExecution` / `git commit` |
| ローカル Homebrew 等の CLI | `.cursor/setup-chunk.sh`（brew があれば brew、無ければ GitHub Releases から Linux バイナリ） |

## 参考

- [Cursor Hooks](https://cursor.com/docs/hooks)（Cloud agent support）— cursor.com への直接アクセスができない環境で作成したため、検索結果の要約で確認したのみで原文は未読
- [Cursor Cloud Environment Setup](https://cursor.com/docs/cloud-agent/setup) — 同上、検索結果の要約で確認したのみ
- [Cursor third-party hooks](https://cursor.com/docs/reference/third-party-hooks) — 同上、検索結果の要約で確認したのみ
- [chunk-cli (GitHub)](https://github.com/CircleCI-Public/chunk-cli) — リポジトリ名・リリースアセット命名（`.goreleaser.yaml`）・`docs/HOOKS.md`・`internal/cmd/validate.go` を実際にソースで確認
- [Chunk CLI インストールガイド](https://circleci.com/docs/guides/toolkit/install-and-configure-the-chunk-cli/)
- CircleCI: [Wire Chunk sidecars into agent hooks](https://circleci.com/blog/chunk-sidecar-agent-hooks/)
- `chunk-sidecar` スキル（sync → validate のループ、sidecar 作成・スナップショット手順の一次情報源）
