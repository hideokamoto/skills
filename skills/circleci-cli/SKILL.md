---
license: Apache-2.0
name: circleci-cli
description: >-
  Operate the CircleCI CLI (`circleci` command, CLI v1) safely and correctly —
  auth/token checks, org lookup (`org list`), project create/get, and
  config-source questions. Use this skill whenever a task involves the
  `circleci` CLI: checking whether the CLI is authenticated, resolving an org
  slug or org UUID, creating or checking a project, running `circleci auth me`
  / `circleci org list` / `circleci project ...`, or answering whether
  CircleCI can `source` a YAML config from an external repo. Also trigger for
  Japanese phrasings such as 「CircleCI CLI で〜」「circleci の認証を確認」
  「プロジェクトを作成」「org の UUID を取りたい」「config を外部参照したい」.
  This skill exists to prevent specific recurring CLI mistakes; consult it
  before running any `circleci` command, even when the request looks like a
  one-liner.
---

# CircleCI CLI

このスキルは `circleci` CLI（**CLI v1**、legacy CLI v0.1.x とはコマンド体系が異なる）
を操作するときの「再発する失敗」を構造で潰すためにある。過去に下記の3つで実害
（誤報告・無駄な試行・不要なトークン読み出し）が出た。各節は「何をするか」だけでなく
「なぜそれが正しいか／なぜ逆をやると壊れるか」をセットで持つ。モデルが理由を理解して
いれば、本スキルが想定していない場面でも同じ判断軸を適用できる。

legacy CLI（`circleci diagnostic` / `circleci info org` / positional vcs-type
を使う世代）の手順をどこかで見かけても、それはこのスキルが前提にしている CLI v1 とは
別物として扱い、そのまま流用しない。

## 認証・トークンの扱い

- 認証状態は `circleci auth me`（`--json` 可）で確認する。設定ファイル
  `~/.config/circleci/config.yml` を直接読まない。
- なぜ: 「トークンの値をログに出したくない」という理由で
  `cat ~/.config/circleci/config.yml | grep -v token` を使うと、`-v` は**除外**フラグ
  なのでトークン行だけが消えた出力が返る。それを見て「トークンがない」と誤読し、
  「CLI にトークンが設定されていない」と誤って報告する事故が起きた。**存在確認**と
  **値の秘匿**は別の操作であり、片方の道具でもう片方をやろうとすると壊れる。
  `circleci auth me` は値を出さずに「ログイン済みか」を報告するので、両方を同時に満たす。
- 認証方法は `circleci auth login`（ブラウザ経由の OAuth）、`circleci auth logout`、
  または `CIRCLE_TOKEN` 環境変数（設定するとログインをスキップし、保存済み資格情報より
  優先される）。
- トークンの**値は表示・参照しない**。存在だけ確かめたいなら、値を出さない形を使う:
  - 第一選択: `circleci auth me`
  - 設定ファイルでキーの有無だけ見たい場合:
    `grep -q token ~/.config/circleci/config.yml && echo "token configured"`
    （`-q` で出力を抑止し、値を画面に出さない）

## org の lookup（id と slug は別物）

- `circleci org list --json` を実行して org 一覧を得る。結果には UUID の `id` と、
  `gh/myorg` のような形式の `slug` が両方含まれる（フィールド名は変わりうるので
  `--json` の実出力を確認する）。
- **`project create --org` に渡すのは slug（`gh/myorg` 形式）であって UUID ではない。**
  GitHub の org 名（例: `hideokamoto`）は slug の一部（`gh/hideokamoto`）として使うので、
  「GitHub org 名は別物だから使えない」と早合点して UUID を探しにいかない。
- なぜ: legacy CLI では `circleci info org` が UUID を返す運用だったため、「org 指定は
  UUID でなければならない」という思い込みを引きずりやすい。CLI v1 の `project create`
  は slug を受け取る設計なので、まず `circleci org list --json` で自分の org の正しい
  slug を確認してから渡す。

## プロジェクト操作

### 作成前に存在を確認する

- `circleci project create ...` を「無い前提」で先に叩かない。先に
  `circleci project get --project <vcs>/<org>/<repo>` で存在を確認する。
  `project list`（自分がフォロー済みの projects しか返さない）に無いことは
  「存在しない」の根拠にならない。
- なぜ: `project get` が成功する（終了コード 0）ことだけを「既存」の判定に使う。
  `project create` を先に叩いてしまうと、org 指定を間違えたまま実行して
  `Org not found` を踏み、本当は**既存**のプロジェクトなのに「存在しない」と
  誤認しかねない。

### `project create` の構文

- 構文: `circleci project create <project-name> --org <vcs>/<org-slug>`
  （例: `circleci project create my-repo --org gh/hideokamoto`）。
  legacy CLI にあった positional な vcs-type 引数は存在しない。vcs の種別は
  `--org` の prefix（`gh/`, `bb/` など）に埋め込まれている。
- `already exists` は**エラーではない**が、**無条件に「作成済みで安全」と断定もしない**。
  `already exists` を見たら `circleci project get` で実体を確認し、想定した project と
  一致するかを見てから「既存」として扱う。
- GitHub/Bitbucket の OAuth 連携で追加した project は、Web UI 側でインポートされている
  ことが多く、`project create` を CLI から叩く場面自体が少ない。`project create` は
  主に `circleci` 系（GitHub App/Bitbucket Data Center）の org で使う。

### 失敗時は原因を読んでから動く

- create / get が失敗したら、org slug を**闇雲に変えて再試行する前に**、エラー文言を
  読んで原因を確定する。`Org not found`（org slug の指定ミス）と `already exists`
  （既存）は意味が真逆。
- なぜ: 原因を読まずに org slug の候補を総当たりすると、たまたま通った結果から誤った
  因果（「この org はこの slug 形式だった」等）を後付けしてしまう。先にエラーを読めば
  一発で分かる。

## API を直接叩かない（CLI で完結させる）

- CircleCI CLI が設定済みである以上、REST API を直接叩く必要はない。CLI 経由で操作する。
- なぜ: API を直接使おうとすると、認証ヘッダのためにトークンを読み出す動機が生まれる。CLI を
  通せばトークンの値に一切触れずに同じ操作ができる。CLI の存在を確認せずに API へ行くこと自体が
  設計上の誤り。まず CLI でできないかを確認する。

## Config Source と `source` 構文は別物

- **Config Source**（config を置くリポジトリ）と **Checkout Source**（コードを
  checkout するリポジトリ）を別々に指定できるのは、GitHub App 連携・Bitbucket Data
  Center の project setup 画面（Web UI）での話。この場合、config は checkout 対象とは
  別の任意のリポジトリ・任意のパスの `.yml` を指定できる。外部リポジトリを config の
  置き場所にすること自体は**できる**。
- 一方で、YAML の config ファイル内に「別リポジトリの config を `source:` のような構文で
  直接 import する」機能は**ない**。「外部 config を参照したい」という要件を、この YAML
  レベルの import 構文で実現しようとしない。
- 動的に config を生成・継続したい（パラメータやトリガー元に応じて config を切り替えたい）
  場合の代替は dynamic config（setup workflow + continuation orb）。

## 禁止事項（クイックリファレンス）

本文の理由を踏まえた要約。迷ったら本文の「なぜ」に戻る。

- legacy CLI のコマンド（`circleci diagnostic` / `circleci info org` / positional
  vcs-type）をそのまま使わない（CLI v1 では削除・変更済み）
- `grep -v token` で存在確認をしない（除外フラグなので値が消えるだけで存在判定にならない）
- トークンの**値**を表示・参照しない（存在確認は `circleci auth me`）
- org slug（`gh/myorg` 形式）が要求される箇所に、素の GitHub org 名や UUID を渡さない
  （`circleci org list --json` で正しい slug を確認する）
- 「無い前提」で `project create` を先に叩かない（先に `project get` で存在確認）
- `already exists` を無条件に「既存で問題なし」と断定しない（`project get` で実体確認）
- コマンド失敗時、エラー文言を読まずに org slug を総当たりで変えて再試行しない
- REST API を直接叩かない（CLI で完結させる）
- 「外部リポジトリの config を YAML の `source` 構文で直接参照できない」ことと、
  「GitHub App/Bitbucket Data Center で Config Source を別リポジトリにできる」ことを
  混同しない
