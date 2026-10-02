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
| [`claude-web-chunk-sidecar-setup`](./skills/claude-web-chunk-sidecar-setup/) | Claude Code on the web（クラウドのコンテナ）で `chunk sidecar ssh` だけでなく `chunk sidecar sync` も動くようにします。rsync と OpenSSH クライアントを導入し、chunk が作る PKCS#8 形式の ed25519 鍵（Ubuntu 24.04 の OpenSSH が読めない）を OpenSSH 形式にそろえます。 | MIT |
| [`export-session-log`](./skills/export-session-log/) | Claude Code セッション自身の生の JSONL トランスクリプト（要約ではなく tool_use/tool_result を含む全イベント）を、別セッションやスクリプトで分析できるように引き渡します。 | MIT |
| [`dialogic-learning-style`](./skills/dialogic-learning-style/) | チャンク単位で解説し、ユーザーの返答から「進行」と「深掘り」のシグナルを見分けて、一方的な長大解説にも問い詰めにもならないよう対話のペースを制御するカスタム文体スキルです。 | MIT |
| [`research-handoff`](./skills/research-handoff/) | 調査・分析の依頼で、着手前に「結論を誰が出すか・前提知識の仮定・渡し方」を宣言し、成果物の書式をスクリプト（`check_handoff.py`）で検査します。読みにくさへの不満が来たときの出し直しにも使います。 | MIT |
| [`stop-and-align`](./skills/stop-and-align/) | 出力への否定や訂正を受けたとき、新しい作業に進まず、いま理解している要求を差し出して確認を待ちます。 | MIT |

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

`<skill-name>` には `wordpress-handbook` / `circleci-cli` / `cursor-chunk-sidecar-setup` / `claude-web-chunk-sidecar-setup` / `export-session-log` / `dialogic-learning-style` / `research-handoff` / `stop-and-align` のいずれかが入ります。

## ライセンス

このリポジトリ自体のファイルは [MIT](./LICENSE)。各スキルの個別ライセンスは、それぞれの `SKILL.md` を参照してください。
