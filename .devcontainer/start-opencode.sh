#!/usr/bin/env bash
# start-opencode.sh
# ---------------------------------------------------------------------------
# Codespaces の postStartCommand から実行される「有限」のランチャー。
#
# 重要: GitHub Codespaces は postStartCommand が終了するまで Codespace を
# "Starting/Provisioning" 状態のままにする。そのため本スクリプトは
# 必ず「短時間で exit 0 すること」（ここを while true にすると起動が完了しない）。
#
# 動作:
#   1) 設定（private の config-opencode）を ~/.config/opencode へ反映（タイムアウト付き）
#   2) opencode を未インストールなら導入
#   3) opencode 常駐監視デーモンを「分離起動（detach）」してから
#      すぐ exit 0 する（デーモン本体は新しいセッションで独立して生き続ける）
# ---------------------------------------------------------------------------
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG=/tmp/start-opencode.log

log() { echo "[start-opencode] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*" >>"$LOG"; }

# 起動直後にログを書く。以後どこで失敗しても調査可能にする。
log "ランチャー起動: $(basename "$0")"

# 変数デフォルト。注意: ":-" を使わないと、参照先の変数が未設定の場合に
# set -u でスクリプト全体が即死する（コンテナの bash は厳密）。
# config 用トークンは未設定であることが普通なので必ず ":-" で防ぐ。
: "${OPENCODE_PORT:=4096}"
: "${OPENCODE_HOST:=0.0.0.0}"
: "${OPENCODE_BIN:=$HOME/.opencode/bin/opencode}"
: "${CONFIG_DIR:=$HOME/.config/opencode}"
: "${CONFIG_REPO:=}"
: "${CONFIG_BRANCH:=main}"
: "${TMP_CLONE:=$HOME/.opencode-config-tmp}"
# config リポジトリ用トークン。GitHub は CONFIG_TOKEN、GitLab は GITLAB_TOKEN を許容。
: "${CONFIG_TOKEN:=${GITLAB_TOKEN:-}}"

export GIT_TERMINAL_PROMPT=0
export PATH="$HOME/.opencode/bin:$PATH"

# ---- opencode Web の Basic 認証（port 4096 を public で公開するため必須） ----
# 優先: Codespaces シークレット OPENCODE_SERVER_PASSWORD。
# なければ一時パスワードを生成し ~/.opencode/.webpass に保持（再起動で同じ値になる）。
# ※~/.config/opencode は config-opencode の同期対象のため、鍵をそこに置かない。
PW_FILE="$HOME/.opencode/.webpass"
if [ -z "${OPENCODE_SERVER_PASSWORD:-}" ]; then
  mkdir -p "$HOME/.opencode"
  if [ -s "$PW_FILE" ]; then
    OPENCODE_SERVER_PASSWORD="$(cat "$PW_FILE")"
  else
    OPENCODE_SERVER_PASSWORD="$(command -v openssl >/dev/null 2>&1 && openssl rand -hex 16 2>/dev/null || echo "opencode-$(date +%s)")"
    printf '%s' "$OPENCODE_SERVER_PASSWORD" > "$PW_FILE"
    chmod 600 "$PW_FILE"
    log "OPENCODE_SERVER_PASSWORD 未設定のため一時パスワードを生成しました: $PW_FILE"
  fi
  export OPENCODE_SERVER_PASSWORD
fi
log "opencode Basic 認証を使用します（username=opencode）"

# タイムアウト付き実行ラッパー（外部コマンドのハング防止）
run_t() {
  if command -v timeout >/dev/null 2>&1; then timeout "$1" "${@:2}"; else "${@:2}"; fi
}

# デーモンの分離起動：新しいセッション(setsid)でバックグラウンド化し、disown して
# postStartCommand のプロセスグループとは切り離す。stdin/stdout/stderr は /dev/null へ。
launch_bg() {
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" >/dev/null 2>&1 < /dev/null &
  else
    nohup "$@" >/dev/null 2>&1 < /dev/null &
  fi
  disown 2>/dev/null || true
  return 0
}

# ---- 1) 設定の反映 ---------------------------------------------------------
sync_config() {
  mkdir -p "$CONFIG_DIR"
  # 認証トークンが無ければ同期そのものをスキップする。
  # private リポジトリを認証なしで clone しようとすると git の認証ヘルパーが
  # 対話入力を要求し、postStartCommand をブロックするため、必ず早期 return する。
  if [ -z "$CONFIG_REPO" ] || [ -z "$CONFIG_TOKEN" ]; then
    log "CONFIG_REPO / CONFIG_TOKEN 未設定のため config の同期をスキップ"
    return 0
  fi
  # private リポジトリはトークン埋め込みで認証（GitHub は x-access-token、GitLab は oauth2）
  local prefix="oauth2"
  case "$CONFIG_REPO" in *github.com*) prefix="x-access-token" ;; esac
  local auth_url="$(printf '%s' "$CONFIG_REPO" | sed -E 's#(https?://)[^@]*@#\1#; s#^https?://#&'"$prefix"':'"$CONFIG_TOKEN"'@#')"
  # どの git 操作でも認証ヘルパー（GUI入力）を無効化し、問い合わせを絶対にさせない
  local noask=(-c credential.helper=)
  if [ -d "$TMP_CLONE/.git" ]; then
    run_t 30 git "${noask[@]}" -C "$TMP_CLONE" remote set-url origin "$auth_url" 2>/dev/null || true
    run_t 30 git "${noask[@]}" -C "$TMP_CLONE" fetch --depth 1 origin "$CONFIG_BRANCH" 2>/dev/null || true
    run_t 30 git "${noask[@]}" -C "$TMP_CLONE" reset --hard "origin/$CONFIG_BRANCH" 2>/dev/null || true
  else
    rm -rf "$TMP_CLONE"
    run_t 30 git "${noask[@]}" clone --depth 1 "$auth_url" "$TMP_CLONE" 2>/dev/null || { log "設定のcloneに失敗（スキップ）"; return 0; }
  fi
  [ -d "$TMP_CLONE/.git" ] || { log "設定リポジトリが取得できません（スキップ）"; return 0; }

  local count=0
  while IFS= read -r -d '' f; do
    local src="$TMP_CLONE/$f" dst="$CONFIG_DIR/$f"
    if [ -f "$src" ]; then
      mkdir -p "$(dirname "$dst")"
      cp -f "$src" "$dst"
      count=$((count + 1))
    fi
  done < <(git "${noask[@]}" -C "$TMP_CLONE" ls-files -z 2>/dev/null)
  rm -rf "$TMP_CLONE"
  log "設定を反映しました（${count}ファイル）"
}

sync_config

# ---- 2) opencode の導入 ----------------------------------------------------
if [ ! -x "$OPENCODE_BIN" ]; then
  log "opencode をインストールします"
  run_t 120 curl -fsSL https://opencode.ai/install | bash >/tmp/opencode-install.log 2>&1 || true
fi
if [ ! -x "$OPENCODE_BIN" ]; then
  log "警告: opencode が見つかりません（$OPENCODE_BIN）。後続の監視デーモンで失敗する場合があります"
fi

# ---- 2.5) 対象リポジトリの自動 clone（TARGET_REPO が設定されている場合のみ・有限） -----
if [ -n "${TARGET_REPO:-}" ]; then
  if [ -f "$SCRIPT_DIR/../setup-target.sh" ]; then
    log "TARGET_REPO が設定されているため setup-target.sh を実行します"
    run_t 120 bash "$SCRIPT_DIR/../setup-target.sh" || log "setup-target.sh が失敗（スキップ）"
  else
    log "setup-target.sh が見つかりません（スキップ）"
  fi
fi

# ---- 3) デーモンを分離起動して即座に終了 -----------------------------------
launch_bg bash "$SCRIPT_DIR/start-opencode-daemon.sh"

log "ランチャー完了：デーモンを分離起動しました。postStartCommand を終了します"
exit 0
