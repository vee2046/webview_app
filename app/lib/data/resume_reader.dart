/// 续接卡摘要引擎 —— 按 `resume.extract` 规格从 localStorage 快照算出状态摘要。
///
/// 关键约束（实测结论）：**App 的 Dart 侧读不到 WebView 内的 localStorage**，
/// 它活在 WebView 沙箱里。所以真实流程是：
///
///   打开工具 → WebView 里 `JSON.stringify(localStorage)` → 取回 Dart 侧缓存
///   → 退出工具时用缓存算摘要 → 写进「最近」页
///
/// 副作用：**没访问过的工具没有摘要**，显示「还没开始」而不是编一个。
///
/// 算法与占位符见 `docs/STORAGE_KEYS.md`。
library;

import 'dart:convert';

import '../model/app_config.dart';

class ResumeSummary {
  const ResumeSummary({
    required this.text,
    required this.available,
    this.detail,
  });

  /// 展示文本；`available == false` 时是「还没开始」之类的占位
  final String text;

  /// 是否真的算出了数据（false = 没有快照 / 没数据）
  final bool available;

  /// 额外信息，比如「今天 3 / 8 杯」
  final String? detail;
}

class ResumeReader {
  ResumeReader();

  /// 根据工具配置与快照算出摘要。
  ResumeSummary summarize(ToolConfig tool, Map<String, dynamic>? snapshot) {
    final resume = tool.resume;

    if (!resume.enabled || resume.mode == ResumeMode.none) {
      return const ResumeSummary(text: '', available: false);
    }

    if (resume.mode == ResumeMode.bridge) {
      // 脑力慢养：结构复杂，App 读不懂 → 等 P3 的 Bridge 上报
      final reported = _bridgeReported;
      if (reported != null) {
        return ResumeSummary(text: reported, available: true);
      }
      return ResumeSummary(text: resume.summary, available: false);
    }

    if (snapshot == null || snapshot.isEmpty) {
      return ResumeSummary(text: '还没开始', available: false);
    }

    final extract = resume.extract;
    switch (extract.kind) {
      case ExtractKind.none:
        return ResumeSummary(text: resume.summary, available: false);

      case ExtractKind.count:
        return _countSummary(resume, extract, snapshot);

      case ExtractKind.countDateMap:
        return _countDateMapSummary(resume, extract, snapshot);

      case ExtractKind.countToday:
        return _countTodaySummary(resume, extract, snapshot);

      case ExtractKind.field:
        return _fieldSummary(resume, extract, snapshot);

      case ExtractKind.lastGame:
        return _lastGameSummary(resume, extract, snapshot);
    }
  }

  /// Bridge 上报的摘要（由 KM.setResumeState 写入）
  String? _bridgeReported;

  /// 由 KM Bridge 回调写入
  set bridgeReported(String? value) => _bridgeReported = value;

  // ── count：数数组长度 ─────────────────────────────────────

  ResumeSummary _countSummary(
    ResumeConfig resume,
    ExtractConfig extract,
    Map<String, dynamic> snapshot,
  ) {
    final key = extract.key;
    if (key == null) {
      return ResumeSummary(text: resume.summary, available: false);
    }

    // localStorage 的值一律是字符串 → 先解一层 JSON
    final root = maybeDecode(snapshot[key]);
    if (root == null) {
      return ResumeSummary(text: '还没开始', available: false);
    }

    // `path` 是 **key 里那个值内部** 的点路径（如 `medicine_tracker_v1` → `meds`）
    final Object? target;
    if (extract.path == null) {
      target = root;
    } else if (root is Map<String, dynamic>) {
      target = resolvePath(root, extract.path!);
    } else {
      target = null;
    }

    final list = target is List ? target : null;

    if (list == null) {
      return ResumeSummary(text: '还没开始', available: false);
    }

    final n = list.length;
    if (n == 0) {
      return ResumeSummary(text: '还没有记录', available: false);
    }

    final unit = extract.unit ?? '';
    final template = extract.template ?? '{n}';
    final text = template
        .replaceAll('{n}', '$n')
        .replaceAll('{v}', '$n')
        .replaceAll('{unit}', unit);
    return ResumeSummary(text: text, available: true);
  }

  // ── countDateMap：按日期分组的对象里数「今天」的条数 ──────
  //
  // 打卡助手的真实结构（实测）：
  //   `{"2026-11-19":[{"t":"in","time":"08:38:21"}, ...], "2026-11-18":[...]}`

  ResumeSummary _countDateMapSummary(
    ResumeConfig resume,
    ExtractConfig extract,
    Map<String, dynamic> snapshot,
  ) {
    final key = extract.key;
    if (key == null) {
      return ResumeSummary(text: resume.summary, available: false);
    }

    final decoded = maybeDecode(snapshot[key]);
    if (decoded is! Map) {
      return ResumeSummary(text: '还没开始', available: false);
    }

    final unit = extract.unit ?? '次';
    final now = DateTime.now();
    final todayValue = decoded[dateKey(now)];
    final list = todayValue is List ? todayValue : null;

    if (list == null) {
      // 今天没有，但历史上有 → 告诉用户「今天还没打卡，但一共打过多少次」
      final total = _countAll(decoded);
      if (total > 0) {
        return ResumeSummary(
          text: '今天还没打卡 · 累计 $total $unit',
          available: false,
          detail: '累计 $total $unit',
        );
      }
      return ResumeSummary(text: '还没开始', available: false);
    }

    final n = list.length;
    if (n == 0) {
      return ResumeSummary(text: '今天还没打卡', available: false);
    }

    final template = extract.template ?? '今天 {n} {unit}打卡';
    final text = template
        .replaceAll('{n}', '$n')
        .replaceAll('{v}', '$n')
        .replaceAll('{unit}', unit);
    return ResumeSummary(text: text, available: true, detail: '$n $unit');
  }

  // ── lastGame：脑力慢养的「上一局」─────────────────────────
  //
  // 脑力慢养把「今天还没打完的那一局」存在 `bf_progress`：
  //   `{"gameId":"B","level":2,"qIndex":0,"score":82,"startedAt":1764...}`
  //
  // 两个要点：
  //  1. H5 自己会清理过期数据（不是今天就 removeItem）⇒ **key 还在就一定是今天那局**
  //  2. 各游戏的分数字段不一样（有的 `score`，有的只有 `moves`）
  //     ⇒ 分数 / 步数两级降级，再不行就只报游戏名
  //
  // 游戏代码 → 中文名的映射放在配置 `extract.names` 里 ——
  // **H5 的知识放配置，App 不硬编码**。

  ResumeSummary _lastGameSummary(
    ResumeConfig resume,
    ExtractConfig extract,
    Map<String, dynamic> snapshot,
  ) {
    final key = extract.key;
    if (key == null) {
      return ResumeSummary(text: resume.summary, available: false);
    }

    final root = maybeDecode(snapshot[key]);
    if (root is! Map<String, dynamic>) {
      return ResumeSummary(text: resume.summary, available: false);
    }

    final gameId = (root[extract.gameField ?? 'gameId'] ?? '').toString();
    if (gameId.isEmpty) {
      return ResumeSummary(text: resume.summary, available: false);
    }
    final game = extract.names?[gameId] ?? gameId;

    final level = _asInt(root[extract.levelField ?? 'level']);
    final score = _asInt(root[extract.scoreField ?? 'score']);
    final moves = _asInt(root[extract.movesField ?? 'moves']);

    final unit = extract.unit ?? '';
    String text;
    if (score != null) {
      text = _render(extract.template ?? '{n}', game, score, unit, level);
    } else if (moves != null) {
      text = _render(extract.templateMoves ?? '{n}', game, moves, unit, level);
    } else {
      text = _render(extract.templateFallback ?? game, game, 0, unit, level);
    }

    // 副标题：优先「游戏名 · 第 N 关」，其次「游戏名 · N 分」，最后只有游戏名
    String? detail;
    if (level != null) {
      detail = '$game · 第 $level 关';
    } else if (score != null) {
      detail = '$game · $score $unit'.trim();
    } else {
      detail = game;
    }

    return ResumeSummary(text: text, available: true, detail: detail);
  }

  /// 模板渲染：支持 `{game}` `{n}` `{unit}` `{level}`
  static String _render(
    String template,
    String game,
    int n,
    String unit,
    int? level,
  ) {
    return template
        .replaceAll('{game}', game)
        .replaceAll('{n}', '$n')
        .replaceAll('{v}', '$n')
        .replaceAll('{unit}', unit)
        .replaceAll('{level}', level?.toString() ?? '');
  }

  /// 数字解析：`42` 和 `'42'` 都认（localStorage 里什么类型都可能）
  static int? _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  /// 把「按日期分组的对象」里所有日期的记录数加起来
  static int _countAll(Map<Object?, Object?> map) {
    var total = 0;
    for (final v in map.values) {
      if (v is List) total += v.length;
    }
    return total;
  }

  /// `DateTime` → `YYYY-MM-DD`（localStorage 里日期键的格式）
  static String dateKey(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  // ── countToday：数今天的记录 ──────────────────────────────

  ResumeSummary _countTodaySummary(
    ResumeConfig resume,
    ExtractConfig extract,
    Map<String, dynamic> snapshot,
  ) {
    final key = extract.key;
    if (key == null) {
      return ResumeSummary(text: resume.summary, available: false);
    }

    final raw = maybeDecode(snapshot[key]);
    if (raw is! List) {
      return ResumeSummary(text: '还没开始', available: false);
    }

    final dateField = extract.dateField ?? 'timestamp';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    var count = 0;
    for (final item in raw) {
      if (item is! Map) continue;
      final ts = item[dateField];
      final dt = parseTimestamp(ts);
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      if (day == today) count++;
    }

    if (count == 0) {
      return ResumeSummary(text: '今天还没记录', available: false);
    }

    // 目标值
    String? goal;
    if (extract.goalKey != null) {
      final g = snapshot[extract.goalKey!];
      if (g is num) {
        goal = g.toInt().toString();
      } else if (g is String) {
        goal = g;
      }
    }

    final unit = extract.unit ?? '';
    final template = extract.template ?? '今天 {n} {unit}';
    final text = template
        .replaceAll('{n}', '$count')
        .replaceAll('{v}', '$count')
        .replaceAll('{goal}', goal ?? '?')
        .replaceAll('{unit}', unit);

    return ResumeSummary(
      text: text,
      available: true,
      detail: goal != null ? '$count / $goal $unit' : null,
    );
  }

  // ── field：读某个字段 ─────────────────────────────────────

  ResumeSummary _fieldSummary(
    ResumeConfig resume,
    ExtractConfig extract,
    Map<String, dynamic> snapshot,
  ) {
    final key = extract.key;
    if (key == null) {
      return ResumeSummary(text: resume.summary, available: false);
    }
    final value = maybeDecode(snapshot[key] ?? resolvePath(snapshot, key));
    if (value == null) {
      return ResumeSummary(text: '还没开始', available: false);
    }
    final template = extract.template ?? '{v}';
    final text = template
        .replaceAll('{v}', '$value')
        .replaceAll('{n}', '$value')
        .replaceAll('{unit}', extract.unit ?? '');
    return ResumeSummary(text: text, available: true);
  }

  // ── 工具方法 ─────────────────────────────────────────────

  /// **localStorage 的值一律是字符串**，App 取回快照后要先试着解一层 JSON。
  ///
  /// 实测：`flutter.km.snapshot.checkin` =
  /// `{"checkin_records":"{\"2026-11-19\":[{\"t\":\"in\",...}]}"}`
  /// —— 值是「JSON 字符串套 JSON 字符串」，不解就会当成普通字符串丢掉。
  ///
  /// 规则：只有首字符是 `{` 或 `[` 才尝试解析；解析失败原样返回。
  static Object? maybeDecode(Object? value) {
    if (value is! String) return value;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final first = trimmed[0];
    if (first != '{' && first != '[') return value;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return value;
    }
  }

  /// 点路径取值：`meds` / `a.b.c`；数组用数字下标
  static Object? resolvePath(Map<String, dynamic> root, String path) {
    Object? current = root;
    for (final segment in path.split('.')) {
      if (current is Map<String, dynamic>) {
        current = current[segment];
      } else if (current is List) {
        final idx = int.tryParse(segment);
        current = idx != null && idx >= 0 && idx < current.length
            ? current[idx]
            : null;
      } else {
        return null;
      }
      if (current == null) return null;
    }
    return current;
  }

  /// 时间戳解析：毫秒数 / 秒数 / ISO 字符串都试一遍
  static DateTime? parseTimestamp(Object? raw) {
    if (raw is num) {
      final v = raw.toInt();
      if (v > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(v);
      }
      if (v > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(v * 1000);
      }
      return null;
    }
    if (raw is String) {
      final n = int.tryParse(raw);
      if (n != null) return parseTimestamp(n);
      return DateTime.tryParse(raw);
    }
    return null;
  }
}
