/// 远端配置签名 —— 纯 Dart 实现 HMAC-SHA256，不引入任何第三方依赖。
///
/// 目的（DESIGN.md §4.4）：让 `remote.requireSignature` 这个开关**真的有用**。
/// 在此之前它只是配置里的一行字：模型读了、UI 显示了、但没有任何代码校验过它。
///
/// 威胁模型（诚实版）：
///   ✅ 防：CDN / 静态托管被误改、被劫持、运营手滑发布了没签名的文件
///   ✅ 防：中间人替换响应体（HTTPS 证书被绕过时）
///   ❌ 不防：定向逆向 —— 密钥编译进了 App 包，能被提取
///   ❌ 不防：能改 App 的人本来就能改行为
///
/// 真要做到「防定向逆向」，得用非对称签名（服务端私钥签、App 内置公钥验），
/// 那是 M4 之后的事（§4.4 签名方案演进）。
///
/// 签名内容 = **规范化 JSON**（键排序、无空白、排除 `signature` 字段本身）。
/// 服务端脚本 `scripts/sign-config.sh` 用同一套规范化规则算签名。
library;

import 'dart:convert';

/// 远端配置签名用的共享密钥。
///
/// ⚠️ 这个值会编译进 App 二进制 —— 见文件头的威胁模型说明。
/// 它防的是「配置链路被改」，不是「App 被逆」。
const String kmlabConfigSecret = 'kmlab-h5-config-2026-v1';

/// 配置里携带签名的字段名。
const String configSignatureField = 'signature';

class ConfigSignature {
  const ConfigSignature._();

  /// 给配置算签名（自动排除 `signature` 字段本身）。
  static String sign(Map<String, dynamic> config, {String secret = kmlabConfigSecret}) {
    return hmacSha256Hex(secret, canonicalJson(_withoutSignature(config)));
  }

  /// 校验配置签名。签名缺失或对不上都返回 false。
  static bool verify(Map<String, dynamic> config,
      {String secret = kmlabConfigSecret}) {
    final given = config['signature']; // 字面量：契约测试要能扫到这个字段
    if (given is! String || given.isEmpty) return false;
    final expect = sign(config, secret: secret);
    return _constantTimeEquals(expect, given);
  }

  /// 从配置里取出签名（没有就 null）。
  static String? signatureOf(Map<String, dynamic> config) {
    final v = config['signature'];
    return v is String && v.isNotEmpty ? v : null;
  }

  /// 去掉 `signature` 字段。
  static Map<String, dynamic> _withoutSignature(Map<String, dynamic> config) {
    final out = Map<String, dynamic>.from(config);
    out.remove('signature');
    return out;
  }

  /// 规范化 JSON：键按字典序排序、无多余空白。
  ///
  /// 必须与 `scripts/sign-config.sh`（python 侧）**逐字节一致**，否则签名对不上。
  /// 规则：
  ///   - 对象：键排序后 `{"k":v,...}`
  ///   - 数组：保持原顺序 `[v,...]`
  ///   - 字符串：`"..."`（转义与 JSON 一致）
  ///   - 整数：`123`
  ///   - 布尔 / null：`true` / `false` / `null`
  ///   - 浮点：统一用 `toStringAsFixed(0)`？—— **不支持**，配置里禁止出现小数
  static String canonicalJson(Object? value) {
    final sb = StringBuffer();
    _writeCanonical(value, sb);
    return sb.toString();
  }

  static void _writeCanonical(Object? value, StringBuffer sb) {
    if (value == null) {
      sb.write('null');
    } else if (value is bool) {
      sb.write(value ? 'true' : 'false');
    } else if (value is int) {
      sb.write(value.toString());
    } else if (value is double) {
      // 配置里不该有小数；真出现了就取整（与服务端保持一致）
      sb.write(value.toStringAsFixed(0));
    } else if (value is String) {
      sb.write(jsonEncode(value));
    } else if (value is List) {
      sb.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) sb.write(',');
        _writeCanonical(value[i], sb);
      }
      sb.write(']');
    } else if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      sb.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) sb.write(',');
        sb.write(jsonEncode(keys[i]));
        sb.write(':');
        _writeCanonical(value[keys[i]], sb);
      }
      sb.write('}');
    } else {
      sb.write(jsonEncode(value.toString()));
    }
  }

  /// HMAC-SHA256（十六进制小写），密钥按 UTF-8 编码。
  static String hmacSha256Hex(String secret, String message) {
    return hmacSha256HexBytes(utf8.encode(secret), message);
  }

  /// HMAC-SHA256（十六进制小写），密钥是**原始字节**。
  ///
  /// 为什么要单独开一个：RFC 4231 的测试向量用的密钥是二进制（0xaa / 0x0b…），
  /// 走 `String.fromCharCodes` 会被当成 Latin-1 码点，UTF-8 编码后字节数变了，
  /// 向量就验不过。
  static String hmacSha256HexBytes(List<int> keyBytes, String message) {
    return hmacSha256Raw(keyBytes, utf8.encode(message));
  }

  /// HMAC-SHA256 的**原始字节**版本（密钥与消息都是字节）。
  ///
  /// RFC 4231 的测试向量里密钥和消息都是二进制，用 `String.fromCharCodes`
  /// 会被当 Latin-1 码点、UTF-8 编码后字节数翻倍，向量就验不过。
  static String hmacSha256Raw(List<int> keyBytes, List<int> msg) {
    const blockSize = 64;

    List<int> k = List<int>.from(keyBytes);
    if (k.length > blockSize) {
      k = sha256Bytes(k);
    }
    final padded = List<int>.filled(blockSize, 0);
    for (var i = 0; i < k.length; i++) {
      padded[i] = k[i];
    }

    final oKey = List<int>.generate(blockSize, (i) => padded[i] ^ 0x5c);
    final iKey = List<int>.generate(blockSize, (i) => padded[i] ^ 0x36);

    final inner = sha256Bytes([...iKey, ...msg]);
    final outer = sha256Bytes([...oKey, ...inner]);
    return _toHex(outer);
  }

  /// SHA-256（返回 32 字节）。
  static List<int> sha256Bytes(List<int> input) {
    const k = <int>[
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, //
      0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
      0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
      0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
      0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
      0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
      0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
      0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
      0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];

    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;

    final msgLen = input.length;
    final bitLen = msgLen * 8;
    final padded = <int>[...input, 0x80];
    while (padded.length % 64 != 56) {
      padded.add(0);
    }
    // 长度按 64 位大端追加（本实现只处理低 48 位，足够用）
    for (var i = 7; i >= 0; i--) {
      padded.add((bitLen >> (i * 8)) & 0xff);
    }

    final w = List<int>.filled(64, 0);

    for (var chunk = 0; chunk < padded.length; chunk += 64) {
      for (var i = 0; i < 16; i++) {
        final j = chunk + i * 4;
        w[i] = (padded[j] << 24) |
            (padded[j + 1] << 16) |
            (padded[j + 2] << 8) |
            padded[j + 3];
      }
      for (var i = 16; i < 64; i++) {
        final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;
      var f = h5;
      var g = h6;
      var hh = h7;

      for (var i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xffffffff) & g);
        final temp1 = (hh + s1 + ch + k[i] + w[i]) & 0xffffffff;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;

        hh = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + hh) & 0xffffffff;
    }

    return [
      (h0 >> 24) & 0xff,
      (h0 >> 16) & 0xff,
      (h0 >> 8) & 0xff,
      h0 & 0xff,
      (h1 >> 24) & 0xff,
      (h1 >> 16) & 0xff,
      (h1 >> 8) & 0xff,
      h1 & 0xff,
      (h2 >> 24) & 0xff,
      (h2 >> 16) & 0xff,
      (h2 >> 8) & 0xff,
      h2 & 0xff,
      (h3 >> 24) & 0xff,
      (h3 >> 16) & 0xff,
      (h3 >> 8) & 0xff,
      h3 & 0xff,
      (h4 >> 24) & 0xff,
      (h4 >> 16) & 0xff,
      (h4 >> 8) & 0xff,
      h4 & 0xff,
      (h5 >> 24) & 0xff,
      (h5 >> 16) & 0xff,
      (h5 >> 8) & 0xff,
      h5 & 0xff,
      (h6 >> 24) & 0xff,
      (h6 >> 16) & 0xff,
      (h6 >> 8) & 0xff,
      h6 & 0xff,
      (h7 >> 24) & 0xff,
      (h7 >> 16) & 0xff,
      (h7 >> 8) & 0xff,
      h7 & 0xff,
    ];
  }

  /// 32 位右循环移位。
  static int _rotr(int x, int n) {
    final v = x & 0xffffffff;
    return ((v >> n) | (v << (32 - n))) & 0xffffffff;
  }

  static String _toHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write((b & 0xff).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// 定长比较，避免通过比较耗时侧信道泄漏信息。
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
