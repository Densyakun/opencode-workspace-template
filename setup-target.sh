#!/usr/bin/env bash
# setup-target.sh
# ---------------------------------------------------------------------------
# 作業対象リポジトリを Codespace のワークスペースへ clone し、opencode で開く。
#
# 環境変数（Codespaces シークレットから注入される想定）:
#   TARGET_REPO      対象リポジトリの clone URL（https:// または git@ 形式）
#                    ※未設定なら何もせずスキップ（自分で git clone して下さい）
#   TARGET_BRANCH    （任意）clone するブランチ。未設定なら既定ブランチ
#   TARGET_DIR       （任意）clone 先のサブディレクトリ名。未指定ならリポジトリ名
#
# private リポジトリの認証:
#   GitHub  : GITHUB_TOKEN（Codespaces が自動注入・github_pat / PAT）
#   GitLab  : GITLAB_TOKEN（PRIVATE-TOKEN）→ oauth2:<token>@ 埋め込みで使用
#
# 使い方:
#   起動時自動実行: .devcontainer/start-opencode.sh で TARGET_REPO が有効なら呼び出す
#   手動実行     : bash setup-target.sh
# ---------------------------------------------------------------------------
set -u

: "${TARGET_REPO:=}"
: "${TARGET_BRANCH:=}"
: "${TARGET_DIR:=}"

DEFAULT_DIR="/workspaces/$(basename "$PWD")"
log() { echo "[setup-target] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >>/tmp/setup-target.log; }

if [ -z "$TARGET_REPO" ]; then
  log "TARGET_REPO が未設定のためスキップ"
  exit 0
fi

# 認証を URL に埋め込む。GitHub は token@ で github.com を置換、GitLab は oauth2 で認証。
auth_url="$TARGET_REPO"
if [ "$auth_url" = "git@github.com"* ]; then
  # SSH はそのまま（Codespace の SSH 鍵設定次第）
  :
elif [ -n "${GITHUB_TOKEN:-}" ] && [ "$auth_url" = "https://github.com"* ]; then
  auth_url="$(printf '%s' "$auth_url" | sed -E 's#https://#https://'"$GITHUB_TOKEN"'@#' | head -1)"
elif [ -n "${GITLAB_TOKEN:-}" ] && [ "$auth_url" = "https://gitlab."* ]; then
  auth_url="$(printf '%s' "$auth_url" | sed -E 's#https://#https://oauth2:'"$GITLAB_TOKEN"'@#' | head -1)"
fi

dst="${TARGET_DIR:-}"
if [ -z "$dst" ]; then
  dst="$(basename "${TARGET_REPO%.git}")"
fi
dst="$DEFAULT_DIR/$dst"

if [ -d "$dst/.git" ]; then
  log "$dst は既に clone 済み"
  exit 0
fi

log "clone 開始: $TARGET_REPO → $dst"
mkdir -p "$DEFAULT_DIR"
if [ -n "$TARGET_BRANCH" ]; then
  GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$TARGET_BRANCH" "$auth_url" "$dst"
else
  GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$auth_url" "$dst"
fi
ret=$?
if [ $ret -ne 0 ]; then
  log "clone に失敗しました（認証・URL・ネットワークを確認してください）"
  exit $ret
fi
log "clone 完了: $dst"
echo "Target cloned to: $dst"
exit 0
