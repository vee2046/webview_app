#!/usr/bin/env bash
# kmlab Toolbox · Android 一键出包
#
#   ./scripts/build-android.sh                 # 静态检查 + 单元测试 + release APK
#   ./scripts/build-android.sh --debug         # 静态检查 + 单元测试 + debug APK
#   ./scripts/build-android.sh --install       # 上面 + 装到已连接的设备并启动
#   ./scripts/build-android.sh --skip-tests    # 跳过单元测试（赶时间时）
#
# 产物：app/build/app/outputs/flutter-apk/app-{release,debug}.apk
#
# ⚠️ 当前 release 包用的是 **debug key** 签名（android/app/build.gradle 里
#    signingConfig = signingConfigs.getByName("debug")）—— 侧载够用，但上架
#    Google Play 前必须换成自建 keystore。
#
# ℹ️ iOS / macOS 的出包脚本已随「只做 Android」的决策暂缓，见 docs/DESIGN.md D15。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$ROOT/scripts/$(basename "${BASH_SOURCE[0]}")"
cd "$ROOT/app"

MODE="release"
INSTALL=0
SKIP_TESTS=0

for arg in "$@"; do
  case "$arg" in
    --debug)       MODE="debug" ;;
    --release)     MODE="release" ;;
    --install)     INSTALL=1 ;;
    --skip-tests)  SKIP_TESTS=1 ;;
    -h|--help)     sed -n '2,16p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$arg（用 --help 看用法）" >&2; exit 2 ;;
  esac
done

# ── 版本号自动递增 ──────────────────────────────────────────────
# 每次出包都必须让版本号变，否则手机会当成「同一个版本」→ 装不上 / 还是旧包，
# 看起来就像「改了没效果」（踩过：版本号一直卡在 0.1.0+1，连出好几个包）。
#   versionName  x.y.z   → patch 位 +1（0.1.0 → 0.1.1）
#   versionCode  +N      → +1（Android 覆盖升级必须严格递增）
# 同时重新生成 app/lib/version.dart，让 App 里的「关于」显示真实包版本。
echo "▸ 0/4 递增版本号"
python3 - "$ROOT" << 'PYVER'
import io, re, sys
root = sys.argv[1]
p = root + '/app/pubspec.yaml'
t = io.open(p, encoding='utf-8').read()
m = re.search(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$', t, re.M)
if not m:
    raise SystemExit('❌ pubspec.yaml 里找不到 version: x.y.z+N')
ma, mi, pa, bn = (int(x) for x in m.groups())
pa += 1
bn += 1
new = '%d.%d.%d+%d' % (ma, mi, pa, bn)
t = t[:m.start()] + 'version: ' + new + t[m.end():]
io.open(p, 'w', encoding='utf-8').write(t)

label = '%d.%d.%d (%d)' % (ma, mi, pa, bn)
lib = root + '/app/lib/version.dart'
content = '''// ⚠️ 本文件由 `scripts/build-android.sh` **自动生成**，请勿手改。
//
// 每次出包前脚本会：
//   1. 递增 `app/pubspec.yaml` 的 version（`x.y.z+N` → patch 位 +1、build 号 +1）
//      —— Android 的 versionCode / versionName 与 iOS 的 CFBundleVersion /
//         CFBundleShortVersionString 都来自这里，所以**版本号一变，安装包就能覆盖升级**。
//   2. 重新生成本文件。
//
// 为什么要自动递增：之前版本号一直卡在 0.1.0+1，连着出好几个包，
// 装到手机上系统会当成「同一个版本」→ 装不上 / 还是旧包 → 看起来像「改了没效果」。
library;

/// 版本名（用户可见），如 `0.1.1`。
const String kAppVersion = '%d.%d.%d';

/// 构建号（Android versionCode / iOS CFBundleVersion），每次出包 +1。
const int kAppBuild = %d;

/// 完整标签（用户可见），如 `0.1.1 (2)`。
const String kAppVersionLabel = '$kAppVersion ($kAppBuild)';
''' % (ma, mi, pa, bn)
# ⚠️ 内容先算好再写文件 —— io.open(p,'w') 会**先截断**，格式化抛错就把文件清空了（踩过）
io.open(lib, 'w', encoding='utf-8').write(content)
print('   版本号 → %s' % label)
PYVER

echo
echo "▸ 1/4 静态检查（flutter analyze）"
flutter analyze

if [ "$SKIP_TESTS" -eq 0 ]; then
  echo
  echo "▸ 2/4 单元测试（flutter test）"
  flutter test
else
  echo
  echo "▸ 2/4 单元测试（已跳过）"
fi

echo
echo "▸ 3/4 构建 $MODE APK（flutter build apk --$MODE）"
flutter build apk --"$MODE"

APK="$ROOT/app/build/app/outputs/flutter-apk/app-$MODE.apk"
SIZE="$(du -h "$APK" | cut -f1 | tr -d ' ')"
echo
echo "✅ 产物：$APK（$SIZE）"

# ── 拷一份到项目根目录 ──────────────────────────────────────────
# build/ 目录里的路径又长又深，容易看错（还可能看到上一次的旧文件）。
# 所以根目录再放一份**带版本号**的名字，一眼就知道是哪个版本。
PUB_VERSION="$(grep -E '^version:' "$ROOT/app/pubspec.yaml" | head -1 | sed 's/^version:[[:space:]]*//' | tr -d ' ')"
ROOT_APK="$ROOT/kmlab-toolbox-v${PUB_VERSION}.apk"
find "$ROOT" -maxdepth 1 -name 'kmlab-toolbox-v*.apk' ! -name "$(basename "$ROOT_APK")" -delete
cp "$APK" "$ROOT_APK"
echo "✅ 项目根目录也放了一份：$(basename "$ROOT_APK")" 

if [ "$INSTALL" -eq 1 ]; then
  echo
  echo "▸ 安装到已连接设备"
  if ! command -v adb >/dev/null 2>&1; then
    echo "❌ 找不到 adb（Android SDK platform-tools 不在 PATH 里）" >&2
    exit 1
  fi
  DEVICES="$(adb devices | sed '1d' | grep -c 'device$' || true)"
  if [ "$DEVICES" -lt 1 ]; then
    echo "❌ 没有已连接的设备（adb devices 里没有 device 状态的行）" >&2
    exit 1
  fi
  adb install -r "$APK"
  adb shell am start -n tech.kmlab.kmlab_toolbox/.MainActivity
  echo "✅ 已启动（包名 tech.kmlab.kmlab_toolbox）"
fi
