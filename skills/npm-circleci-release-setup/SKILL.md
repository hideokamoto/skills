---
name: npm-circleci-release-setup
description: >-
  npm 公開ライブラリに、hideokamoto/circleci-configurations の config source
  方式で CircleCI の validate / npm publish パイプラインを構築し、
  semantic-release による自動リリース、npm Trusted Publisher（trustci）登録、
  commitlint + husky まで整備する。パッケージマネージャ変更やリリース運用変更を
  伴うためユーザー確認が前提。npm ライブラリの CD・リリース自動化、CircleCI での
  npm publish、semantic-release 導入、Trusted Publisher 設定の依頼では、
  明示指定がなくても使う。
license: MIT
compatibility: gh、circleci CLI（CLI v1）、pnpm、npx（trustci）が必要。完了確認には CircleCI MCP の list_runs などを使う。
---

# npm-circleci-release-setup

任意の GitHub リポジトリに対し、`hideokamoto/circleci-configurations` の「config source」方式で CI/リリースを CircleCI に統合し、Conventional Commits + semantic-release による自動リリースを整備する。

**対象リポジトリ自体には `.circleci/config.yml` を直接配置しない**（config source で完結させる）。

## 実行規律（最初に読む）

この作業は、GitHub・CircleCI・npm の実環境に副作用を起こす。しかも一部は取り消しにくい（Pipeline Definition や Trigger の作成、Trusted Publisher の登録、リリース運用の変更）。そのため、手順 0〜6 を**書かれた順序と内容のとおりに**実行する。手順の省略・並べ替え・代替コマンドへの置き換えは、ユーザーの承認なしにはしない。

逸脱が必要になったとき（コマンドが失敗する、テンプレが合わない、前提が違う、など）は、自分で別案を選ばずに次の形で扱う。

1. その場で止まる。
2. 「どの手順の何が、なぜ実行できないか」を、実際のエラー出力とともにユーザーへ報告する。
3. 本書に「フォールバック」として明記されているもの（手順4の trustci 失敗時のみ）を除き、ユーザーの指示を待つ。

こう決めている理由は、逸脱が「うまく回避できた」ように見えても、後から原因を追えない状態で実環境を変えてしまうからである。止まって報告すれば、失敗は 1 箇所で済む。

また、各手順の終わりに「完了条件」を置いてある。完了条件を満たしたことを、コマンド出力などの実物で確認してから次へ進む。「たぶん通った」で進まない。

**ユーザー確認が必須の停止点**（ここでは必ず止まる）:

| 停止点 | 場面 |
|---|---|
| 停止点A | 手順1: パッケージマネージャ変更・リリース運用変更の方針 |
| 停止点B | 手順2: PR のマージ（マージ自体はユーザーが判断する） |
| 停止点C | 手順4: `npx trustci` 本実行（ユーザー自身が実行する） |

## 手順 0: 前提値の解決

次の値は**ハードコードしない**。対象 org ごとに都度取得する。

| 値 | 取得方法 |
|---|---|
| 対象 `<OWNER>/<REPO>` | 対象リポジトリの GitHub owner/repo 名 |
| CircleCI org slug | `gh/<OWNER>`（個人 org の場合は `gh/<OWNER>` がそのまま使える） |
| circleci-configurations の config-repo-id（GitHub 数値 ID） | `gh api repos/hideokamoto/circleci-configurations --jq '.id'` |
| 対象リポジトリの GitHub 数値 ID（checkout-repo-id） | `gh api repos/<OWNER>/<REPO> --jq '.id'` |
| circleci-configurations の config ref（`--config-ref` に渡す、config repo 側のブランチ名） | `gh api repos/hideokamoto/circleci-configurations --jq '.default_branch'` |
| 利用する context の UUID（名前からの解決が必要な場合のみ） | `circleci context list --org gh/<OWNER> --json` |

- trustci は `--context-id` を UUID でしか受け付けない。使う context があれば、名前→UUID をここで解決する。context を使わない場合は、この解決手順自体をスキップしてよい。
- CircleCI org UUID は明示指定不要。trustci がトークンから自動解決するため、原則取得しない。context 解決以外の用途がなければ省略する。
- `circleci` CLI の操作では、`circleci-cli` スキルが利用できればそれに従う（CLI v1 と legacy CLI でコマンド体系が違うため）。

**完了条件**: config-repo-id と checkout-repo-id が数値で、config ref がブランチ名で得られている。

## 手順 1: 現状把握

対象リポジトリで次を確認する。

- `package.json` の scripts
- lockfile の種別
- 現在のリリース方法
- `.github/workflows` の有無
- GitHub 上の default branch。`circleci project get` の `vcs_default_branch` は古いキャッシュの場合があるので**信用しない**。次を使う。

  ```bash
  gh repo view <OWNER>/<REPO> --json defaultBranchRef
  ```

次に、`hideokamoto/circleci-configurations` の `workflows/validation/README.md` と `workflows/publish/README.md` を読み、対象リポジトリの構成（パッケージマネージャ・ランタイム）に合うテンプレを探す。

- **合うテンプレが既にあるなら、それに合わせてリポジトリ側を変更する方を優先する。** 新規テンプレを対象リポジトリ専用に作らない。
- `npm-polyrepo-*` 系は pnpm 前提。`npm-polyrepo-bun.yaml` のみ bun 前提。手動タグ運用のプレーン npm は、テンプレ無しの場合がある。

### 停止点A（必須）

パッケージマネージャ変更や、リリース運用（手動タグ → main merge 自動、など）の変更は**破壊的な意思決定**である。どちらの方針にするかを**必ずユーザーに確認してから**進める。確認前に、手順 2 以降の変更に着手しない。

**完了条件**: 選んだテンプレのファイル名、default branch、方針についてのユーザーの回答が揃っている。

## 手順 2: リポジトリ移行（pnpm + semantic-release 化する場合）

停止点Aで、pnpm + semantic-release 化が承認された場合のみ実施する。

1. `package-lock.json` / `yarn.lock` 等を削除 → `pnpm install` → `pnpm-lock.yaml` を生成。
2. `package.json` に `"packageManager": "pnpm@<version>"` を追加。
3. 不足している scripts を追加（lint / typecheck / build / test）。typecheck が無く、かつ TypeScript を使うリポジトリ（`tsconfig.json` がある）の場合は `"typecheck": "tsc --noEmit"` を追加。TypeScript を使わないリポジトリには追加しない（`tsc` が無く検証が失敗するため）。
4. `.releaserc.json` を、`circleci-configurations` の `workflows/publish/templates/semantic-release/.releaserc.json` からコピーする。
   - branches / tagFormat / plugins はそのまま。
   - 既存リリースのタグが対象ブランチの履歴上にあることを確認する。
5. 旧リリース手段（np 等）の script / 依存を削除。
6. 既存の `.github/workflows` が重複・競合するなら、次のどちらかを判断する。**無言で両方残して壊れたままにしない。**
   - CircleCI の validate パイプラインに一本化して削除する。
   - pnpm 対応だけして残す。
7. ローカルで `lint` / `typecheck` / `format:check` / `build` / `test` のうち、`package.json` に定義されているものを**全部**実行して確認する。定義が無いために実行しなかった項目（TypeScript を使わない場合の `typecheck`、未定義の `format:check` など）は、その旨を報告する。
8. 新しいブランチで commit・push・PR 作成。**default branch への直接 push はしない。**

### 停止点B（必須）

PR のマージはユーザー判断。マージしない。

**完了条件**: 実行した各コマンドの結果（成功/失敗）と、実行しなかった項目とその理由を示せる。PR の URL を示せる。

## 手順 3: CircleCI Pipeline Definition / Trigger 作成

1. 既存状態を確認する。`pipeline list` は Pipeline Definition の一覧であり、Trigger は含まれない。既存の Definition ごとに Trigger も確認する（残っている Trigger が同じ push で起動すると、新旧のパイプラインが重複して走るため）。

   ```bash
   circleci pipeline list --project gh/<OWNER>/<REPO> --json
   circleci project trigger list --project gh/<OWNER>/<REPO> --pipeline-definition-id <既存DefinitionのID> --json
   ```

2. **2 つの Pipeline Definition** を作成する。checkout / config ともに `--checkout-provider` / `--config-provider` は `github_app`。`github_oauth` は使えない。

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

3. **Trigger** を作成する。config repo と checkout repo が別なので `--config-ref <config repoのブランチ>` が**必須**。無いと `400: a config ref must be provided...` で失敗する。

   ```bash
   circleci project trigger create --project gh/<OWNER>/<REPO> \
     --pipeline-definition-id <validateのid> --repo-id <対象repoの数値ID> \
     --event-preset all-pushes --config-ref <config repoのブランチ> --json

   circleci project trigger create --project gh/<OWNER>/<REPO> \
     --pipeline-definition-id <publishのid> --repo-id <対象repoの数値ID> \
     --event-preset default-branch-pushes --config-ref <config repoのブランチ> --json
   ```

   タグ手動運用のテンプレを使う場合は、publish の `--event-preset` を `only-tags` にする。

`<config repoのブランチ>` は、手順0で得た circleci-configurations 側のブランチ名を使う。`--config-ref` は config を取得する Git ref（CircleCI CLI リファレンス: 「config repo が event source repo と異なる場合のみ必要」）であり、対象リポジトリの default branch（手順1）ではない。両者を混同しない。

**完了条件**: 2 つの Pipeline Definition の id と、2 つの Trigger の作成結果（JSON）が得られている。

## 手順 4: npm Trusted Publisher 登録（trustci 使用）

`npm trust circleci` を直接組み立てず、`npx trustci@<trustciのバージョン>` に任せる。既存の CircleCI CLI 認証（`CIRCLE_TOKEN` 環境変数、または `~/.circleci/cli.yml`）があれば、org-id / project-id / pipeline-definition-id / vcs-origin は API から自動解決される。

`npx trustci` は CircleCI の認証情報を使って、registry から取得したパッケージを実行する。未確認の更新版が実行されないよう、バージョンを固定する。最初に版を 1 つ決め、dry-run と本実行の**両方で同じ版**を使う。

```bash
npm view trustci version
```

出力された版を `<trustciのバージョン>` として、ユーザーに提示する。

次に **dry-run** で解決結果を確認する（推奨）。dry-run は実行しない確認である。

```bash
npx trustci@<trustciのバージョン> --provider circleci --allow-publish --dry-run \
  --file workflows/publish/<選んだファイル>.yaml \
  [--context-id <contextのUUID> ...]   # contextを使う場合のみ、複数指定可
```

dry-run の出力を確認してから、本実行のコマンドを組み立てる。

```bash
npx trustci@<trustciのバージョン> --provider circleci --allow-publish \
  --file workflows/publish/<選んだファイル>.yaml \
  [--context-id <contextのUUID> ...]
```

- `--file` は publish 用の pipeline 定義を一意に選ぶためだけに使われる。プロジェクトに pipeline 定義が 1 つしかない場合は省略可。
- `--vcs-origin` を自動推定に任せられない場合（`package.json` の repository と git remote が一致しない等）のみ明示指定する。
- dry-run で vcs-origin 解決や UUID 解決が失敗する場合は、trustci のバージョンを確認する（既知の問題が修正されている可能性があるため）。版を変える場合は、dry-run と本実行の両方を同じ新しい版にそろえ、ユーザーに伝える。解決しなければ、`npm trust circleci` を**手動の完全形式**（org-id / project-id / pipeline-definition-id / vcs-origin / context-id を個別指定）にフォールバックする。**これが、本書で唯一認められているフォールバックである。**

### 停止点C（必須）

ブラウザでの 2FA/OTP 承認が必須なので、**本実行のコマンドはユーザー自身が実行する**。エージェントはコマンドを提示して止まる。本実行をエージェントが実行しない。

**完了条件**: 固定した trustci のバージョン、dry-run の出力をユーザーに示し、同じバージョンを指定した本実行コマンドを提示した。

## 手順 5: Conventional Commits 強制（commitlint + husky）

このスキルのコマンドは pnpm を例に書いている。**停止点Aで決めた package manager を使う。** pnpm への移行を承認していない場合は pnpm コマンドを実行せず、同等のコマンド（npm なら `npm install -D` / `npx` / `npm install`）に置き換える。lockfile を別の package manager 用に作り替えない。

1. 依存を追加する。

   ```bash
   pnpm add -D husky @commitlint/cli @commitlint/config-conventional
   ```

2. commitlint の設定ファイル（`commitlint.config.js` 等）が無ければ `@commitlint/config-conventional` を extends して作成する（原文の手順はこのファイルの存在を前提にしているため、補った手順）。そのうえで、設定ファイルが `.gitignore` の `*.js` 除外ルールに引っかかって追跡されないことが多いので確認する。既存の `!jest.config.js` のような例外パターンがあれば、`!commitlint.config.js` を追加する。
3. `pnpm exec husky init` を実行する。
   - 生成される `.husky/pre-commit`（デフォルトで `pnpm test`）は、**依頼されていなければ削除する**。
   - `.husky/commit-msg` には `pnpm exec commitlint --edit "$1"` **だけ**を置く（スコープを広げない）。
4. `package.json` の `prepare` スクリプトが元々あれば（例: build 実行用）、husky 呼び出しを上書きせず両立させる。例: `"prepare": "husky && npm run build"`。
5. `pnpm install` で再セットアップする。
6. 次の 2 点を確認してから commit・PR にする。
   - bad message が弾かれること: `echo "x" | pnpm exec commitlint`
   - 実際に `git commit -m "bad"` が拒否されること

**完了条件**: 上記 2 つの拒否の出力を示せる。

## 手順 6: 完了後の確認

PR マージ後（マージはユーザー）、validate / npm publish パイプラインが実際に走ったことを確認する。CircleCI MCP の次のツールを順にたどる。

`list_runs` → `list_run_workflows` → `list_workflow_jobs` / `get_job`

- release 対象の無い commit（例: `ci:` / `chore:` のみ）では、semantic-release が正常に「リリース対象なし」で終わることを確認する。これは異常ではなく期待どおりの結果である。
- `feat:` / `fix:` を含む次のマージで実際に publish されるかは、そのタイミングで見る。まだ起きていないことを「確認済み」と報告しない。

**完了条件**: 実際に走った run / workflow / job の結果を、実物の出力で示せる。
