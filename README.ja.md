# skills

AI コーディングエージェント（Claude Code・Cursor・Codex など `SKILL.md` 互換ツール）向けの [Agent Skills](https://agentskills.io) 集です。

> 🇬🇧 English: see [README.md](./README.md).

## 含まれるスキル

| スキル | 概要 | ライセンス |
|--------|------|-----------|
| [`wordpress-handbook`](./skills/wordpress-handbook/) | developer.wordpress.org の公式 WordPress 開発者ハンドブック（プラグイン / テーマ / ブロックエディター / REST API / 共通 API / コーディング規約 / 高度な管理）を検索し、必要に応じて記事本文を取得します。 | Apache-2.0 |

各スキルディレクトリは `SKILL.md` の frontmatter に個別の `license` を持つ場合があります。このリポジトリ直下の [LICENSE](./LICENSE)（MIT）と異なる場合は、そのスキルディレクトリ自身のライセンスが優先されます。

## インストール

オープンな [`SKILL.md`](https://agentskills.io) 標準に準拠しています。

```bash
# GitHub CLI
gh skill install hideokamoto/skills wordpress-handbook

# Vercel skills CLI
npx skills add hideokamoto/skills --skill wordpress-handbook
```

## ライセンス

このリポジトリ自体のファイルは [MIT](./LICENSE)。各スキルの個別ライセンスは、それぞれの `SKILL.md` を参照してください。
