# opencode-workspace-template

GitHub Codespaces で **opencode の Web UI を高速・確実に起動する**ための公開テンプレートです。
このリポジトリから Codespace を作成すると、数分で opencode が起動します。その中で任意のリポジトリを clone して開発できます。

秘密情報は一切含みません。必要な値は **Codespaces シークレット**（各自のアカウント）から注入します。

## 使い方（単体で使う）

1. GitHub で **「Use this template」** または fork して、自分のリポジトリにコピーします。
2. 自分のリポジトリで **「<> Code」→「Codespaces」→「Create codespace」** を選びます。
3. `postStartCommand` が opencode を起動します。数分後、公開URL `https://<codespace名>-4096.app.github.dev` にアクセスできます。
   - ユーザー名: `opencode`
   - パスワード: `OPENCODE_SERVER_PASSWORD` シークレットを設定（推奨）。未設定なら初回起動時に生成され `~/.opencode/.webpass` に保存されます。

## 設定する Codespaces シークレット（すべて任意）

| シークレット | 用途 |
|---|---|
| `OPENCODE_SERVER_PASSWORD` | opencode Web の Basic 認証パスワード（推奨） |
| `CODESPACE_STOP_TOKEN` | 自動停止に必須の PAT。fine-grained は Account permissions → Codespaces lifecycle admin: Read and write、classic は scope `codespace` |
| `CONFIG_REPO` / `CONFIG_BRANCH` / `CONFIG_TOKEN` | 自分の opencode 設定リポジトリ（例: `opencode-config-template` を fork した private repo）を `~/.config/opencode` に同期。未設定ならスキップ |
| `TARGET_REPO` / `TARGET_BRANCH` / `TARGET_DIR` | 起動時に自動 clone する対象リポジトリ |

`GITHUB_TOKEN` は Codespaces が自動注入します（読み取り専用）。停止には使えないため、停止には `CODESPACE_STOP_TOKEN`（`codespace` 権限）が必要です。

## Kozmik Cloud Dashboard と連携する場合（任意）

Cloudflare 版ダッシュボード（`kozmik-cloud-dashboard`）を使うと、スマホから Codespace の起動・停止・opencode パスワード確認ができます。
連携を使う場合は、次の 2 つの Codespaces シークレットがダッシュボード側から自動投入されます（手動設定は不要です）。

| シークレット | 用途 |
|---|---|
| `DASHBOARD_BASE_URL` | ダッシュボードの URL |
| `PRESENCE_TOKEN` | 監視スイッチ（在席/不在）をダッシュボードから読むためのトークン |

## 構成

```
opencode-workspace-template/
├── .devcontainer/
│   ├── Dockerfile               軽量ベース + opencode プリインストール
│   ├── devcontainer.json        public:4096 + hostRequirements + postStartCommand
│   ├── start-opencode.sh        有限ランチャー（config同期 + デーモン分離起動）
│   ├── start-opencode-daemon.sh opencode 常駐監視・自動再起動
│   ├── presence-monitor.sh      不在時に自動停止（停止は stop-codespace.sh に委譲）
│   └── stop-codespace.sh        三重照合つきの安全な自己停止（PAT 必須）
├── setup-target.sh              対象リポジトリの自動 clone
├── .gitattributes               .sh を LF 固定
└── .gitignore
```

## 自動停止の仕組み

`presence-monitor.sh` が「監視中スイッチ」を参照します。スイッチが **不在(OFF)** で、opencode の全セッションが完了してから猶予時間（既定180秒）続くと、Codespace を自動停止します。

- ダッシュボード連携時は `DASHBOARD_BASE_URL` + `PRESENCE_TOKEN` から状態を取得します。
- 未設定の場合は、自分のリポジトリの `presence` ブランチの `presence.json`（`{"monitoring": false}`）を参照します。
- どちらも読めない場合は **監視中（停止しない）** の安全側に倒れます。

## 注意

- パスワード等の秘密はリポジトリに置かず、必ず Codespaces シークレットを使ってください。
- `.devcontainer` の変更は **Rebuild Container** で初めて反映されます。
