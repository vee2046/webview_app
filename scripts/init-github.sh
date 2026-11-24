#!/usr/bin/env bash
# 把 webview_app 推到 GitHub，并打 tag 触发自动发版。
#
#   ./scripts/init-github.sh                 # 首次：加 remote + 推 main
#   ./scripts/init-github.sh --release       # 再打一个 tag → Actions 自动出包 + 发 Release
#
# ⚠️ 前提：GitHub 上**已经手动建好**空仓库 vee2046/webview_app
#    （https://github.com/new → 仓库名填 webview_app → Public → Create）
#    —— 建仓库这一步必须走网页或 gh CLI（要个人凭据），推代码用 SSH 就行。
#
# Release 资产名固定 `kmlab-toolbox.apk`，自动更新清单里的稳定直链依赖它：
#   https://github.com/vee2046/webview_app/releases/latest/download/kmlab-toolbox.apk
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPO="${KMLAB_GH_REPO:-vee2046/webview_app}"
SSH_URL="git@github.com:${REPO}.git"
RELEASE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --release) RELEASE=1; shift ;;
    --repo) REPO="$2"; SSH_URL="git@github.com:${REPO}.git"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

# ── 1. remote ─────────────────────────────────────────────────
if git remote get-url origin >/dev/null 2>&1; then
  echo "▸ remote origin 已经是 $(git remote get-url origin)"
else
  git remote add origin "$SSH_URL"
  echo "▸ 已添加 remote origin $SSH_URL"
fi

# ── 2. 推 main ───────────────────────────────────────────────
echo "▸ 推送 main"
git push -u origin main

# ── 3. 打 tag（触发 Actions 出包 + 发 Release）────────────────
if [ "$RELEASE" -eq 1 ]; then
  VERSION="$(grep -E '^version:' app/pubspec.yaml | head -1 | sed 's/^version:[[:space:]]*//' | tr -d ' ')"
  TAG="v${VERSION}"
  echo "▸ 打 tag $TAG 并推送（会触发 GitHub Actions 自动出包 + 发 Release）"
  git tag -f "$TAG"
  git push origin "$TAG"
  echo
  echo "✅ 已推送 $TAG"
  echo "   盯着 Actions：https://github.com/$REPO/actions"
  echo "   完成后下载地址：https://github.com/$REPO/releases/latest/download/kmlab-toolbox.apk"
fi
