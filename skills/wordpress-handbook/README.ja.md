# wordpress-handbook

[developer.wordpress.org](https://developer.wordpress.org/) が公開している WordPress 公式開発者ハンドブックを検索し、プラグイン・テーマ・ブロックエディター・REST API・コーディング規約などの質問に一次情報で答えられるようにする [Agent Skill](https://agentskills.io) です。

親リポジトリ: [hideokamoto/wordpress-skills](https://github.com/hideokamoto/wordpress-skills)

## できること

- **検索**でハンドブック内の記事を探し、必要に応じて **本文取得**で HTML 全文を取りにいく二段構成です。
- 次の 7 種類のハンドブックを対象にできます（プラグイン、テーマ、ブロック、REST API、共通 API、コーディング規約、高度な管理）。

## 対象ハンドブック

| Shortname | Subtype | 内容 |
|-----------|---------|------|
| `plugin` | `plugin-handbook` | プラグイン開発 |
| `theme` | `theme-handbook` | テーマ開発 |
| `block` | `blocks-handbook` | ブロックエディター（Gutenberg） |
| `rest-api` | `rest-api-handbook` | REST API |
| `apis` | `apis-handbook` | 共通 API（設定・オプションなど） |
| `coding` | `wpcs-handbook` | WordPress コーディング規約 |
| `admin` | `adv-admin-handbook` | 高度な管理 |

## インストール（推奨）

パスやバージョンを揃えるため、まとまったリポジトリ [wordpress-skills](https://github.com/hideokamoto/wordpress-skills) から入れるのがおすすめです。

### GitHub CLI（`gh skill`）

```bash
gh skill install hideokamoto/wordpress-skills wordpress-handbook

# バージョンを固定
gh skill install hideokamoto/wordpress-skills wordpress-handbook --pin v0.1.0
```

### Vercel skills CLI（`npx skills`）

```bash
npx skills add hideokamoto/wordpress-skills --skill wordpress-handbook
```

## スクリプトをローカルで動かす

スキルのルート（`SKILL.md` と `scripts/` があるディレクトリ）で実行します。

### 1. 検索

```bash
python3 scripts/search.py "<query>" [handbook|all] [limit]
```

| 引数 | 必須 | 説明 |
|------|------|------|
| `query` | はい | 検索キーワード |
| `handbook` | いいえ | 上表の Shortname または `all`。省略時は全ハンドブック |
| `limit` | いいえ | 件数（既定 5、最大 20） |

出力: `{ id, title, url, handbook, subtype }` の JSON 配列。

例:

```bash
python3 scripts/search.py "custom post type"
python3 scripts/search.py "register_post_type" plugin
python3 scripts/search.py "naming conventions" coding 10
```

### 2. 本文取得

検索結果の `subtype` と `id` を渡します。

```bash
python3 scripts/fetch_content.py "<subtype>" <id>
```

出力: `{ id, title, url, excerpt, content }` の JSON（`content` に HTML）。

```bash
python3 scripts/fetch_content.py plugin-handbook 11070
```

## エージェント上の流れ（要約）

1. `search.py` で記事を探す  
2. ユーザーにタイトルと URL を示す  
3. 詳細が必要なら、結果の `subtype` と `id` で `fetch_content.py` を呼ぶ  
4. 返った HTML を要約・引用する  

## 動作環境

- **Python 3.x**（スクリプト実行）
- **ネットワーク**（`developer.wordpress.org` へ HTTPS）

## 注意

- 検索 API ではタイトル・URL などに限られるため、全文は `fetch_content.py` を使う  
- 本文は HTML のため、利用側で整形・タグ除去が必要な場合があります  
- `handbook` を省略すると横断検索になり、広いトピック向きです  

## ライセンス

Apache-2.0（親リポジトリの `LICENSE` を参照）

## English

For the English README, see [README.md](./README.md).
