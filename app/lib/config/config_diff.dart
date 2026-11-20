/// 配置差异 —— 让远端热更「可审」。
///
/// 背景（DESIGN.md §4.4）：远端配置可以在 App 不发版的情况下被运营改掉。
/// 这件事本身很方便，但**不方便的是「改了什么看不见」** —— 用户遇到行为变化时
/// 只会觉得「App 是不是坏了」，运营也复现不了「线上到底是哪一版」。
///
/// 所以远端配置替换生效前，先算出一份**人类可读的差异清单**，在「我的 → 配置」
/// 里摊开，并在一键刷新后弹出来。
///
/// 差异算在 **JSON 层**（`AppConfig.toJson()`），不是模型层 ——
/// 这样「模型层压根没读的那个字段」也会被抓出来（这正是 BUG #23 那一族）。
library;

import '../model/app_config.dart';

/// 配置变更类型（Dart 不允许类内声明 enum，只能顶层）。
enum ConfigChangeKind { added, removed, changed }

/// 一处配置变化。
class ConfigChange {
  const ConfigChange({
    required this.path,
    required this.kind,
    this.before,
    this.after,
  });

  /// 例如 `tools[checkin].resume.extract.kind`
  final String path;

  final ConfigChangeKind kind;
  final Object? before;
  final Object? after;

  String get kindLabel => switch (kind) {
        ConfigChangeKind.added => '新增',
        ConfigChangeKind.removed => '删除',
        ConfigChangeKind.changed => '修改',
      };

  /// 人类可读的一行，例如：
  /// `修改  tools[checkin].resume.extract.kind：count → countDateMap`
  String describe() {
    final b = formatValue(before);
    final a = formatValue(after);
    return switch (kind) {
      ConfigChangeKind.added => '新增  $path：$a',
      ConfigChangeKind.removed => '删除  $path：$b',
      ConfigChangeKind.changed => '修改  $path：$b → $a',
    };
  }

  /// 把值渲染成短而可读的样子。
  static String formatValue(Object? v) {
    if (v == null) return '（无）';
    if (v is bool) return v ? '是' : '否';
    if (v is num) return v.toString();
    if (v is String) {
      if (v.isEmpty) return '（空）';
      return v.length <= 40 ? v : '${v.substring(0, 40)}…';
    }
    if (v is List) {
      if (v.isEmpty) return '[]';
      final head = v.take(3).map(formatValue).join(', ');
      return v.length <= 3 ? '[$head]' : '[$head, …共 ${v.length} 项]';
    }
    if (v is Map) {
      if (v.isEmpty) return '{}';
      return '{${v.length} 项}';
    }
    return v.toString();
  }

  @override
  String toString() => describe();
}

/// 配置差异计算器。
class ConfigDiff {
  const ConfigDiff._();

  /// 比较两份配置的**全部 JSON 字段**，返回变化清单（空列表 = 完全一致）。
  ///
  /// 列表按 `id` 对齐（`tools` / `tabs` / `bottomNav` 都有 `id`），
  /// 这样「调换顺序」不会变成 N 条无意义的修改，而「改标题」只会有一条。
  static List<ConfigChange> between(AppConfig before, AppConfig after) {
    return diffMaps(before.toJson(), after.toJson(), '');
  }

  /// 给 [changes] 生成一句总结。
  static String summarize(List<ConfigChange> changes) {
    if (changes.isEmpty) return '配置没有变化';
    final added = changes.where((c) => c.kind == ConfigChangeKind.added).length;
    final removed = changes.where((c) => c.kind == ConfigChangeKind.removed).length;
    final changed =
        changes.where((c) => c.kind == ConfigChangeKind.changed).length;
    final parts = <String>[
      if (changed > 0) '修改 $changed 处',
      if (added > 0) '新增 $added 处',
      if (removed > 0) '删除 $removed 处',
    ];
    return parts.join(' · ');
  }

  /// 两份 JSON 树的差异。
  static List<ConfigChange> diffMaps(Map<String, dynamic> a, Map<String, dynamic> b,
      String prefix) {
    final out = <ConfigChange>[];
    final keys = <String>{...a.keys, ...b.keys}.toList()..sort();

    for (final key in keys) {
      final path = prefix.isEmpty ? key : '$prefix.$key';
      final va = a[key];
      final vb = b[key];

      if (!a.containsKey(key)) {
        out.add(ConfigChange(path: path, kind: ConfigChangeKind.added, after: vb));
        continue;
      }
      if (!b.containsKey(key)) {
        out.add(ConfigChange(
            path: path, kind: ConfigChangeKind.removed, before: va));
        continue;
      }

      // ⚠️ 用 `is Map` 而不是 `is Map<String, dynamic>` —— 空 Map 字面量 `{}`
      // 的静态类型是 Map<dynamic, dynamic>，用后者判断会漏掉。
      if (va is Map && vb is Map) {
        out.addAll(diffMaps(
          Map<String, dynamic>.from(va),
          Map<String, dynamic>.from(vb),
          path,
        ));
        continue;
      }

      if (va is List && vb is List) {
        out.addAll(_diffLists(va, vb, path));
        continue;
      }

      if (!_deepEquals(va, vb)) {
        out.add(ConfigChange(
            path: path, kind: ConfigChangeKind.changed, before: va, after: vb));
      }
    }
    return out;
  }

  /// 列表差异：优先按 `id` 对齐，退化到按索引。
  static List<ConfigChange> _diffLists(List<dynamic> a, List<dynamic> b,
      String path) {
    final out = <ConfigChange>[];

    final aIds = _idsOf(a);
    final bIds = _idsOf(b);
    if (aIds != null && bIds != null) {
      // 按 id 对齐
      final bById = <String, dynamic>{for (final e in b) e['id'] as String: e};
      final aById = <String, dynamic>{for (final e in a) e['id'] as String: e};

      for (final id in aIds) {
        final itemPath = '$path[$id]';
        if (!bById.containsKey(id)) {
          out.add(ConfigChange(
              path: itemPath, kind: ConfigChangeKind.removed, before: aById[id]));
        } else {
          out.addAll(_diffItem(aById[id], bById[id], itemPath));
        }
      }
      for (final id in bIds) {
        if (!aById.containsKey(id)) {
          out.add(ConfigChange(
              path: '$path[$id]', kind: ConfigChangeKind.added, after: bById[id]));
        }
      }
      return out;
    }

    // 按索引
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final itemPath = '$path[$i]';
      if (i >= b.length) {
        out.add(ConfigChange(
            path: itemPath, kind: ConfigChangeKind.removed, before: a[i]));
      } else if (i >= a.length) {
        out.add(ConfigChange(
            path: itemPath, kind: ConfigChangeKind.added, after: b[i]));
      } else {
        out.addAll(_diffItem(a[i], b[i], itemPath));
      }
    }
    return out;
  }

  /// 单个列表元素的差异。
  static List<ConfigChange> _diffItem(
      dynamic a, dynamic b, String path) {
    if (a is Map && b is Map) {
      return diffMaps(
        Map<String, dynamic>.from(a),
        Map<String, dynamic>.from(b),
        path,
      );
    }
    if (a is List && b is List) {
      return _diffLists(a, b, path);
    }
    if (!_deepEquals(a, b)) {
      return [
        ConfigChange(
            path: path, kind: ConfigChangeKind.changed, before: a, after: b)
      ];
    }
    return const [];
  }

  /// 若列表里每项都是带 `id` 的 Map，返回 id 列表，否则返回 null。
  static List<String>? _idsOf(List<dynamic> list) {
    if (list.isEmpty) return const <String>[];
    final ids = <String>[];
    for (final e in list) {
      if (e is Map<String, dynamic> && e['id'] is String) {
        ids.add(e['id'] as String);
      } else {
        return null;
      }
    }
    return ids;
  }

  /// 深比较（List / Map 递归）。
  static bool _deepEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k)) return false;
        if (!_deepEquals(a[k], b[k])) return false;
      }
      return true;
    }
    return a == b;
  }
}
