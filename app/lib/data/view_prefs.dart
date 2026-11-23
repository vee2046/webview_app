/// 视图偏好 —— 「最近」和「小工具」两页**共用**的显示格式开关。
///
/// 层级（重要）：
///   1. `app.home.layout`（远端配置）→ **默认**值
///   2. 用户在顶栏点过的选择 → 覆盖默认值，并持久化到本机
///
/// 所以配置里的 `layout` 不是摆设：没手动切过的用户跟随配置切过一次的用本机记忆。
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 显示格式。
enum ViewMode {
  /// 卡片（网格）
  grid,

  /// 列表（每行一个）
  list;

  ViewMode get other => this == ViewMode.grid ? ViewMode.list : ViewMode.grid;

  static ViewMode fromName(String? name) =>
      name == 'list' ? ViewMode.list : ViewMode.grid;
}

class ViewPrefs extends ChangeNotifier {
  /// SharedPreferences key（跟 `km.theme.dark` 同一套命名风格）。
  static const String key = 'km.view.mode';

  /// 配置给的默认值（`app.home.layout`）。
  ViewMode _configDefault = ViewMode.grid;

  /// 用户手动选过的值；null = 从没选过 → 跟随配置。
  ViewMode? _userChoice;

  /// 当前生效的显示格式。
  ViewMode get mode => _userChoice ?? _configDefault;

  bool get isGrid => mode == ViewMode.grid;
  bool get isList => mode == ViewMode.list;

  /// 用户是否手动选过（选过就不再跟随配置变）。
  bool get hasUserChoice => _userChoice != null;

  /// 读取持久化的用户选择（冷启动时调用）。
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return; // 从没选过 → 跟随配置
    final next = ViewMode.fromName(raw);
    if (next == _userChoice) return;
    _userChoice = next;
    notifyListeners();
  }

  /// 配置到达后告诉它默认值。**不会**覆盖用户已经选过的值。
  void setConfigDefault(ViewMode value) {
    if (_configDefault == value) return;
    _configDefault = value;
    if (_userChoice == null) notifyListeners();
  }

  /// 切换到另一种显示格式（记为用户选择）。
  Future<void> toggle() => setMode(mode.other);

  Future<void> setMode(ViewMode value) async {
    // 跟「当前生效的值」比，不是跟 `_userChoice` 比 ——
    // 没手动选过时生效值 = 配置默认值，此时 setMode(默认值) 应该是空操作。
    if (mode == value) return;
    _userChoice = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value.name);
  }
}
