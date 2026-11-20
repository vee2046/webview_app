#!/usr/bin/env bash
# 从 SVG 生成各平台 App 图标（依赖 ImageMagick 的 magick 命令）。
#
#   assets/icon.svg            → Android 传统 mipmap-{mdpi..xxxhdpi}/ic_launcher.png
#                                Android 自适应前景层 ic_launcher_foreground.png
#                                Android 13 单色主题图标 ic_launcher_monochrome.png
#                                Android 自适应图标描述 mipmap-anydpi-v26/ic_launcher.xml
#   assets/icon-foreground.svg → Android 自适应前景层（只有笔画，没有底色）
#                                iOS AppIcon.appiconset/（按 Contents.json 列的 filename 逐个生成）
#                                macOS AppIcon.appiconset/
#
# 关键坑（真踩过）：
#   iOS 那边不能自己发明文件名 —— 必须直接读 Contents.json，按它列的 filename 生成，
#   否则 Xcode 压根不用你生成的图（桌面图标一直是 Flutter 默认 logo）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FULL="assets/icon.svg"
FORE="assets/icon-foreground.svg"
ANDROID_RES="app/android/app/src/main/res"
IOS_ICON="app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
MAC_ICON="app/macos/Runner/Assets.xcassets/AppIcon.appiconset"

command -v magick >/dev/null 2>&1 || { echo "❌ 需要 ImageMagick（brew install imagemagick）"; exit 1; }
[ -f "$FULL" ] || { echo "❌ 缺少 $FULL"; exit 1; }

# ---------- Android 传统图标 ----------
echo "▸ Android 传统图标"
for pair in "mdpi 48" "hdpi 72" "xhdpi 96" "xxhdpi 144" "xxxhdpi 192"; do
  set -- $pair
  d="$ANDROID_RES/mipmap-$1"
  mkdir -p "$d"
  magick -background none "$FULL" -resize "${2}x${2}" "$d/ic_launcher.png"
done

# ---------- Android 自适应前景层 ----------
if [ -f "$FORE" ]; then
  echo "▸ Android 自适应前景层"
  for pair in "mdpi 108" "hdpi 162" "xhdpi 216" "xxhdpi 324" "xxxhdpi 432"; do
    set -- $pair
    d="$ANDROID_RES/mipmap-$1"
    mkdir -p "$d"
    magick -background none "$FORE" -resize "${2}x${2}" "$d/ic_launcher_foreground.png"
  done
else
  echo "⚠️ 缺少 $FORE，跳过自适应前景层"
fi

# ---------- Android 单色（Android 13 主题图标）----------
echo "▸ Android 单色图标"
for pair in "mdpi 108" "hdpi 162" "xhdpi 216" "xxhdpi 324" "xxxhdpi 432"; do
  set -- $pair
  d="$ANDROID_RES/mipmap-$1"
  mkdir -p "$d"
  magick "$FULL" -resize "${2}x${2}" -alpha extract -threshold 50% -negate -fill black -colorize 100 "$d/ic_launcher_monochrome.png"
done

# ---------- Android 自适应图标描述 ----------
mkdir -p "$ANDROID_RES/mipmap-anydpi-v26" "$ANDROID_RES/values"
cat > "$ANDROID_RES/mipmap-anydpi-v26/ic_launcher.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
EOF
cat > "$ANDROID_RES/values/colors.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#f6f1e4</color>
</resources>
EOF
echo "▸ 已生成 mipmap-anydpi-v26/ic_launcher.xml + values/colors.xml"

# ---------- iOS / macOS：严格按 Contents.json 生成 ----------
gen_apple_icons() {
  local dir="$1" src="$2"
  [ -f "$dir/Contents.json" ] || { echo "⚠️ 缺少 $dir/Contents.json，跳过"; return 0; }
  echo "▸ 生成 $dir"
  python3 - "$dir" "$src" << 'PYEOF'
import json, io, os, subprocess, sys
d, src = sys.argv[1], sys.argv[2]
meta = json.load(io.open(os.path.join(d, 'Contents.json'), encoding='utf-8'))
n = 0
for item in meta.get('images', []):
    fn = item.get('filename')
    if not fn:
        continue
    size = item.get('size', '')
    scale = item.get('scale', '1x')
    try:
        px = int(float(size.split('x')[0].split('@')[0]) * float(scale.rstrip('x')))
    except Exception:
        px = 1024
    out = os.path.join(d, fn)
    subprocess.run(['magick', '-background', 'none', src, '-resize', f'{px}x{px}', out], check=True)
    n += 1
print(f'  生成 {n} 个尺寸')
PYEOF
}

gen_apple_icons "$IOS_ICON" "$FULL"
[ -f "$MAC_ICON/Contents.json" ] && gen_apple_icons "$MAC_ICON" "$FULL"

echo
echo "✅ 图标生成完毕"
