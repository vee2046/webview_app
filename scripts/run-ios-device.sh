#!/usr/bin/env bash
# 路线 A：把自己的 iPhone 当开发机跑这个 App（**不需要付费开发者账号**）。
#
# 用普通 Apple ID 签出来的包 **7 天后会失效**，重跑一次本脚本即可续命。
#
# 用法：
#   ./scripts/run-ios-device.sh              # 自动挑第一台连着的 iPhone
#   ./scripts/run-ios-device.sh <device-id>  # 指定设备
#
# 详细步骤见 docs/TESTFLIGHT.md 的「路线 A」。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "▸ 工具链体检"
"$ROOT/scripts/setup-ios.sh" || true

echo
echo "▸ 可用设备："
flutter devices 2>/dev/null | sed 's/^/  /'

DEVICE="${1:-}"
if [ -z "$DEVICE" ]; then
  # 只要**真机**：targetPlatform=ios 且 emulator=False（模拟器 emulator=True）
  DEVICE="$(cd "$ROOT/app" && flutter devices --machine 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for d in data:
    if d.get('targetPlatform') == 'ios' and not d.get('emulator', True):
        print(d.get('id', ''))
        break
")"
fi

if [ -z "$DEVICE" ]; then
  cat >&2 << 'EOF'
❌ 没找到连着的 iPhone。

请按顺序检查：
  1. 数据线插好了吗？手机屏幕上有「信任此电脑」吗？（点信任 + 输入密码）
  2. Xcode → 打开一次并登录 Apple ID（Settings → Accounts → + → Apple ID）
  3. Xcode → Runner 项目 → Signing & Capabilities → Team 选你的 Apple ID
     → Bundle Identifier 改成一个全球唯一的（默认 tech.kmlab.kmlabToolbox 也可以用）
  4. 再跑一次本脚本

完整步骤见 docs/TESTFLIGHT.md「路线 A」。
EOF
  exit 1
fi

echo
echo "▸ 开始在设备 $DEVICE 上运行（首次会编译 1~3 分钟）"
cd "$ROOT/app"
exec flutter run -d "$DEVICE" "$@"
