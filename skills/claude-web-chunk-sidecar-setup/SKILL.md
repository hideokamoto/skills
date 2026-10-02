---
name: claude-web-chunk-sidecar-setup
description: >-
  Claude Code on the web（claude.ai/code のクラウドコンテナ）から CircleCI
  の chunk sidecar を使えるようにセットアップする。web のコンテナには rsync と OpenSSH
  クライアントが無く、さらに chunk が作る鍵 ~/.ssh/chunk_ai が PKCS#8 形式の
  ed25519 で OpenSSH が読めないため、「chunk sidecar ssh は通るのに chunk
  sidecar sync だけ失敗する」。この2つを同梱のスクリプトで直し、sync
  を含めた往復が通ることを確認する。「web で chunk sidecar sync が失敗する」「rsync:
  executable file not found」「Load key "~/.ssh/chunk_ai":
  invalid format」「Permission denied (publickey) で sync
  できない」「クラウドの Claude Code から sidecar を使いたい」「sidecar
  にファイルを送れない」といった相談では、明示的に名指しされていなくても必ずこのスキルを使うこと。
license: MIT
---

# Claude Code on the web × Chunk Sidecar セットアップ

Claude Code on the web のコンテナから `chunk sidecar` を使うための準備手順。
`chunk sidecar ssh` はそのまま動くが、`chunk sidecar sync` は2つの理由で失敗する。
このスキルは、その2つを同梱のスクリプトで直し、実際に sync が通るところまで確かめる。

sidecar の作成やスナップショット運用そのものは、CircleCI の `chunk-sidecar` スキル
（sync → validate のループ）の担当。Cursor Cloud Agent 向けは、兄弟スキルの
`cursor-chunk-sidecar-setup` が担当する。

## 背景（なぜ web ではそのまま sync が動かないか）

### 原因1: sync は外部の rsync と OpenSSH を使うが、web のコンテナには無い

`chunk sidecar sync` が実際に組み立てるコマンドは次のとおり。`ssh` と `rsync` を
引数を記録するラッパーに差し替えて取得した。

```text
rsync --archive --delete --filter=":- .gitignore" \
  -e "ssh -p <中継ポート> -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ProxyCommand=none -o ProxyJump=none -o ControlPath=none -o RequestTTY=no \
      -o IdentitiesOnly=yes -i ~/.ssh/chunk_ai" \
  <git ルート>/ user@127.0.0.1:<git ルート>
```

- **ssh だけが通る理由**: `chunk sidecar ssh` は手元の `ssh` コマンドを使わない。
  OpenSSH クライアントを入れる前から動いていた。そのため、web のコンテナでは
  「ssh は通るのに sync だけ失敗する」状態になる。
- **導入時の落とし穴**: コンテナのパッケージ一覧が古いことがあり、`apt-get update`
  をしないと `openssh-client` の取得が 404 で失敗した。
- **直すのは手元（web のコンテナ）側だけ**: `rsync: exec: "rsync": executable file not found`
  は手元の PATH で見つからないときのエラー。sidecar 側の rsync は、無ければ chunk が
  自分で入れる（chunk 本体に `which rsync` と `apt-get install -y -qq rsync`、
  `rsync: install rsync on sidecar` の文字列がある。実行時の動作は未確認）。

### 原因2: chunk が作る鍵を OpenSSH が読めない

- chunk は `~/.ssh/chunk_ai` が無いと、自分で鍵を作る。その鍵は PKCS#8 形式の ed25519
  （先頭行が `-----BEGIN PRIVATE KEY-----`）で、OpenSSH 9.6 は
  `Load key "~/.ssh/chunk_ai": invalid format` として読めない。
- **chunk とは無関係に再現できる**:

  | 鍵 | 形式 | OpenSSH 9.6 で読めたか |
  |----|------|-----------------------|
  | ed25519（openssl で生成） | PKCS#8 | 読めない（invalid format） |
  | ECDSA P-256 | PKCS#8 | 読めた |
  | RSA 2048 | PKCS#8 | 読めた |
  | ed25519（ssh-keygen で生成） | OpenSSH | 読めた |

- **chunk 自身は OpenSSH 形式も読める**: OpenSSH 形式にそろえれば、ssh と sync の
  両方が動く。
- **鍵を作り直しても既存の sidecar に影響しない**: 作り直した鍵でも、古い鍵で作った
  既存の sidecar に `chunk sidecar add-ssh-key` なしで接続できた。
- **鍵を消して chunk に作り直させても直らない**: chunk が作り直す鍵はまた PKCS#8 になる。
  消すのではなく、OpenSSH 形式に変換するか `ssh-keygen` で作る（Step 1 のスクリプトがやる）。

## Step 0: 事前確認

1. **web 環境か**: `echo "$CLAUDE_CODE_REMOTE"` が `true` なら Claude Code on the web。
   それ以外の環境でもスクリプトは動くが、検証したのは web のコンテナ（Ubuntu 24.04・root）だけ。
2. **認証**: `chunk auth status` で CircleCI のトークンが有効かを見る。
   - web では、環境変数 `CIRCLE_TOKEN` か `CIRCLECI_TOKEN` から読まれる。
   - 無ければ、ユーザーに環境の設定（環境変数）へ追加してもらう。トークンの値を会話で
     受け取ったり、ファイルに書いたりしない。
3. **orgID**: `.chunk/config.json` に orgID が無い操作で org を聞かれたら、**一度だけ**
   ユーザーに尋ね、`chunk config set orgID <id>` で保存する。
   - org ID は、どこかで見た値（別リポジトリや会話の途中に出た値）を確認なしに使わない。
     このスキルは誰の環境でも使うので、他人の org を叩く事故になる。

`chunk` が入っていなくても、Step 1 のスクリプトが入れるので先に進んでよい。

## Step 1: セットアップスクリプトを実行する

```bash
bash "${CLAUDE_SKILL_DIR}/assets/setup-claude-web.sh"
```

`${CLAUDE_SKILL_DIR}` は、Claude Code がこの SKILL.md の置かれたディレクトリに展開する。
展開されない場合は、この SKILL.md の実際の場所から `assets/setup-claude-web.sh`
のパスを組み立てる。素の `assets/...` だと、シェルはプロジェクトのルートにいるので
見つからない。

**スクリプトがすること**（何度実行しても同じ結果になる）:

1. **rsync と openssh-client を入れる**: 無いときだけ入れる。最初の導入に失敗したら、
   `apt-get update` してから入れ直す。
2. **chunk を入れる**: 無いときだけ、GitHub Releases の直接ダウンロード URL から入れる。
   置き場所は、書き込めれば `/usr/local/bin`、だめなら `~/.local/bin`。
3. **鍵 `~/.ssh/chunk_ai` を OpenSSH 形式にそろえる**:
   - 無ければ `ssh-keygen` で作る。
   - PKCS#8 なら、元の鍵を `~/.ssh/chunk_ai.bak.<日時>` に退避してから直す。
     python の `cryptography` があれば同じ鍵のまま変換し、指紋の一致を確かめる。
     無ければ作り直す。
   - すでに OpenSSH で読める鍵なら何もしない。

ログはすべて標準エラーに `[setup-claude-web]` の印付きで出る。結果をユーザーに見せる。

## Step 2: sync が往復で通ることを確かめる

「たぶん動く」で終わらせず、実際にファイルを送って届いたことまで見せる。

1. **sidecar を用意する**: `chunk sidecar current` で、アクティブな sidecar があるかを見る。
   - 無ければ、`.chunk/config.json` の `validation.sidecarImage`（スナップショット ID）
     から作る: `chunk sidecar create --image <id>`。
   - それも無ければ `chunk sidecar create`。
2. **目印のファイルで往復を確かめる**: `.gitignore` に入っていないファイルを使う。

   ```bash
   echo "sync-probe $(date +%s)" > .chunk-sync-probe
   chunk sidecar sync
   chunk sidecar ssh -- cat "$(git rev-parse --show-toplevel)/.chunk-sync-probe"
   rm .chunk-sync-probe && chunk sidecar sync   # 目印を消し、sidecar 側からも消す
   ```

   `cat` が同じ内容を返せば成功。

## 運用上の注意（実際に踏んだもの）

- **sync の対象は git ルート全体**: サブディレクトリで実行しても、リポジトリ全体が
  sidecar の同じパスへ送られる。`.gitignore` 対象（`node_modules` など）は送られない。
  `--delete` 付きなので、手元に無いファイルは sidecar からも消える。テスト結果を
  リポジトリ内に出すと、次の sync で消えることがある。結果は `/tmp` などに出す。
- **アクティブな sidecar はプロジェクトごとに決まる**: 記録先はプロジェクトの
  `.chunk/sidecar.json`（`chunk sidecar use <id>` や `create` で書かれる。
  chunk 本体の文字列とヘルプで確認）。
  - リポジトリの外（`/tmp` など）から打つと「No active sidecar is set」になる。
    `--sidecar-id <id>` を付ければ、どこからでも動く。
  - コンテナはセッションごとに作り直されるので、前のセッションの記録は残らない。
  - セッションごとに変わるローカルな状態なので、`.gitignore` に入っていなければ、
    誤ってコミットしないよう注意する。
- **`chunk sidecar snapshot create` は元の sidecar を削除する**: 撮ったあとも作業を続けたいなら、
  スナップショットから作り直す前提で動く。
- **`chunk sidecar ssh -- <cmd>` の標準出力はデータの通り道**: ファイルを
  `tar` やハッシュ一覧で取り出すときは、ログを標準エラーに逃がす。ログが1行混ざって
  ハッシュ照合が一致しなくなったことがある。
- **sidecar 側はプロキシなしで外へ直接つながる**: 手元の web コンテナはプロキシ経由。
  ブラウザのテストなど、外部へ通信する処理は sidecar で動かすと設定が要らない。
- **スナップショットの効果は「手順が減る」ことが主**: 実測（Playwright の E2E 9本、各1回）では、
  テストが通るまでが 63.8 秒から 50.7 秒になった（約2割の短縮）。導入の36秒は消えるが、
  スナップショットからの作成と最初の接続がそれぞれ約10秒ずつ遅くなる。

## sync がどうしても使えないときの代わり

`chunk sidecar ssh` は標準入出力をそのまま通すので、tar で送れる。差分転送や削除の反映は
できないので、毎回まとめて送り直すことになる。

```bash
# 手元 → sidecar
tar czf - --exclude=node_modules --exclude=.git . \
  | chunk sidecar ssh -- sh -c 'mkdir -p /home/user/app && tar xzf - -C /home/user/app'

# sidecar → 手元（取り出す前後でハッシュを照合する）
chunk sidecar ssh -- sh -c 'cd /tmp && find out -type f -exec sha256sum {} + | sort -k2' > remote.sha256
chunk sidecar ssh -- tar czf - -C /tmp out > out.tgz && tar xzf out.tgz
find out -type f -exec sha256sum {} + | sort -k2 | diff - remote.sha256 && echo MATCH
```

## 常設化（セッション開始時の自動実行）

未確定。Step 1 のスクリプトを、新しいセッションのたびに自動で走らせる仕込み先は2つある。

- 環境設定画面の「セットアップスクリプト」
- リポジトリの `.claude/settings.json` の SessionStart フック

どちらにするかは、利用者の運用に合わせて決める。それまでは、セッションごとに Step 1 を
手動で実行する。

## 検証状況（何をどこまで確かめたか）

- **確かめた環境（2026-10-02）**:

  | 項目 | 値 |
  |------|-----|
  | 実行場所 | Claude Code on the web（Ubuntu 24.04、root） |
  | chunk | v0.7.192（GitHub Releases の latest の直接ダウンロードで取得できた版も同じ） |
  | OpenSSH | 9.6p1 |
  | rsync | 3.2.7 |
  | sidecar 側 | Ubuntu 24.04、rsync 3.2.7、sshd あり |

- **実機で確認したこと**:
  - sync が組み立てる rsync / ssh の引数。
  - PKCS#8 の ed25519 だけが読めないこと（上の表）。
  - 鍵を変換すると、素の `chunk sidecar sync` が通ること。
    - 初回5〜7秒、差分約5秒。
    - 880ファイルが一致し、`node_modules` は除外された。
  - 変換した鍵・作り直した鍵のどちらでも、新規の sidecar と既存の sidecar の両方に
    `add-ssh-key` なしで ssh と sync が通ること。
  - chunk が一度作った鍵を、その後の sidecar 作成で作り直さないこと。
  - web のコンテナから見た GitHub の到達性:

    | 宛先 | 結果 |
    |------|------|
    | `releases/latest/download/<アセット名>` | 取得できた（302 で `release-assets.githubusercontent.com` へ転送） |
    | Releases のページ | 403 |
    | `api.github.com` | 403 |

- **確かめていないこと**:
  - 新しい版の chunk で鍵の形式が変わったか。2026-10-02 時点の最新リリースは v0.7.192。
  - root ではない（sudo で動く）環境でのスクリプトの動作。
  - 鍵を作り直しても既存の sidecar に入れる仕組み（chunk が接続時に登録し直しているとみられる）。

## トラブルシュート

| 症状 | 確認すること |
|------|-------------|
| `rsync: exec: "rsync": executable file not found in $PATH` | Step 1 のスクリプトを実行する |
| `rsync: [sender] Failed to exec ssh: No such file or directory` | 同上（openssh-client が無い） |
| `apt-get install` が 404 | `apt-get update` してから入れ直す（スクリプトは自動でやる） |
| `Load key "~/.ssh/chunk_ai": invalid format` | 鍵が PKCS#8。Step 1 のスクリプトが OpenSSH 形式にそろえる |
| `Permission denied (publickey)` | 直前に invalid format が出ていないか。出ていれば上と同じ |
| 鍵を消して作り直させたのに、まだ invalid format | chunk が作る鍵は再び PKCS#8 になる。Step 1 のスクリプトで OpenSSH 形式にそろえる |
| `No active sidecar is set` | リポジトリの外で実行していないか。`--sidecar-id` を付ける |
| sync 後に sidecar 上のファイルが消えた | `--delete` で手元に無いファイルが消えた。結果は `/tmp` に出す |
| chunk の取得が失敗する | ネットワークの許可設定で `github.com` と `release-assets.githubusercontent.com` が通るか |

## 参考

- [chunk-cli (GitHub)](https://github.com/CircleCI-Public/chunk-cli)
- [Chunk CLI インストールガイド](https://circleci.com/docs/guides/toolkit/install-and-configure-the-chunk-cli/)
- 兄弟スキル `cursor-chunk-sidecar-setup`（chunk の導入処理と orgID の扱いの出典）
- CircleCI の `chunk-sidecar` スキル（sidecar の作成・スナップショット・validate のループ）
