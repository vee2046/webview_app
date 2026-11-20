#!/usr/bin/env bash
# 给远端配置签名 —— 让 `remote.requireSignature` 这个开关真的有用。
#
# 签名算法：HMAC-SHA256(密钥, 规范化JSON)，十六进制小写。
# 规范化 JSON：键按字典序排序、无多余空白、排除 `signature` 字段本身。
#
# ⚠️ 规范化规则必须与 App 侧 `app/lib/config/config_signature.dart`
#    的 `canonicalJson()` **逐字节一致**，否则签名对不上。
#    `app/test/config_signature_test.dart` 会拿真实配置文件互相验证。
#
# 用法：
#   ./scripts/sign-config.sh              # 给 config/app.config.json 签名（就地写入）
#   ./scripts/sign-config.sh --check      # 只校验签名是否正确，不改文件
#   ./scripts/sign-config.sh --print      # 打印签名（不写文件）

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${ROOT}/config/app.config.json"

# 与 App 侧 kmlabConfigSecret 保持一致
SECRET="${KMLAB_CONFIG_SECRET:-kmlab-h5-config-2026-v1}"

MODE="sign"
case "${1:-}" in
  --check) MODE="check" ;;
  --print) MODE="print" ;;
  "") ;;
  *) echo "未知参数：$1（可用：--check / --print）" >&2; exit 2 ;;
esac

if [ ! -f "$TARGET" ]; then
  echo "❌ 找不到配置文件：$TARGET" >&2
  exit 1
fi

RESULT="$(python3 - "$TARGET" "$SECRET" "$MODE" << 'PYEOF'
import json, hmac, hashlib, sys, collections

path, secret, mode = sys.argv[1], sys.argv[2], sys.argv[3]

with open(path, encoding='utf-8') as f:
    cfg = json.load(f, object_pairs_hook=collections.OrderedDict)

def canonical(v):
    """与 Dart 侧 canonicalJson() 逐字节一致。"""
    if v is None:
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        # 配置里不该有小数；真出现了就取整（与 Dart 侧 toStringAsFixed(0) 对齐）
        return format(v, '.0f')
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, (list, tuple)):
        return '[' + ','.join(canonical(x) for x in v) + ']'
    if isinstance(v, dict):
        keys = sorted(v.keys())
        return '{' + ','.join(
            json.dumps(k, ensure_ascii=False) + ':' + canonical(v[k])
            for k in keys) + '}'
    raise TypeError('不支持的类型: %r' % type(v))

body = {k: v for k, v in cfg.items() if k != 'signature'}
message = canonical(body).encode('utf-8')
sig = hmac.new(secret.encode('utf-8'), message, hashlib.sha256).hexdigest()

old = cfg.get('signature')
if mode == 'print':
    print(sig)
    sys.exit(0)

if mode == 'check':
    if old == sig:
        print('✅ 签名正确：%s' % sig)
        sys.exit(0)
    print('❌ 签名不匹配')
    print('   文件里的：%s' % (old or '（缺失）'))
    print('   算出来的：%s' % sig)
    sys.exit(1)

# sign：写回文件（保留缩进与中文，末尾换行）
cfg['signature'] = sig
with open(path, 'w', encoding='utf-8') as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
    f.write('\n')
print('✅ 已签名：%s' % sig)
PYEOF
)"

echo "$RESULT"

if [ "$MODE" = "sign" ]; then
  # 签名会改文件 → 三份副本需要重新同步
  echo "→ 现在请跑 ./scripts/publish-config.sh 把签名后的配置同步到副本"
fi
