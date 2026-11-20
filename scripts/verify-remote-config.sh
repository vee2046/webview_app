#!/usr/bin/env bash
# 自查线上远端配置是否已上线且与本地一致。
#
# 检查项：
#   1. HTTP 状态 200
#   2. content-type 是 JSON（防 SPA 把不存在的路径兜底成 index.html）
#   3. 线上 md5 == 本地三份副本的 md5
#   4. generatedAt / schemaVersion / tools 数量
#   5. 打卡助手的续接卡算法是不是最新的那个
#
# 退出码 0 = 全绿；非 0 = 有问题。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SRC="config/app.config.json"
BUILTIN="app/assets/app.config.json"
KMLAB_SITE_DIR="${KMLAB_SITE_DIR:-../kmlab_site}"
REMOTE="$KMLAB_SITE_DIR/public/data/app.json"

URL="$(python3 -c "import json,io;print(json.load(io.open('$SRC',encoding='utf-8'))['remote']['configUrl'])")"

rc=0
say() { printf '%s\n' "$*"; }
ok()  { say "✅ $*"; }
bad() { say "❌ $*"; rc=1; }

say "远端配置：$URL"
say "────────────────────────────────────────"

# 1 + 2. 状态码与 content-type
HEADERS="$(curl -sS -D - -o /tmp/_km_remote_cfg.json --max-time 20 "$URL" 2>&1 || true)"
STATUS="$(printf '%s' "$HEADERS" | head -1 | awk '{print $2}')"
CTYPE="$(printf '%s' "$HEADERS" | grep -i '^content-type:' | head -1 | tr -d '\r' | cut -d' ' -f2-)"

[ "$STATUS" = "200" ] && ok "HTTP 状态 200" || bad "HTTP 状态 ${STATUS:-无响应}"
case "$CTYPE" in
  *json*) ok "content-type = $CTYPE" ;;
  *) bad "content-type = ${CTYPE:-无} —— 静态托管 SPA 会把不存在的路径兜底成 index.html，远端配置根本没上线" ;;
esac

if [ ! -s /tmp/_km_remote_cfg.json ]; then
  bad "远端响应为空"
  echo; echo "❌ 远端配置有问题"
  exit 1
fi

# 3. md5 三方比对
LOCAL_MD5="$(md5 -q "$SRC")"
REMOTE_MD5="$(md5 -q /tmp/_km_remote_cfg.json)"
MD5_OK=0
[ "$LOCAL_MD5" = "$REMOTE_MD5" ] && MD5_OK=1

[ "$MD5_OK" = "1" ] && ok "线上 md5 == 本地真相源 md5（$LOCAL_MD5）" \
                    || bad "线上 md5（$REMOTE_MD5）!= 本地 md5（$LOCAL_MD5）—— 站上还没重新构建部署"

for f in "$BUILTIN" "$REMOTE"; do
  if [ -f "$f" ]; then
    m="$(md5 -q "$f")"
    [ "$m" = "$LOCAL_MD5" ] && ok "本地副本一致：$f" || bad "本地副本不一致：$f（$m）"
  else
    bad "本地副本缺失：$f"
  fi
done

# 4 + 5. 内容字段
python3 - /tmp/_km_remote_cfg.json << 'PYEOF'
import json, io, sys
rc = 0
try:
    d = json.load(io.open(sys.argv[1], encoding='utf-8'))
except Exception as e:
    print(f'❌ 远端不是合法 JSON：{e}')
    sys.exit(1)

def check(cond, good, bad):
    global rc
    print(('✅ ' if cond else '❌ ') + (good if cond else bad))
    if not cond:
        rc = 1

check(d.get('schemaVersion') == 1, f"schemaVersion = {d.get('schemaVersion')}", f"schemaVersion 应为 1，实为 {d.get('schemaVersion')}")
check(bool(d.get('generatedAt')), f"generatedAt = {d.get('generatedAt')}", '缺 generatedAt（App 会拒绝这份配置）')
tools = d.get('tools') or []
check(len(tools) > 0, f"tools = {len(tools)} 个", 'tools 为空')
check(d.get('app', {}).get('appName') == 'kmlab Toolbox',
      f"appName = {d.get('app', {}).get('appName')}",
      f"appName 应为 kmlab Toolbox，实为 {d.get('app', {}).get('appName')}")
ck = next((t for t in tools if t.get('id') == 'checkin'), None)
kind = (ck or {}).get('resume', {}).get('extract', {}).get('kind')
check(kind == 'countDateMap', f"打卡助手算法 = {kind}", f"打卡助手算法应为 countDateMap（线上是旧版），实为 {kind}")
sys.exit(rc)
PYEOF
[ $? -ne 0 ] && rc=1

echo "────────────────────────────────────────"
if [ "$rc" = "0" ] && [ "$MD5_OK" = "1" ]; then
  echo "✅ 远端配置已上线且与本地一致"
else
  echo "❌ 远端配置有问题（若刚改了配置，去 kmlab_site 跑一次 pnpm run build 并重新部署）"
fi
rm -f /tmp/_km_remote_cfg.json
exit $rc
