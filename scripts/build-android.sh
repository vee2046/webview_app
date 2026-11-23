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

echo "▸ 1/3 静态检查（flutter analyze）"
flutter analyze

if [ "$SKIP_TESTS" -eq 0 ]; then
  echo
  echo "▸ 2/3 单元测试（flutter test）"
  flutter test
else
  echo
  echo "▸ 2/3 单元测试（已跳过）"
fi

echo
echo "▸ 3/3 构建 $MODE APK（flutter build apk --$MODE）"
flutter build apk --"$MODE"

APK="$ROOT/app/build/app/outputs/flutter-apk/app-$MODE.apk"
SIZE="$(du -h "$APK" | cut -f1 | tr -d ' ')"
echo
echo "✅ 产物：$APK（$SIZE）"

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
