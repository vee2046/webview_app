#!/usr/bin/env bash
# 出包 → 发到 GitHub Release → 更新自动更新清单。
#
#   ./scripts/publish-release.sh                        # 用默认仓库
#   ./scripts/publish-release.sh --repo owner/name      # 指定仓库
#   ./scripts/publish-release.sh --repo owner/name --notes "这版修了什么"
#
# 为什么用 GitHub Releases 托管 APK：
#   - **不会让 git 仓库膨胀**（53MB 的 APK 不进 commit 历史）
#   - 有稳定的直链：`https://github.com/<owner>/<repo>/releases/latest/download/<file>`
#     —— 清单里就写这个地址，以后每次发版都不用改清单
#   - 不用自建对象存储、不用备案域名
#
# 需要其中之一：
#   ① `gh` CLI 且已登录（brew install gh && gh auth login）
#   ② 环境变量 GITHUB_TOKEN（PAT，勾 repo 权限）
#   ③ 仓库里配了 .github/workflows/release.yml —— push 一个 tag 就会自动出包+发 Release
#
# 产物：kmlab_site/public/data/update.json（清单，url 指向 releases/latest/download）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPO="${KMLAB_GH_REPO:-vee2046/webview_app}"
NOTES=""
SKIP_BUILD=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)  REPO="$2"; shift 2 ;;
    --notes) NOTES="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

# ── 1. 出包 ────────────────────────────────────────────────────
if [ "$SKIP_BUILD" -eq 0 ]; then
  echo "▸ 出包"
  ./scripts/build-android.sh
fi

APK="$(ls -t "$ROOT"/kmlab-toolbox-v*.apk 2>/dev/null | head -1 || true)"
if [ -z "$APK" ] || [ ! -f "$APK" ]; then
  echo "❌ 找不到 APK（先跑 ./scripts/build-android.sh）" >&2
  exit 1
fi
BASENAME="$(basename "$APK")"
VERSION="$(grep -E '^version:' app/pubspec.yaml | head -1 | sed 's/^version:[[:space:]]*//' | tr -d ' ')"
VER_NAME="${VERSION%%+*}"
VER_CODE="${VERSION##*+}"
TAG="v${VERSION}"

# Releases 里的资产名固定（清单里的 URL 依赖它）
ASSET="kmlab-toolbox.apk"

echo
echo "▸ 仓库：$REPO   版本：$VER_NAME ($VER_CODE)   tag：$TAG"

# ── 2. 发 Release ─────────────────────────────────────────────
release_created=0

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "▸ 用 gh CLI 发 Release"
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "$APK" --repo "$REPO" --clobber
  else
    gh release create "$TAG" "$APK" --repo "$REPO" \
      --title "kmlab Toolbox $VER_NAME" \
      --notes "${NOTES:-kmlab Toolbox $VER_NAME（versionCode $VER_CODE）}"
  fi
  release_created=1
elif [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "▸ 用 GITHUB_TOKEN 发 Release（API）"
  API="https://api.github.com/repos/$REPO"
  # release 已存在就复用，否则先建
  if ! curl -sf -H "Authorization: token $GITHUB_TOKEN" "$API/releases/tags/$TAG" >/dev/null; then
    python3 - "$NOTES" "$VER_NAME" "$VER_CODE" "$TAG" << 'PYEOF' > /tmp/km_release.json
import io, json, sys
notes, ver, code, tag = sys.argv[1:5]
body = {"tag_name": tag, "name": "kmlab Toolbox " + ver,
        "body": notes or ("kmlab Toolbox " + ver + "（versionCode " + code + "）"),
        "draft": False, "prerelease": False}
io.open('/tmp/km_release.json', 'w', encoding='utf-8').write(json.dumps(body, ensure_ascii=False))
PYEOF
    curl -sf -X POST -H "Authorization: token $GITHUB_TOKEN" \
      -H "Content-Type: application/json" \
      -d @/tmp/km_release.json "$API/releases" >/dev/null
  fi
  UPLOAD_URL=$(curl -sf -H "Authorization: token $GITHUB_TOKEN" "$API/releases/tags/$TAG" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['upload_url'].split('{')[0])")
  curl -sf -X POST -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$APK" "$UPLOAD_URL?name=$ASSET" >/dev/null
  release_created=1
else
  echo "⚠️ 没有 gh CLI 也没有 GITHUB_TOKEN —— 跳过上传"
  echo "   两种走法："
  echo "   a) brew install gh && gh auth login   然后重跑本脚本"
  echo "   b) 在仓库里放 .github/workflows/release.yml，push tag '$TAG' 让 GitHub Actions 自动出包发版"
fi

# ── 3. 更新自动更新清单 ────────────────────────────────────────
DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/$ASSET"

echo
echo "▸ 更新清单（$DOWNLOAD_URL）"
./scripts/publish-update.sh --url "$DOWNLOAD_URL" --note "${NOTES:-}" >/dev/null

echo
if [ "$release_created" -eq 1 ]; then
  echo "✅ 完成"
  echo "   APK 下载地址：$DOWNLOAD_URL"
  echo "   ⚠️ 还要提交并部署 kmlab_site（清单在 public/data/update.json）"
else
  echo "⚠️ 清单已更新，但 Release 还没发 —— 手工上传："
  echo "   把 $BASENAME 作为附件传到 https://github.com/$REPO/releases/tag/$TAG"
  echo "   资产名必须是 $ASSET（清单里的 URL 依赖它）"
fi
