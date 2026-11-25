import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/config_loader.dart';
import 'config/config_store.dart';
import 'data/update_checker.dart';
import 'data/usage_store.dart';
import 'data/view_prefs.dart';
import 'icons/doodle_icons.dart';
import 'theme/paper_theme.dart';
import 'ui/root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final configStore = ConfigStore(loader: ConfigLoader());
  final usage = UsageStore();
  final viewPrefs = ViewPrefs();
  final updateStore = UpdateStore(UpdateChecker());

  await usage.load();
  await viewPrefs.load();

  final prefs = await SharedPreferences.getInstance();
  final dark = prefs.getBool('km.theme.dark') ?? false;

  runApp(KmlabApp(
    configStore: configStore,
    usage: usage,
    viewPrefs: viewPrefs,
    updateStore: updateStore,
    initialDark: dark,
  ));

  // 首屏已经用内置快照渲染出来了，后台再静默拉远端配置。
  unawaited(configStore.bootstrap().then((_) async {
    final cfg = configStore.config;
    if (cfg == null) return;
    // 远端配置里的 doodle 路径表装进全局注册表 ——
    // 站点新增一种图标，App 不用重新打包就能显示。
    DoodleIcons.install(cfg.app.icons.paths);
    // 远端配置到位后再查更新 —— 这样 updateUrl 也是最新的那一份。
    await updateStore.check(cfg.remote);
  }));
}

void unawaited(Future<void> f) {
  f.catchError((_) {});
}

class KmlabApp extends StatefulWidget {
  const KmlabApp({
    super.key,
    required this.configStore,
    required this.usage,
    required this.viewPrefs,
    required this.updateStore,
    required this.initialDark,
  });

  final ConfigStore configStore;
  final UsageStore usage;
  final ViewPrefs viewPrefs;
  final UpdateStore updateStore;
  final bool initialDark;

  @override
  State<KmlabApp> createState() => _KmlabAppState();
}

class _KmlabAppState extends State<KmlabApp> {
  late bool _dark = widget.initialDark;

  Future<void> _setDark(bool value) async {
    setState(() => _dark = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('km.theme.dark', value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.configStore.config?.app.appName ?? 'kmlab Toolbox',
      debugShowCheckedModeBanner: false,
      theme: buildPaperTheme(dark: false),
      darkTheme: buildPaperTheme(dark: true),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: RootShell(
        configStore: widget.configStore,
        usage: widget.usage,
        viewPrefs: widget.viewPrefs,
        updateStore: widget.updateStore,
        darkMode: _dark,
        onDarkModeChanged: _setDark,
      ),
    );
  }
}
