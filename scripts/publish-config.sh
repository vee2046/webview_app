#!/usr/bin/env bash
# 把唯一真相源 config/app.config.json 同步到各份副本。
#
#   1. app/assets/app.config.json        随 App 打包的内置快照（离线兜底 / 首屏）
#   2. kmlab_site/public/data/app.json   远端配置（运营改这份，不用发版）
#   3. app/android/.../res/values/strings.xml  Android 桌面标签（配置即契约）
#
# generatedAt 的规矩：
#   - 只在「配置内容真的变了」时才盖，没变就不动（免得逼人重复部署）
#   - 取 max(当前 UTC 时间, 上一版 + 1 秒)，保证单调递增
#     （否则会出现「新配置比线上还旧 → 被 App 的新鲜度保护拒绝」的坑）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SRC="config/app.config.json"
BUILTIN="app/assets/app.config.json"
KMLAB_SITE_DIR="${KMLAB_SITE_DIR:-../kmlab_site}"
REMOTE="$KMLAB_SITE_DIR/public/data/app.json"
STRINGS="app/android/app/src/main/res/values/strings.xml"

[ -f "$SRC" ] || { echo "❌ 找不到唯一真相源 $SRC"; exit 1; }

echo "▸ 唯一真相源：$SRC"

# ---------- 1. 比较内容（剥掉 generatedAt 再比） ----------
strip_ts() {
  python3 - "$1" << 'PYEOF'
import json, sys, io
d = json.load(io.open(sys.argv[1], encoding='utf-8'))
d.pop('generatedAt', None)
print(json.dumps(d, sort_keys=True, ensure_ascii=False))
PYEOF
}

CHANGED=1
if [ -f "$BUILTIN" ] && [ -f "$REMOTE" ]; then
  if [ "$(strip_ts "$SRC")" = "$(strip_ts "$BUILTIN")" ] && \
     [ "$(strip_ts "$SRC")" = "$(strip_ts "$REMOTE")" ]; then
    CHANGED=0
  fi
fi

# ---------- 2. 盖 generatedAt（只在变了时，且单调递增） ----------
NEXT=""
if [ "$CHANGED" = "1" ]; then
  NEXT="$(python3 - "$SRC" "$BUILTIN" "$REMOTE" << 'PYEOF'
import json, io, sys, datetime

def read_ts(p):
    try:
        return json.load(io.open(p, encoding='utf-8')).get('generatedAt')
    except Exception:
        return None

def parse(s):
    if not s:
        return None
    try:
        return datetime.datetime.fromisoformat(s.replace('Z', '+00:00'))
    except Exception:
        return None

now = datetime.datetime.now(datetime.timezone.utc)
prev = [parse(read_ts(p)) for p in sys.argv[1:]]
prev = [p for p in prev if p is not None]
cand = now
if prev:
    latest = max(prev)
    cand = max(now, latest + datetime.timedelta(seconds=1))
print(cand.strftime('%Y-%m-%dT%H:%M:%SZ'))
PYEOF
)"
  echo "▸ 配置有变化 → generatedAt 更新为 $NEXT"
else
  echo "▸ 配置内容未变 → generatedAt 保持不动"
fi

python3 - "$SRC" "$NEXT" << 'PYEOF'
import json, io, sys, collections
src, ts = sys.argv[1], sys.argv[2]
with io.open(src, encoding='utf-8') as f:
    d = json.load(f, object_pairs_hook=collections.OrderedDict)
if ts:
    d['generatedAt'] = ts
with io.open(src, 'w', encoding='utf-8') as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
    f.write('\n')
PYEOF

# ---------- 3. 同步副本 ----------
mkdir -p "$(dirname "$BUILTIN")"
cp "$SRC" "$BUILTIN"
echo "▸ 已同步 $BUILTIN"

if [ -d "$KMLAB_SITE_DIR" ]; then
  mkdir -p "$(dirname "$REMOTE")"
  cp "$SRC" "$REMOTE"
  echo "▸ 已同步 $REMOTE"
else
  echo "⚠️ 找不到 $KMLAB_SITE_DIR，跳过远端发布（可用 KMLAB_SITE_DIR 指定）"
fi

# ---------- 4. Android 桌面标签 ----------
APP_NAME="$(python3 -c "import json,io;print(json.load(io.open('$SRC',encoding='utf-8'))['app']['appName'])")"
mkdir -p "$(dirname "$STRINGS")"
cat > "$STRINGS" << EOF
<?xml version="1.0" encoding="utf-8"?>
<!-- 由 scripts/publish-config.sh 依据 config/app.config.json 的 app.appName 生成，请勿手改 -->
<resources>
    <string name="app_name">$APP_NAME</string>
</resources>
EOF
echo "▸ 已生成 $STRINGS（app_name = $APP_NAME）"

# ---------- 5. 自检 ----------
python3 - "$SRC" << 'PYEOF'
import json, io, sys
d = json.load(io.open(sys.argv[1], encoding='utf-8'))
assert d['schemaVersion'] == 1, 'schemaVersion 必须为 1'
assert d.get('generatedAt'), '缺 generatedAt'
assert d['app'].get('appName'), '缺 app.appName'
assert d.get('tools'), 'tools 为空'
print(f"✅ 自检通过：schemaVersion=1 · generatedAt={d['generatedAt']} · tools={len(d['tools'])} 个 · appName={d['app']['appName']}")
PYEOF

echo
echo "三份副本 md5："
md5 -q "$SRC" "$BUILTIN" 2>/dev/null
[ -f "$REMOTE" ] && md5 -q "$REMOTE" || true
