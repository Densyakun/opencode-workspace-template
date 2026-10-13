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
| `CONFIG_REPO` / `CONFIG_BRANCH` / `CONFIG_TOKEN` | 自分の opencode 設定リポジトリ（例: `opencode-config-template` を fork した private repo）を `~/.config/opencode` に同期。未設定ならスキップ |
| `TARGET_REPO` / `TARGET_BRANCH` / `TARGET_DIR` | 起動時に自動 clone する対象リポジトリ |

`GITHUB_TOKEN` は Codespaces が自動注入します（読み取り専用）。

## 構成

```
opencode-workspace-template/
├── .devcontainer/
│   ├── Dockerfile               軽量ベース + opencode プリインストール
│   ├── devcontainer.json        public:4096 + hostRequirements + postStartCommand
│   ├── start-opencode.sh        有限ランチャー（config同期 + デーモン分離起動）
│   └── start-opencode-daemon.sh opencode 常駐監視・自動再起動
├── setup-target.sh              対象リポジトリの自動 clone
├── .gitattributes               .sh を LF 固定
└── .gitignore
```

## 注意

- パスワード等の秘密はリポジトリに置かず、必ず Codespaces シークレットを使ってください。
- `.devcontainer` の変更は **Rebuild Container** で初めて反映されます。
