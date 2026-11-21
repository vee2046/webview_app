/// 设备分桶 —— 灰度发布的基础设施。
///
/// 灰度要「稳定」：同一台设备每次启动都必须落在同一个桶里，
/// 否则今天在灰度组、明天在稳定组，用户会看到两种行为，运营也没法复现。
///
/// 做法：首次启动生成一个随机 UUID 存进 SharedPreferences，
/// 之后每次用 `uuid.hashCode % 100` 分桶 —— 纯本地计算，不联网、不上报。
library;

import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceBucket {
  const DeviceBucket._();

  static const String _deviceIdKey = 'km.device.id';

  /// 分桶总数（0 ~ 99）。
  static const int buckets = 100;

  /// 取本机分桶号（0 ~ 99）。读不到设备 ID 时返回 0（= 永远落在稳定组）。
  static Future<int> bucket() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_deviceIdKey);
      if (id == null || id.isEmpty) {
        id = _newId();
        await prefs.setString(_deviceIdKey, id);
      }
      return bucketFor(id);
    } catch (_) {
      return 0;
    }
  }

  /// 给定设备 ID 算分桶（纯函数，好测）。
  ///
  /// ⚠️ 不用 `String.hashCode` —— Dart 只保证「同一版本内一致」，
  /// 跨 Dart 版本可能变。灰度要求「同一台设备永远同一个桶」，
  /// 所以自己实现 FNV-1a（32 位），结果永远一致。
  static int bucketFor(String deviceId) {
    if (deviceId.isEmpty) return 0;
    var hash = 0x811c9dc5; // FNV offset basis
    for (final c in deviceId.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xffffffff; // FNV prime
    }
    // ⚠️ 光有 FNV-1a 还不够：它的雪崩集中在低位，取模 100 正好只用低位，
    // 实测 200 个 ID 只覆盖 47~76 个桶（严重不均）。
    // 补一步 murmur3 的 fmix32 终混合（高位也搅匀），再用乘高位映射缩放到 0~99。
    hash ^= hash >>> 16;
    hash = (hash * 0x85ebca6b) & 0xffffffff;
    hash ^= hash >>> 13;
    hash = (hash * 0xc2b2ae35) & 0xffffffff;
    hash ^= hash >>> 16;
    return (hash * buckets) >>> 32;
  }

  /// 随机设备 ID（不依赖任何设备信息，纯随机）。
  static String _newId() {
    final rnd = Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < 4; i++) {
      buf.write(rnd.nextInt(0x10000).toRadixString(16).padLeft(4, '0'));
    }
    return buf.toString();
  }

  /// 判断本机是否落在灰度组。
  ///
  /// 规则：`bucket < rolloutPercent` → 灰度组。
  /// ⚠️ `rolloutPercent` 取自**稳定版配置**（决定「拉哪个地址」的那份），
  /// 不能取自灰度版 —— 否则不在灰度组的设备永远看不到它，也就永远升不到 100%。
  static bool isInCanary(int bucket, int rolloutPercent) {
    if (rolloutPercent <= 0) return false;
    if (rolloutPercent >= buckets) return true;
    return bucket < rolloutPercent;
  }
}
