/// 本机使用记录 —— 最近时间线 + 常用置顶。
///
/// 只存本机，不上传服务器（与 kmlab_site 的「数据保存在本机」一致）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UsageRecord {
  const UsageRecord({
    required this.toolId,
    required this.at,
    this.summary,
  });

  final String toolId;
  final DateTime at;

  /// 最近一次退出工具时抓到的状态摘要快照
  final String? summary;

  Map<String, dynamic> toJson() => {
        'toolId': toolId,
        'at': at.millisecondsSinceEpoch,
        if (summary != null) 'summary': summary,
      };

  static UsageRecord? fromJson(Map<String, dynamic> json) {
    final id = json['toolId'] as String?;
    final at = json['at'];
    if (id == null || at is! num) return null;
    return UsageRecord(
      toolId: id,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      summary: json['summary'] as String?,
    );
  }
}

class UsageStore extends ChangeNotifier {
  static const String _historyKey = 'km.usage.history';
  static const String _pinnedKey = 'km.usage.pinned';
  static const String _snapshotPrefix = 'km.snapshot.';

  final List<UsageRecord> _history = [];
  final List<String> _pinned = [];

  /// 已访问过的工具的 localStorage 快照（由 WebView 取回）
  final Map<String, Map<String, dynamic>> _snapshots = {};

  List<UsageRecord> get history => List.unmodifiable(_history);
  List<String> get pinned => List.unmodifiable(_pinned);

  /// 已有快照的工具 id（App 级导出 / 清除用）
  List<String> get snapshotIds => _snapshots.keys.toList()..sort();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final rawHistory = prefs.getString(_historyKey);
    if (rawHistory != null) {
      try {
        final list = jsonDecode(rawHistory);
        if (list is List) {
          _history
            ..clear()
            ..addAll(list
                .whereType<Map<String, dynamic>>()
                .map(UsageRecord.fromJson)
                .whereType<UsageRecord>());
          _history.sort((a, b) => b.at.compareTo(a.at));
        }
      } catch (e) {
        debugPrint('[UsageStore] 读取历史失败: $e');
      }
    }

    final rawPinned = prefs.getString(_pinnedKey);
    if (rawPinned != null) {
      try {
        final list = jsonDecode(rawPinned);
        if (list is List) {
          _pinned
            ..clear()
            ..addAll(list.whereType<String>());
        }
      } catch (e) {
        debugPrint('[UsageStore] 读取置顶失败: $e');
      }
    }

    // localStorage 快照也要读回来 —— 否则重启后续接卡全是「还没开始」
    await loadSnapshots();
  }

  /// 记录一次打开
  Future<void> recordOpen(String toolId, {String? summary}) async {
    _history.removeWhere((r) => r.toolId == toolId);
    _history.insert(0, UsageRecord(
      toolId: toolId,
      at: DateTime.now(),
      summary: summary,
    ));
    if (_history.length > 60) {
      _history.removeRange(60, _history.length);
    }
    await _persistHistory();
    notifyListeners();
  }

  /// 更新某工具最近一次的摘要
  Future<void> updateSummary(String toolId, String summary) async {
    final idx = _history.indexWhere((r) => r.toolId == toolId);
    if (idx < 0) return;
    _history[idx] = UsageRecord(
      toolId: _history[idx].toolId,
      at: _history[idx].at,
      summary: summary,
    );
    await _persistHistory();
    notifyListeners();
  }

  Future<void> togglePin(String toolId) async {
    if (_pinned.contains(toolId)) {
      _pinned.remove(toolId);
    } else {
      _pinned.add(toolId);
    }
    await _persistPinned();
    notifyListeners();
  }

  bool isPinned(String toolId) => _pinned.contains(toolId);

  /// 最近使用的工具 id，按最近优先
  List<String> get recentToolIds {
    final seen = <String>{};
    final out = <String>[];
    for (final r in _history) {
      if (seen.add(r.toolId)) out.add(r.toolId);
    }
    return out;
  }

  UsageRecord? recordOf(String toolId) {
    for (final r in _history) {
      if (r.toolId == toolId) return r;
    }
    return null;
  }

  /// 今天打开过几个工具
  int get todayCount {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _history
        .where((r) =>
            r.at.isAfter(today) &&
            r.at.isBefore(today.add(const Duration(days: 1))))
        .map((r) => r.toolId)
        .toSet()
        .length;
  }

  /// 连续使用天数
  int get streakDays {
    if (_history.isEmpty) return 0;
    final days = _history
        .map((r) => DateTime(r.at.year, r.at.month, r.at.day))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (days.first.difference(today).inDays > 1) return 0;
    if (days.first.difference(today).inDays == 1) return 1;

    var streak = 1;
    for (var i = 1; i < days.length; i++) {
      if (days[i - 1].difference(days[i]).inDays == 1) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  /// 时间线分组 —— 默认 今天 / 昨天 / 本周 / 更早
  Map<String, List<UsageRecord>> timelineByGroups(List<String> groups) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekStart = today.subtract(const Duration(days: 6));

    final buckets = <String, List<UsageRecord>>{
      for (final g in groups) g: <UsageRecord>[],
    };

    for (final r in _history) {
      final day = DateTime(r.at.year, r.at.month, r.at.day);
      final String group;
      if (day == today) {
        group = '今天';
      } else if (day == yesterday) {
        group = '昨天';
      } else if (!day.isBefore(weekStart)) {
        group = '本周';
      } else {
        group = '更早';
      }
      if (buckets.containsKey(group)) {
        buckets[group]!.add(r);
      }
    }
    return buckets;
  }

  // ── localStorage 快照 ──────────────────────────────────────

  /// 存下某个工具的 localStorage 快照（由 WebView 取回）
  Future<void> saveSnapshot(String toolId, Map<String, dynamic> snapshot) async {
    _snapshots[toolId] = snapshot;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_snapshotPrefix$toolId',
      jsonEncode(snapshot),
    );
    notifyListeners();
  }

  Map<String, dynamic>? snapshotOf(String toolId) => _snapshots[toolId];

  Future<void> loadSnapshots() async {
    final prefs = await SharedPreferences.getInstance();
    for (final rawKey in prefs.getKeys()) {
      // Android 的 shared_preferences 会给 key 加 `flutter.` 前缀，取回来时不一定剥掉
      final key = rawKey.startsWith('flutter.') ? rawKey.substring(8) : rawKey;
      if (!key.startsWith(_snapshotPrefix)) continue;
      final toolId = key.substring(_snapshotPrefix.length);
      final raw = prefs.getString('$_snapshotPrefix$toolId');
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _snapshots[toolId] = decoded;
        }
      } catch (_) {
        // 快照坏了就当没有，不影响其它工具
      }
    }
  }

  /// 清除某工具的快照（配合「清除数据」）
  Future<void> clearSnapshot(String toolId) async {
    _snapshots.remove(toolId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_snapshotPrefix$toolId');
    notifyListeners();
  }

  // ── App 级数据管理（导出全部 / 导入 / 清除全部） ─────────────

  /// 打成一份可导出的包：全部工具快照 + 使用记录 + 置顶。
  Map<String, dynamic> exportPayload() {
    return {
      'tools': {
        for (final e in _snapshots.entries)
          e.key: Map<String, dynamic>.from(e.value),
      },
      'usage': {
        'history': _history.map((e) => e.toJson()).toList(),
        'pinned': List<String>.from(_pinned),
      },
    };
  }

  /// 导入一份包。
  ///
  /// - [replaceAll] = true：先清掉本地全部快照，再写导入的（完全覆盖）
  /// - [replaceAll] = false：mergeByKey —— 导入的 key 覆盖同名，本地独有的保留
  ///
  /// 使用记录按 toolId 去重，取时间较新的一条；置顶取并集。
  Future<void> importPayload(
    Map<String, dynamic> payload, {
    bool replaceAll = false,
  }) async {
    if (replaceAll) _snapshots.clear();

    final tools = payload['tools'];
    if (tools is Map) {
      for (final entry in tools.entries) {
        final v = entry.value;
        if (v is! Map) continue;
        final toolId = entry.key.toString();
        final merged = Map<String, dynamic>.from(
          _snapshots[toolId] ?? const <String, dynamic>{},
        );
        merged.addAll(Map<String, dynamic>.from(v));
        _snapshots[toolId] = merged;
      }
    }

    final usage = payload['usage'];
    if (usage is Map) {
      final hist = usage['history'];
      if (hist is List) {
        for (final raw in hist) {
          if (raw is! Map) continue;
          final record = UsageRecord.fromJson(Map<String, dynamic>.from(raw));
          if (record == null) continue;
          final idx = _history.indexWhere((e) => e.toolId == record.toolId);
          if (idx < 0) {
            _history.add(record);
          } else if (_history[idx].at.isBefore(record.at)) {
            _history[idx] = record;
          }
        }
        _history.sort((a, b) => b.at.compareTo(a.at));
        if (_history.length > 60) _history.removeRange(60, _history.length);
      }
      final pin = usage['pinned'];
      if (pin is List) {
        for (final p in pin) {
          final s = p.toString();
          if (!_pinned.contains(s)) _pinned.add(s);
        }
      }
    }

    await _persistAll();
    notifyListeners();
  }

  /// 清除这台设备上的全部本地数据（使用记录 + 置顶 + 所有快照）。
  Future<void> clearAllData() async {
    _history.clear();
    _pinned.clear();
    _snapshots.clear();

    final prefs = await SharedPreferences.getInstance();
    for (final rawKey in prefs.getKeys()) {
      final key = rawKey.startsWith('flutter.') ? rawKey.substring(8) : rawKey;
      if (key.startsWith(_snapshotPrefix) ||
          key == _historyKey ||
          key == _pinnedKey) {
        await prefs.remove(key);
      }
    }
    notifyListeners();
  }

  Future<void> _persistAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final rawKey in prefs.getKeys()) {
      final key = rawKey.startsWith('flutter.') ? rawKey.substring(8) : rawKey;
      if (key.startsWith(_snapshotPrefix)) await prefs.remove(key);
    }
    for (final e in _snapshots.entries) {
      await prefs.setString('$_snapshotPrefix${e.key}', jsonEncode(e.value));
    }
    await _persistHistory();
    await _persistPinned();
  }

  // ── 持久化 ────────────────────────────────────────────────

  Future<void> _persistHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(_history.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _persistPinned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinnedKey, jsonEncode(_pinned));
  }
}
