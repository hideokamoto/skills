# skills

AI コーディングエージェント（Claude Code・Cursor・Codex など `SKILL.md` 互換ツール）向けの [Agent Skills](https://agentskills.io) 集です。

本リポジトリが各スキルの正本です。

> 🇬🇧 English: see [README.md](./README.md).

## 含まれるスキル

| スキル | 概要 | ライセンス |
|--------|------|-----------|
| [`wordpress-handbook`](./skills/wordpress-handbook/) | developer.wordpress.org の公式 WordPress 開発者ハンドブック（プラグイン / テーマ / ブロックエディター / REST API / 共通 API / コーディング規約 / 高度な管理）を検索し、必要に応じて記事本文を取得します。 | Apache-2.0 |
| [`circleci-cli`](./skills/circleci-cli/) | CircleCI CLI（CLI v1）を安全に操作します — 認証/トークン確認、org の解決、プロジェクトの作成/取得、config の外部参照可否の判断など、繰り返されがちな CLI ミスを構造で防ぎます。 | Apache-2.0 |
| [`cursor-chunk-sidecar-setup`](./skills/cursor-chunk-sidecar-setup/) | Claude Code で Chunk sidecar 検証済みのリポジトリを、Cursor Cloud Agent でも同じように sidecar 検証できるようにセットアップします。 | MIT |

各スキルディレクトリは `SKILL.md` の frontmatter に個別の `license` を持つ場合があります。このリポジトリ直下の [LICENSE](./LICENSE)（MIT）と異なる場合は、そのスキルディレクトリ自身のライセンスが優先されます。

## インストール

オープンな [`SKILL.md`](https://agentskills.io) 標準に準拠しています。スキルは `skills/*/SKILL.md` という規約で検出されます。

```bash
# GitHub CLI
gh skill install hideokamoto/skills <skill-name>

# Vercel skills CLI
npx skills add hideokamoto/skills --skill <skill-name>

# 本リポジトリの全スキルを一覧表示
npx skills add hideokamoto/skills --list
```

`<skill-name>` には `wordpress-handbook` / `circleci-cli` / `cursor-chunk-sidecar-setup` のいずれかが入ります。

## ライセンス

このリポジトリ自体のファイルは [MIT](./LICENSE)。各スキルの個別ライセンスは、それぞれの `SKILL.md` を参照してください。
