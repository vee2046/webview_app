#!/usr/bin/env bash
# iOS 工具链体检 + 修复引导。
#
# 真踩过的坑（本脚本就是为它们写的）：
#   1. 装了 Xcode，但系统没选中它 —— `xcode-select -p` 还指着 CommandLineTools，
#      而 CommandLineTools 里只有 macOS SDK，**没有 iPhoneSimulator SDK**
#      → Flutter 的 native-assets hook 报 `Target build_hooks failed`（Bad state: No element）
#   2. 设 `DEVELOPER_DIR` 是治标不治本 —— Xcode 内部 build script 以 xcode-select 为准
#   3. CocoaPods 不是必需的 —— Flutter 3.47 默认走 Swift Package Manager
#   4. github.com 主站不通，但 codeload.github.com 通
#
# 用法：
#   ./scripts/setup-ios.sh          只体检
#   ./scripts/setup-ios.sh --fix    体检 + 尝试自动修（需要输系统密码）
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIX=0
[ "${1:-}" = "--fix" ] && FIX=1

ok()  { printf '✅ %s\n' "$*"; }
bad() { printf '❌ %s\n' "$*"; }
warn(){ printf '⚠️  %s\n' "$*"; }
info(){ printf '   %s\n' "$*"; }

echo "════════════════════════════════════════"
echo " iOS 工具链体检"
echo "════════════════════════════════════════"

# ---------- 1. Xcode ----------
echo
echo "【1】Xcode"
if ! command -v xcodebuild >/dev/null 2>&1; then
  bad "找不到 xcodebuild —— 装 Xcode：https://developer.apple.com/xcode/"
elif ! xcodebuild -version >/dev/null 2>&1; then
  bad "xcodebuild 存在但跑不起来（常见于只装了 CommandLineTools）"
else
  xcodebuild -version | sed 's/^/   /'
  ok "Xcode 可用"
fi

# ---------- 2. xcode-select ----------
echo
echo "【2】xcode-select 指向"
SEL="$(xcode-select -p 2>/dev/null || echo '未设置')"
info "当前：$SEL"
if [ "$SEL" = "/Applications/Xcode.app/Contents/Developer" ]; then
  ok "已指向完整版 Xcode"
else
  bad "没指向完整版 Xcode"
  info "CommandLineTools 里没有 iPhoneSimulator SDK → Flutter 会报 Target build_hooks failed"
  if [ "$FIX" = "1" ]; then
    if [ -d "/Applications/Xcode.app" ]; then
      info "准备弹系统密码框执行 sudo xcode-select -s …"
      if osascript -e 'do shell script "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" with administrator privileges' 2>/dev/null; then
        ok "已修复：$(xcode-select -p)"
      else
        bad "自动修复失败，请手动执行："
        info "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
      fi
    else
      bad "/Applications/Xcode.app 不存在"
    fi
  else
    info "手动执行：sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  fi
fi

# ---------- 3. SDK ----------
echo
echo "【3】iOS SDK"
if SDK="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null)"; then
  ok "iphonesimulator SDK：$SDK"
else
  bad "找不到 iphonesimulator SDK（多半是第 2 步没修好）"
fi
if SDK2="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)"; then
  ok "iphoneos SDK：$SDK2"
else
  bad "找不到 iphoneos SDK"
fi

# ---------- 4. 模拟器 runtime ----------
echo
echo "【4】模拟器 runtime"
if command -v xcrun >/dev/null 2>&1; then
  RT="$(xcrun simctl list runtimes 2>/dev/null | grep -i 'iOS' | head -3)"
  if [ -n "$RT" ]; then
    ok "可用 runtime："
    printf '%s\n' "$RT" | sed 's/^/     /'
  else
    warn "没装 iOS 模拟器 runtime（Xcode → Settings → Components 里下载）"
  fi
fi

# ---------- 5. Flutter iOS 引擎产物 ----------
echo
echo "【5】Flutter iOS 引擎产物"
FLUTTER_ROOT="$(cd "$(dirname "$(command -v flutter)")/.." && pwd)"
if [ -d "$FLUTTER_ROOT/bin/cache/artifacts/engine/ios" ]; then
  ok "iOS 引擎产物已就绪"
else
  warn "缺 iOS 引擎产物，跑一次 flutter precache --ios"
fi

# ---------- 6. CocoaPods（非必需） ----------
echo
echo "【6】CocoaPods"
if command -v pod >/dev/null 2>&1; then
  ok "已安装（但 Flutter 3.47 默认走 SPM，不一定用得上）"
else
  info "未安装 —— Flutter 3.47 默认走 Swift Package Manager，不需要它"
  info "（真要装：brew install cocoapods，注意系统 Ruby 版本可能太老）"
fi

echo
echo "════════════════════════════════════════"
echo " 出包命令"
echo "════════════════════════════════════════"
echo "   # 模拟器 debug 包（不需要签名）"
echo "   cd app && flutter build ios --simulator --debug"
echo
echo "   # 真机 / TestFlight 需要 Xcode Archive 流程，见 scripts/setup-testflight.sh"
echo
echo "   # 跑模拟器"
echo "   cd app && flutter run -d <device-id>"
echo "   xcrun simctl list devices available"
echo
echo "   # 提示：simctl install 偶尔会挂死，重试即可"
