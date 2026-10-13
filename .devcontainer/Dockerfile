# Kotlin-like lightweight base for the OpenCode Codespace.
# 目標: Codespaces の起動を高速化する。
#   以前: mcr.microsoft.com/devcontainers/universal:2（数GB・pull に数分）を要求
#   今回: debian:12-slim（~80MB）+ 最小限のツール群 + opencode をビルド時にプリインストール
#  → 初回作成も短時間、キャッシュ後はさらに高速になる。
#
# 必要なツール: opencode 本体(インストーラ)と各コアスクリプトの要求に限定。
#   - curl      : opencode インストール / ヘルスチェック
#   - git       : config リポジトリの同期（git clone / fetch / reset）
#   - tar, sed, grep : opencode インストーラが使用
#   - ca-certificates : TLS（github.com / gitlab.com / opencode.ai）
#   - util-linux : setsid（postStartCommand からデーモンを分離起動するために必須）
#   - openssl    : public ポートを守る Basic 認証パスワードの生成
#   - nodejs/npm : opencode ワークスペースで Node.js を使う（規定で Node 20 LTS を導入）
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/root \
    PATH="/root/.opencode/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    BROWSER=true \
    OPENCODE_DISABLE_AUTOUPDATE=true

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        tar \
        sed \
        grep \
        util-linux \
        openssl \
    && rm -rf /var/lib/apt/lists/*

# Node.js を規定で導入する（opencode ワークスペースで Node.js を使うため）。
# Debian 12 標準の nodejs は 18 系のため、Node 20 LTS を NodeSource から入れる。
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI (gh) を best-effort で導入する。開発中の PR / issue 操作などに
# 便利なため。ビルド時ネットワークの一時不調で失敗してもイメージビルド自体は
# 成功させる。
RUN set -eux; \
    for i in 1 2 3; do \
        if ( \
            mkdir -p -m 755 /etc/apt/keyrings \
            && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
            && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
            && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
            && apt-get update \
            && apt-get install -y --no-install-recommends gh \
            && rm -rf /var/lib/apt/lists/* \
        ); then \
            break; \
        fi; \
        echo "warning: gh pre-install attempt $i/3 failed, retrying..."; \
        sleep 5; \
    done; \
    if command -v gh >/dev/null 2>&1; then echo "gh pre-install OK"; else echo "warning: gh pre-install failed; continuing without gh"; fi

# opencode をビルド時にプリインストールする（起動時にダウンロード待ちをさせない）。
# 注意: インストーラはバージョン解決のために api.github.com 等へ外部通信する。
# ビルド時ネットワークの一時的な不調・レート制限で失敗してもイメージビルド自体は
# 成功させる（起動時の start-opencode.sh がバイナリ不在ならランタイムで
# インストールするフォールバックを持つ）。リトライ付きのベストエフォート方式。
RUN for i in 1 2 3; do \
        if curl -fsSL https://opencode.ai/install | bash; then \
            break; \
        fi; \
        echo "warning: opencode pre-install attempt $i/3 failed, retrying..."; \
        sleep 5; \
    done; \
    if command -v opencode >/dev/null 2>&1 || [ -x "$HOME/.opencode/bin/opencode" ]; then \
        echo "opencode pre-install OK"; \
    else \
        echo "warning: opencode pre-install failed; start-opencode.sh will install it at container start"; \
    fi

CMD ["/bin/bash"]
