#!/usr/bin/env bash
# 生成**自动更新清单** kmlab_site/public/data/update.json
#
#   ./scripts/publish-update.sh                      # 用默认下载地址
#   ./scripts/publish-update.sh --url <下载直链>     # 指定 APK 的下载地址
#   ./scripts/publish-update.sh --note "这版修了什么"
#
# 清单长这样（App 的 lib/data/update_checker.dart 读它）：
#   { "versionCode": 9, "versionName": "0.1.8", "url": "...apk", "size": 55653964, ... }
#
# ⚠️ **APK 本体不由这个脚本托管** —— 清单里的 url 指向哪里由发布方决定
#    （站点静态目录 / 对象存储 / 网盘直链都行）。
#    App 只负责「查清单 → 比版本号 → 提示 → 下载 → 拉起安装」。
#
# ⚠️ 清单里的 versionCode 必须**大于**用户机器上的 —— App 拿本机的
#    `version.dart` 里的 kAppBuild 来比（那个值跟安装包里的 versionCode 一致）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

URL=""
NOTE=""
APK=""

while [ $# -gt 0 ]; do
  case "$1" in
    --url)  URL="$2"; shift 2 ;;
    --note) NOTE="$2"; shift 2 ;;
    --apk)  APK="$2"; shift 2 ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

# 最新的根目录 APK
if [ -z "$APK" ]; then
  APK="$(ls -t "$ROOT"/kmlab-toolbox-v*.apk 2>/dev/null | head -1 || true)"
fi
if [ -z "$APK" ] || [ ! -f "$APK" ]; then
  echo "❌ 找不到 APK（先跑 ./scripts/build-android.sh）" >&2
  exit 1
fi

VERSION="$(grep -E '^version:' app/pubspec.yaml | head -1 | sed 's/^version:[[:space:]]*//' | tr -d ' ')"
VER_NAME="${VERSION%%+*}"
VER_CODE="${VERSION##*+}"
SIZE="$(stat -f%z "$APK" 2>/dev/null || stat -c%s "$APK")"
BASENAME="$(basename "$APK")"

# 默认下载地址：GitHub Releases 的稳定直链（每次发版都覆盖同一个 URL）
if [ -z "$URL" ]; then
  URL="https://github.com/${KMLAB_GH_REPO:-vee2046/webview_app}/releases/latest/download/kmlab-toolbox.apk"
fi

OUT="$ROOT/../kmlab_site/public/data/update.json"
mkdir -p "$(dirname "$OUT")"

python3 - "$OUT" "$VER_CODE" "$VER_NAME" "$URL" "$SIZE" "$NOTE" "$BASENAME" << 'PYEOF'
import io, json, sys, datetime
out, code, name, url, size, note, basename = sys.argv[1:8]
data = {
    'versionCode': int(code),
    'versionName': name,
    'url': url,
    'size': int(size),
    'note': note,
    'publishedAt': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'fileName': basename,
}
io.open(out, 'w', encoding='utf-8').write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
print('✅ 已生成 %s' % out)
print('   versionCode=%s  versionName=%s  size=%.1fMB' % (code, name, int(size)/1024/1024))
print('   url=%s' % url)
PYEOF

echo
echo "⚠️ 还没做的事："
echo "   1) 把 APK 放到 url 指向的位置（现在是 $URL）"
echo "   2) 提交并部署 kmlab_site —— 否则线上读不到这份清单"
