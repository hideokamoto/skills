---
license: Apache-2.0
name: circleci-cli
description: >-
  Operate the CircleCI CLI (`circleci` command) safely and correctly — auth/token
  checks, org slug (UUID) lookup, project create/list, and config-source questions.
  Use this skill whenever a task involves the `circleci` CLI: checking whether the
  CLI is authenticated, resolving an org slug or org UUID, creating or listing a
  project, running `circleci diagnostic` / `circleci info org` / `circleci project
  ...`, or answering whether CircleCI can `source` a YAML config from an external
  repo. Also trigger for Japanese phrasings such as 「CircleCI CLI で〜」「circleci の
  認証を確認」「プロジェクトを作成」「org の UUID を取りたい」「config を外部参照したい」.
  This skill exists to prevent specific recurring CLI mistakes; consult it before
  running any `circleci` command, even when the request looks like a one-liner.
---

# CircleCI CLI

このスキルは `circleci` CLI を操作するときの「再発する失敗」を構造で潰すためにある。
過去に下記の3つで実害（誤報告・無駄な試行・不要なトークン読み出し）が出た。各節は
「何をするか」だけでなく「なぜそれが正しいか／なぜ逆をやると壊れるか」をセットで持つ。
モデルが理由を理解していれば、本スキルが想定していない場面でも同じ判断軸を適用できる。

## 認証・トークンの扱い

- 認証状態は `circleci diagnostic` で確認する。設定ファイル `~/.circleci/cli.yml` を直接読まない。
- なぜ: 「トークンの値をログに出したくない」という理由で `cat ~/.circleci/cli.yml | grep -v token`
  を使うと、`-v` は**除外**フラグなのでトークン行だけが消えた出力が返る。それを見て「トークンが
  ない」と誤読し、「CLI にトークンが設定されていない」と誤って報告する事故が起きた。
  **存在確認**と**値の秘匿**は別の操作であり、片方の道具でもう片方をやろうとすると壊れる。
  `circleci diagnostic` は値を出さずに「設定済みか」を報告するので、両方を同時に満たす。
- トークンの**値は表示・参照しない**。存在だけ確かめたいなら、値を出さない形を使う:
  - 第一選択: `circleci diagnostic`
  - 設定ファイルでキーの有無だけ見たい場合: `grep -q token ~/.circleci/cli.yml && echo "token configured"`
    （`-q` で出力を抑止し、値を画面に出さない）

## org slug (UUID) の取得

- `circleci info org` を実行して org の UUID を得る。
- GitHub の org 名（例: `hideokamoto`）と CircleCI の org UUID は**別物**。
  コマンドが org slug / org-id を要求する箇所に GitHub org 名をそのまま渡さない。
- なぜ: org slug が UUID 形式だと知らないと、GitHub org 名で叩いて `Org not found` を踏み、
  原因を取り違える。要求されているのが UUID なら、まず `circleci info org` を経由する。

## プロジェクト操作

### 作成前に存在を確認する

- `circleci project create ...` を「無い前提」で先に叩かない。先に存在を確認する。
- なぜ: vcs-type を間違えたまま create を先に叩くと `Org not found` が返り、本当は**既存**の
  プロジェクトなのに「存在しない」と誤認した。正しい vcs-type で確認していれば、`already exists`
  が即座に返って「既存」と分かったはずだった。

### vcs-type の選択

| 連携方式 | 渡す vcs-type |
|---|---|
| GitHub App 連携（新方式） | `circleci` |
| 旧来の OAuth 連携 | `github` |

- 例: `circleci project create circleci <org-uuid> --name <project-name>`
- `already exists` は**エラーではない**。「作成済み」を表す成功状態として扱う。

### 失敗時は原因を読んでから動く

- create / list が失敗したら、別の vcs-type で**闇雲に再試行する前に**、エラー文言を読んで原因を
  確定する。`Org not found`（org/vcs-type の指定ミス）と `already exists`（既存）は意味が真逆。
- なぜ: 原因を読まずに `github` → `circleci` と総当たりすると、たまたま通った結果から誤った
  因果（「このプロジェクトは新方式だった」等）を後付けしてしまう。先にエラーを読めば一発で分かる。

## API を直接叩かない（CLI で完結させる）

- CircleCI CLI が設定済みである以上、REST API を直接叩く必要はない。CLI 経由で操作する。
- なぜ: API を直接使おうとすると、認証ヘッダのためにトークンを読み出す動機が生まれる。CLI を
  通せばトークンの値に一切触れずに同じ操作ができる。CLI の存在を確認せずに API へ行くこと自体が
  設計上の誤り。まず CLI でできないかを確認する。

## config source / 動的 config

- CircleCI に「外部リポジトリの YAML を直接 `source` 参照する」機能は**ない**。
  そういう前提で設計・回答しない。
- 代替は dynamic config（setup workflow + continuation orb）。外部やパラメータに応じて config を
  生成・継続したい要件は、この経路で実現する。

## 禁止事項（クイックリファレンス）

本文の理由を踏まえた要約。迷ったら本文の「なぜ」に戻る。

- `grep -v token` で存在確認をしない（除外フラグなので値が消えるだけで存在判定にならない）
- トークンの**値**を表示・参照しない（存在確認は `circleci diagnostic`）
- org slug が要求される箇所に GitHub org 名を渡さない（UUID は `circleci info org`）
- 「無い前提」で `project create` を先に叩かない（先に存在確認）
- コマンド失敗時、エラー文言を読まずに別 vcs-type で再試行しない
- REST API を直接叩かない（CLI で完結させる）
