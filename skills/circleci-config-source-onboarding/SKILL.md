---
name: circleci-config-source-onboarding
description: >-
  任意のGitHubリポジトリを、hideokamoto/circleci-configurations の「config source」方式でCircleCIに統合し、Conventional Commits + semantic-release による自動リリース（npm Trusted Publisher 含む）を整備する手順。対象リポジトリ側に .circleci/config.yml を置かず、Pipeline Definition / Trigger を作成して外部configを参照させる。「このリポジトリをCircleCIに載せたい」「config sourceでCI/リリースを設定して」「semantic-release + commitlint を導入して」「npm trust circleci / trustci を設定して」「circleci-configurations のテンプレを適用して」といった依頼で使う。circleci CLI の個別操作（認証確認・org解決など）は circleci-cli スキルも併せて参照する。
license: MIT
---

# CircleCI config source 方式オンボーディング

対象リポジトリに `.circleci/config.yml` を置かず、`hideokamoto/circleci-configurations` のテンプレを外部configとして参照させ、CI（validate）とリリース（publish）を CircleCI で動かす。あわせて Conventional Commits を強制し、semantic-release で自動リリースする。

## 守ること

- 値はハードコードしない。org・リポジトリごとに都度取得する（下記「解決すべき値」）。
- パッケージマネージャ変更やリリース運用変更（手動タグ → main merge 自動など）は破壊的な意思決定。**実行前に必ずユーザーに方針を確認する。**
- デフォルトブランチへ直接 push しない。ブランチを切って PR にする。マージはユーザー判断。
- npm Trusted Publisher の登録コマンドはブラウザで 2FA/OTP 承認が必要。**エージェントは実行せず、コマンドを提示して止まる。**
- `circleci` CLI は CLI v1 前提。コマンド操作の前に `circleci-cli` スキルがあれば参照する。

## 解決すべき値

| 値 | 取得方法 |
|---|---|
| 対象 | `<OWNER>/<REPO>` |
| CircleCI org slug | `gh/<OWNER>`（個人orgならそのまま使える） |
| config-repo-id | `gh api repos/hideokamoto/circleci-configurations --jq '.id'` |
| checkout-repo-id | `gh api repos/<OWNER>/<REPO> --jq '.id'` |
| context の UUID | `circleci context list --org gh/<OWNER> --json`（contextを使う場合のみ。trustci は `--context-id` を UUID でしか受け付けないため名前→UUIDを解決する。使わないなら省略） |

CircleCI org UUID は明示指定不要（trustci がトークンから自動解決する）。context 解決以外に使い道がなければ取得しない。

## 手順

### 1. 現状把握

- `package.json` の scripts、lockfile 種別、現在のリリース方法、`.github/workflows` の有無を確認する。
- default branch は `gh repo view <OWNER>/<REPO> --json defaultBranchRef` で確認する。CircleCI `project get` の `vcs_default_branch` は古いキャッシュのことがあるので信用しない。
- `hideokamoto/circleci-configurations` の `workflows/validation/README.md` と `workflows/publish/README.md` を読み、対象の構成（パッケージマネージャ・ランタイム）に合うテンプレを探す。ファイル名は変わりうるので、下表は目安として扱い、必ず最新の README と突き合わせる。
- **合うテンプレが既にあるなら、リポジトリ側をそれに合わせる方を優先する。** 対象専用の新規テンプレは作らない。手動タグ運用のプレーン npm の publish テンプレは無い。

  | 用途 | ファイル（`workflows/` 配下） | 前提 |
  |---|---|---|
  | validate（publish なし） | `validation/npm.yaml` | lockfile から pnpm / npm を自動判定（両方あると失敗）。scripts: `lint` / `typecheck` / `build` / `test` |
  | publish: 単一パッケージ + pnpm + semantic-release | `publish/npm-polyrepo-semantic-release.yaml` | scripts: `lint` / `typecheck` / `build` / `test` |
  | publish: 単一パッケージ + bun + semantic-release | `publish/npm-polyrepo-bun-semantic-release.yaml` | `bun.lock`（テキスト形式）必須。scripts: `typecheck` / `build` / `test`（lint は実行しない） |
  | publish: 単一パッケージ + release-please | `publish/npm-polyrepo-release-please.yaml` | **現状リリースを作成しない**（README 記載）。Release PR 無しで main マージ即リリースにしたいなら semantic-release 版を使う |
  | publish: Changesets モノレポ | `publish/npm-monorepo.yaml` | main に版上げコミットを直接 push する |

  publish 系は全て main への push 起点で、Node 24 系（`cimg/node:24.21`、npm 11.19.0 同梱）で動く。
- 方針（パッケージマネージャ変更・リリース運用変更をするか）をユーザーに確認してから進む。

### 2. リポジトリ移行（pnpm + semantic-release 化する場合）

- `package-lock.json` / `yarn.lock` 等を削除 → `pnpm install` → `pnpm-lock.yaml` を生成。
- `package.json` に `"packageManager": "pnpm@<version>"` を追加。
- 不足している scripts を追加（lint / typecheck / build / test。typecheck が無ければ `"typecheck": "tsc --noEmit"`）。
- `package.json` の `publishConfig.access` を `"public"` にする（テンプレの公開範囲はこれで決まる）。
- `.releaserc.json` を `circleci-configurations` の `workflows/publish/templates/semantic-release/.releaserc.json` からコピー。branches / tagFormat / plugins はそのまま。既存リリースのタグが対象ブランチの履歴上にあることを確認する。
- 旧リリース手段（np 等）の script / 依存を削除。`package.json` の `version` は手で上げない（公開される版はタグから決まる。CI は main に push しない）。
- `.npmrc` に `//registry.npmjs.org/:_authToken=...` があれば削除する。CircleCI の Project / Context に `NPM_TOKEN` / `NODE_AUTH_TOKEN` の長期トークンを置く運用へ戻さない。
- publish の release ジョブは `--ignore-scripts` で依存を入れるため、`postinstall` / `prepare` に依存したビルドは動かない。ビルドは `build` script が明示的に担う前提にする。
- 既存の `.github/workflows` が重複・競合するなら、CircleCI の validate に一本化して削除するか、pnpm 対応だけして残すかを判断する。**無言で両方残して壊れたままにしない。**
- ローカルで lint / typecheck / format:check / build / test を全部実行して確認。
- 新しいブランチで commit・push・PR 作成。

### 3. CircleCI Context の用意と Pipeline Definition / Trigger 作成

publish テンプレの release ジョブは次の2つの Context を参照する。**先に存在を確認する**（`circleci context list --org gh/<OWNER> --json`）。`github` が無い/`GITHUB_TOKEN` が未設定だと release ジョブは最初の事前確認で失敗する。

| Context | 中身 |
|---|---|
| `github` | `GITHUB_TOKEN`（対象リポジトリへの `contents:write`。タグ push と GitHub Release 作成に使う） |
| `npm-publish-guard` | シークレットは不要（OIDC のため）。誰が・どのブランチから公開できるかを絞る restricted context として使う |

Context が無い場合の作成と権限設定はユーザーに確認してから行う。

`circleci pipeline list --project gh/<OWNER>/<REPO> --json` で既存状態を確認してから作る。

Pipeline Definition を2つ作成する（`--checkout-provider` / `--config-provider` は `github_app`。`github_oauth` は使えない）:

```bash
circleci pipeline create --project gh/<OWNER>/<REPO> --name "validate" \
  --config-provider github_app --config-repo-id <circleci-configurationsの数値ID> \
  --config-file workflows/validation/<選んだファイル>.yaml \
  --checkout-provider github_app --checkout-repo-id <対象repoの数値ID> --json

circleci pipeline create --project gh/<OWNER>/<REPO> --name "npm publish" \
  --config-provider github_app --config-repo-id <circleci-configurationsの数値ID> \
  --config-file workflows/publish/<選んだファイル>.yaml \
  --checkout-provider github_app --checkout-repo-id <対象repoの数値ID> --json
```

Trigger を作成する。**config repo と checkout repo が別なので `--config-ref <デフォルトブランチ>` が必須**（無いと `400: a config ref must be provided...` で失敗する）:

```bash
circleci project trigger create --project gh/<OWNER>/<REPO> \
  --pipeline-definition-id <validateのid> --repo-id <対象repoの数値ID> \
  --event-preset all-pushes --config-ref <デフォルトブランチ> --json

circleci project trigger create --project gh/<OWNER>/<REPO> \
  --pipeline-definition-id <publishのid> --repo-id <対象repoの数値ID> \
  --event-preset default-branch-pushes --config-ref <デフォルトブランチ> --json
```

publish の event-preset は、テンプレのトリガー（main への push 起点）に合わせる。bun 版で main 以外のブランチの `test` ジョブも走らせたい場合は `default-branch-pushes` ではなく `all-pushes` にする。タグ手動運用のテンプレを使う場合は `only-tags`。

> 注意: 上の `circleci pipeline create` / `project trigger create` のフラグと `--event-preset` の値は、元のプロンプトに記載されていたもので、このスキル作成時に CLI の `--help` では検証できていない。実行前に `circleci pipeline create --help` / `circleci project trigger create --help` で確認する。

### 4. npm Trusted Publisher 登録（trustci）

`npm trust circleci` を直接組み立てず `npx trustci` に任せる。trustci 0.3.0 は **npm >=11.5.1 / node >=22.14** を要求する（満たさないと `EBADENGINE` 警告が出る。実行前に `npm --version` / `node --version` を確認し、足りなければユーザーに更新を促す）。private パッケージ（`"private": true`）は対象から除外され、workspace 設定が無ければルートの `package.json` を単一パッケージとして扱う。既存の CircleCI CLI 認証（`CIRCLE_TOKEN` 環境変数 or `~/.circleci/cli.yml`）があれば、org-id / project-id / pipeline-definition-id / vcs-origin は API から自動解決される。

```bash
# まず dry-run で解決結果を確認（推奨。実行はしない）
npx trustci --provider circleci --allow-publish --dry-run \
  --file workflows/publish/<選んだファイル>.yaml \
  [--context-id <contextのUUID> ...]   # contextを使う場合のみ、複数指定可

# dry-run の出力を確認してから実行（ユーザー自身が実行する）
npx trustci --provider circleci --allow-publish \
  --file workflows/publish/<選んだファイル>.yaml \
  [--context-id <contextのUUID> ...]
```

- `--file` は publish 用の pipeline 定義を一意に選ぶためだけに使われる。プロジェクトに pipeline 定義が1つしかなければ省略可。
- `--vcs-origin` は、自動推定に任せられない場合（`package.json` の repository と git remote が一致しない等）のみ明示指定する。
- dry-run で vcs-origin 解決や UUID 解決が失敗する場合は、まず trustci のバージョンを確認する（既知の問題が修正されている可能性がある）。それでも解決しなければ `npm trust circleci` を完全形式（org-id / project-id / pipeline-definition-id / vcs-origin / context-id を個別指定）で手動実行する方にフォールバックする。
- `npm-publish-guard` の Context UUID を `--context-id` に渡すと、その Context が付与された実行の `npm publish` だけが許可される（任意。厳密にしたい場合）。
- ブラウザでの 2FA/OTP 承認が必須。実行コマンドはユーザー自身が実行する。**エージェントはコマンドを提示して止まる。**

### 5. Conventional Commits 強制（commitlint + husky）

- `pnpm add -D husky @commitlint/cli @commitlint/config-conventional`
- `commitlint.config.js` は `.gitignore` の `*.js` 除外ルールに引っかかって追跡されないことが多い。既存の `!jest.config.js` 的な例外があれば `!commitlint.config.js` を追加する。
- `pnpm exec husky init` を実行。生成される `.husky/pre-commit`（デフォルトで `pnpm test`）は依頼されていなければ削除し、`.husky/commit-msg` に `pnpm exec commitlint --edit "$1"` だけを置く（スコープを広げない）。
- `package.json` の `prepare` が元からあれば（例: build 実行用）、husky 呼び出しを上書きせず両立させる（例: `"prepare": "husky && npm run build"`）。
- bun 構成では `bunx commitlint --edit "$1"`、`prepare` に `husky`、root に `commitlint.config.*` と `.husky/commit-msg`。publish テンプレは CI でコミットメッセージを検証しないため、この husky フックがローカルでの唯一の強制になる。Web 上のマージやフック未導入環境のコミットは検証されない点をユーザーに伝える。
- `pnpm install` で再セットアップ。次を確認してから commit・PR:
  - `echo "x" | pnpm exec commitlint` が弾かれる
  - 実際に `git commit -m "bad"` が拒否される

### 6. 完了後の確認

- PR マージ後、validate / npm publish パイプラインが実際に走ったことを確認する（CircleCI MCP: `list_runs` → `list_run_workflows` → `list_workflow_jobs` / `get_job`）。
- publish が失敗したときの注意: semantic-release は**タグを push してから** npm 公開 → GitHub Release の順に実行する。公開だけ失敗するとタグが残り、同じコミットの再実行は「リリース済み」と判定されて公開されない。`npm view <パッケージ名>@<版>` で npm に版があるか確認し、無ければ `git push origin :refs/tags/v<版>` でタグを消してから release ジョブを再実行する（有るなら GitHub Release だけ手動で作る）。タグ削除は破壊的操作なのでユーザーの確認を取る。
- `--provenance` は付けない（CircleCI からの Trusted Publishing は provenance 非対応。npm の provenance バッジは付かない）。
- release 対象の無い commit（`ci:` / `chore:` のみ）では semantic-release が正常に「リリース対象なし」で終わることを確認する。`feat:` / `fix:` を含む次のマージで実際に publish されるかは、そのタイミングで確認する。
