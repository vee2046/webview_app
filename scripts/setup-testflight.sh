#!/usr/bin/env bash
# TestFlight 上架前的体检 + 手工步骤清单。
#
# 为什么必须有这个脚本：
#   上传 TestFlight 需要的不是技术，是**账号**。下面这些没法靠代码绕过：
#     · 付费 Apple Developer Program 账号（$99/年）
#     · Xcode 登录该账号 → 自动生成 Apple Distribution 证书
#     · developer.apple.com 注册 Bundle ID
#     · App Store Connect 建 App 记录（iOS 与 macOS 是两条独立记录，一次只能选一个平台）
#   所以脚本的职责是：把「能自动查的全查了」，再把「只能你手动做的」列清楚。
#
# 用法：
#   ./scripts/setup-testflight.sh            只体检
#   ./scripts/setup-testflight.sh --build    额外跑一次 flutter build macos --release
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD=0
[ "${1:-}" = "--build" ] && BUILD=1

ok()  { printf '✅ %s\n' "$*"; }
bad() { printf '❌ %s\n' "$*"; }
warn(){ printf '⚠️  %s\n' "$*"; }
info(){ printf '   %s\n' "$*"; }
step(){ printf '\n\033[1m%s\033[0m\n' "$*"; }

echo "════════════════════════════════════════"
echo " TestFlight 上架体检"
echo "════════════════════════════════════════"

# ---------- 1. Xcode 工具链 ----------
step "【1】Xcode 工具链"
if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -version | sed 's/^/   /'
  ok "Xcode 可用"
else
  bad "找不到 xcodebuild"
fi
SEL="$(xcode-select -p 2>/dev/null || echo '未设置')"
info "xcode-select → $SEL"
if [ "$SEL" = "/Applications/Xcode.app/Contents/Developer" ]; then
  ok "指向完整版 Xcode"
else
  bad "未指向完整版 Xcode —— 见 scripts/setup-ios.sh --fix"
fi
if xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  ok "iphoneos SDK 可用"
else
  bad "缺 iphoneos SDK"
fi

# ---------- 2. 代码签名身份 ----------
step "【2】代码签名身份"
IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null | grep -c 'valid identities' >/dev/null 2>&1; security find-identity -v -p codesigning 2>/dev/null | grep ')' | wc -l | tr -d ' ')"
if [ "${IDENTITIES:-0}" -gt 0 ]; then
  ok "找到 $IDENTITIES 个有效签名身份"
  security find-identity -v -p codesigning 2>/dev/null | sed 's/^/   /'
else
  bad "没有有效的代码签名身份"
  info "修法：Xcode → Settings → Accounts 登录你的 Apple Developer 账号"
  info "     登录后 Xcode 会自动生成 'Apple Distribution' 证书"
fi

# ---------- 3. App Store Connect API key（可选） ----------
step "【3】App Store Connect API key（可选）"
KEYS="$(ls "$HOME/.appstoreconnect/private_keys" 2>/dev/null | grep -c '\.p8$' || true)"
if [ "${KEYS:-0}" -gt 0 ]; then
  ok "找到 $KEYS 个 .p8 key（可用于自动化上传）"
else
  info "没有 .p8 key —— 不影响手动上传，只是不能用 transporter 脚本自动化"
  info "需要的话在 App Store Connect → 用户与访问 → 集成 → App Store Connect API 造一个"
fi

# ---------- 4. 工程配置 ----------
step "【4】工程配置"
IOS_BUNDLE="$(grep -A1 'PRODUCT_BUNDLE_IDENTIFIER' app/ios/Runner.xcodeproj/project.pbxproj 2>/dev/null | head -1 | sed 's/.*= *//;s/;//' | tr -d ' ')"
MAC_BUNDLE="$(grep 'PRODUCT_BUNDLE_IDENTIFIER' app/macos/Runner/Configs/AppInfo.xcconfig 2>/dev/null | head -1 | sed 's/.*= *//' | tr -d ' ')"
info "iOS   Bundle ID：${IOS_BUNDLE:-读不到}"
info "macOS Bundle ID：${MAC_BUNDLE:-读不到}"
[ -n "$IOS_BUNDLE" ] && ok "iOS Bundle ID 已配置" || warn "iOS Bundle ID 读不到"

DISPLAY_IOS="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' app/ios/Runner/Info.plist 2>/dev/null | sed 's/[[:space:]]*$//')"
DISPLAY_MAC="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' app/macos/Runner/Info.plist 2>/dev/null | sed 's/[[:space:]]*$//')"
info "iOS   显示名：${DISPLAY_IOS:-读不到}"
info "macOS 显示名：${DISPLAY_MAC:-读不到}"

step "【5】entitlements 关键项"
for f in app/macos/Runner/DebugProfile.entitlements app/macos/Runner/Release.entitlements; do
  [ -f "$f" ] || { bad "缺 $f"; continue; }
  ok "$(basename "$f")"
  grep -q 'com.apple.security.app-sandbox' "$f" && ok "  app-sandbox（macOS 上架必需）" || bad "  缺 app-sandbox"
  grep -q 'com.apple.security.network.client' "$f" && ok "  network.client（不加 WebView 白屏）" || bad "  缺 network.client"
  grep -q 'com.apple.security.files.user-selected.read-write' "$f" && ok "  files.user-selected.read-write（导入数据要用）" || warn "  缺 files.user-selected.read-write"
done

step "【6】版本号"
VER="$(grep -E '^version:' app/pubspec.yaml | sed 's/^version: *//' | tr -d ' ')"
NAME_VER="${VER%%+*}"
BUILD_NUM="${VER##*+}"
info "version = $NAME_VER（build $BUILD_NUM）"
if [ "$BUILD_NUM" = "1" ]; then
  warn "build 号还是 1 —— 上架前建议改（pubspec.yaml 的 version: x.y.z+N）"
fi

# ---------- 出包 ----------
if [ "$BUILD" = "1" ]; then
  step "【7】构建 macOS release（ad-hoc 签名，只能本机跑，不能上传）"
  (cd app && flutter build macos --release) && ok "macOS release 包已出" || bad "构建失败"
fi

# ---------- 手工步骤 ----------
cat << 'EOF'

════════════════════════════════════════
 只能你手动做的 6 步
════════════════════════════════════════

 1. 买 Apple Developer Program（$99/年）
      https://developer.apple.com/programs/

 2. Xcode → Settings → Accounts → 登录该账号
      登录后 Xcode 自动生成「Apple Distribution」证书

 3. developer.apple.com → Certificates, IDs & Profiles → Identifiers
      注册 Bundle ID：tech.kmlab.kmlabToolbox
      （iOS 与 macOS 是两条独立记录，各注册各的）

 4. App Store Connect → My Apps → + → New App
      ⚠️ 一次只能选一个平台 —— iOS 和 macOS 要各建一条 App 记录
      填好名称、SKU、Primary Language

 5. Xcode → Product → Archive
      （不要用 flutter build ipa —— 上传必须走 Xcode 的 Archive 流程）

 6. Xcode → Organizer → Distribute App → App Store Connect → Upload
      上传完等 10~30 分钟，TestFlight 里就能看到

 附：macOS 版本同理，但要走「Mac Catalyst」之外的原生 macOS 目标，
    沙箱权限（network.client / files.user-selected.read-write）要在后台单独申请。
EOF
