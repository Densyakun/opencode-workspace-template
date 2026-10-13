#!/usr/bin/env bash
# stop-codespace.sh
# ---------------------------------------------------------------------------
# 自分自身の Codespace を「安全に」停止する。
#
# 背景（重要）:
#   Codespaces が自動注入する GITHUB_TOKEN は読み取り専用
#   （応答ヘッダ x-accepted-github-permissions: codespaces=read）で、
#   POST /user/codespaces/{name}/stop は 403 になる。停止には別途
#   codespace 権限付き PAT（Codespaces シークレット CODESPACE_STOP_TOKEN）が必須。
#
# このスクリプトの安全策:
#   1) 三重照合（CODESPACE_NAME / CLOUDENV_ENVIRONMENT_ID / API応答の owner）が
#      すべて一致した時だけ停止する（誤って別環境を落とさない）。
#   2) 停止用トークンが無い場合は停止せず、理由をログして安全に終了する。
#   3) PAT は出力・保存しない。環境変数経由でのみ扱う。
#
# 依存: curl（必須）。gh があれば gh で停止（無くても curl で停止可能）。
#       python3 には依存しない（イメージに無いため）。
#
# 使い方:
#   CODESPACE_STOP_TOKEN=xxxx bash .devcontainer/stop-codespace.sh
#   CODESPACE_STOP_TOKEN=xxxx bash .devcontainer/stop-codespace.sh --dry-run
#   CODESPACE_STOP_TOKEN=xxxx bash .devcontainer/stop-codespace.sh --check
#
#   --dry-run : 三重照合のみ（停止しない）
#   --check   : 実装前のプリフライト。トークンの有無・照合に加え、classic PAT なら
#               scope を検証する（fine-grained の lifecycle admin 権限は
#               停止を実行するまで断定できないため UNVERIFIED を返す）
#
# 終了コード:
#   0 = 停止要求に成功 / dry-run で照合成功
#   2 = 三重照合に失敗（安全のため停止せず）
#   3 = 停止用トークンが無い、または権限不足と判明（安全のため停止せず）
#   4 = 停止APIの呼び出しに失敗
#   5 = --check: トークンは有効そうだが停止権限を非破壊では検証できない
# ---------------------------------------------------------------------------
set -u

: "${CODESPACE_NAME:=}"
: "${CLOUDENV_ENVIRONMENT_ID:=}"
: "${GITHUB_USER:=}"
# 読み取り照合用（Codespaces が自動注入する読み取り専用トークン）。
: "${GITHUB_TOKEN:=}"
# 停止用 PAT。Codespaces シークレット名は GITHUB_ で始められないため別名にする。
: "${CODESPACE_STOP_TOKEN:=}"
: "${STOP_TOKEN:=$CODESPACE_STOP_TOKEN}"
: "${GH_TOKEN:=}"

LOG="${STOP_LOG:-/tmp/stop-codespace.log}"
log() { echo "[stop-codespace] $(date -u +%Y-%m-%dT%H:%M:%SZ) $*" | tee -a "$LOG" >&2; }

MODE=stop
case "${1:-}" in
  --dry-run) MODE=dry ;;
  --check)   MODE=check ;;
esac
DRY_RUN=0
[ "$MODE" = "dry" ] && DRY_RUN=1

# 停止に使うトークン（優先: CODESPACE_STOP_TOKEN → STOP_TOKEN → GH_TOKEN）。
# 組み込み GITHUB_TOKEN は読み取り専用なので意図的に候補に含めない。
stop_token="${CODESPACE_STOP_TOKEN:-${STOP_TOKEN:-${GH_TOKEN:-}}}"

# ---- Codespaces 環境か -------------------------------------------------------
if [ "${CODESPACES:-}" != "true" ] || [ -z "$CODESPACE_NAME" ]; then
  log "Codespaces 環境ではないため停止しません（CODESPACES=$CODESPACES, CODESPACE_NAME='$CODESPACE_NAME'）"
  exit 0
fi

# ---- 1) 対象の三重照合（読み取りは GITHUB_TOKEN でよい） ----------------------
read_token="${GITHUB_TOKEN:-$stop_token}"
if [ -z "$read_token" ]; then
  log "照合用トークンが無いため対象を確認できず、停止しません"
  exit 2
fi

body="$(curl -fsS --max-time 15 \
  -H "Authorization: Bearer $read_token" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/user/codespaces/${CODESPACE_NAME}" 2>/dev/null || true)"

if [ -z "$body" ]; then
  log "Codespaces API から対象情報を取得できず、停止しません（ネットワーク等）"
  exit 2
fi

jget() { printf '%s' "$body" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -n1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/'; }
api_name="$(jget name)"
api_env="$(jget environment_id)"
api_owner="$(jget login)"

log "照合: name='$api_name' env_id='$api_env' owner='$api_owner' state='$(jget state)'"
if [ "$api_name" != "$CODESPACE_NAME" ] || [ "$api_env" != "$CLOUDENV_ENVIRONMENT_ID" ] || [ "$api_owner" != "$GITHUB_USER" ]; then
  log "対象が一致しません（name/env_id/owner の三重照合に失敗）。停止しません"
  exit 2
fi
log "照合OK: 停止対象は $CODESPACE_NAME（owner=$api_owner）で確定"

if [ "$DRY_RUN" = "1" ]; then
  log "--dry-run のため停止しません"
  exit 0
fi

# ---- 1.5) --check: 実装前のプリフライト --------------------------------------
if [ "$MODE" = "check" ]; then
  if [ -z "$stop_token" ]; then
    log "[check] 停止用トークン（CODESPACE_STOP_TOKEN）が未設定です → 停止できません"
    exit 3
  fi
  hdrf="$(mktemp)"
  code="$(curl -s -D "$hdrf" -o /dev/null -w '%{http_code}' --max-time 15 \
    -H "Authorization: Bearer $stop_token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/user/codespaces/${CODESPACE_NAME}" 2>/dev/null)"
  scopes="$(grep -i '^x-oauth-scopes:' "$hdrf" 2>/dev/null | head -n1 | sed -E 's/^[^:]*:[[:space:]]*//; s/\r$//')"
  rm -f "$hdrf"
  if [ "$code" != "200" ]; then
    log "[check] 停止用トークンで対象を取得できません（HTTP=$code）。無効・期限切れ・権限不足の可能性 → 停止不可"
    exit 3
  fi
  if [ -n "$scopes" ]; then
    if printf '%s' "$scopes" | tr -d ' ' | grep -q 'codespace'; then
      log "[check] classic PAT scope=「$scopes」に codespace を確認 → 停止可能"
      exit 0
    fi
    log "[check] classic PAT scope=「$scopes」に codespace が無い → 停止不可"
    exit 3
  fi
  log "[check] トークンは有効・三重照合もOK。ただし fine-grained の停止権限（Account permissions → Codespaces lifecycle admin → Read and write）は非破壊では検証できません"
  log "[check] → VERIFIED にするには実際の停止時のみ確定します。付与漏れが不安なら、影響の無いタイミングで一度実際に停止して確認してください"
  exit 5
fi

# ---- 2) 停止用トークンの確認 -------------------------------------------------
if [ -z "$stop_token" ]; then
  log "停止用トークン（CODESPACE_STOP_TOKEN）が未設定のため停止しません。"
  log "組み込み GITHUB_TOKEN は読み取り専用で停止できません。Codespaces シークレットに codespace 権限付き PAT を CODESPACE_STOP_TOKEN として登録してください"
  exit 3
fi

# ---- 3) 停止（curl を主、gh があれば gh を副で使用） -------------------------
log "停止を要求します: $CODESPACE_NAME"

stopped=0
if command -v gh >/dev/null 2>&1; then
  if GH_TOKEN="$stop_token" gh codespace stop -c "$CODESPACE_NAME" >/dev/null 2>&1; then
    stopped=1
    log "gh による停止要求に成功"
  else
    log "gh による停止要求に失敗（curl にフォールバック）"
  fi
fi

if [ "$stopped" != "1" ]; then
  if curl -fsS --max-time 60 -X POST \
      -H "Authorization: Bearer $stop_token" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/user/codespaces/${CODESPACE_NAME}/stop" >/dev/null 2>&1; then
    stopped=1
    log "curl による停止要求に成功"
  else
    log "停止APIの呼び出しに失敗しました（トークンの権限/スコープを確認してください）"
    exit 4
  fi
fi

# ---- 4) 停止状態への遷移を確認（任意） --------------------------------------
state="$(curl -fsS --max-time 15 \
  -H "Authorization: Bearer $read_token" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/user/codespaces/${CODESPACE_NAME}" 2>/dev/null \
  | grep -o '"state"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed -E 's/.*"([^"]*)"$/\1/')"
log "停止要求を送信しました（現在の state='${state:-unknown}'）"
exit 0
