import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/config_loader.dart';
import 'config/config_store.dart';
import 'data/usage_store.dart';
import 'theme/paper_theme.dart';
import 'ui/root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final configStore = ConfigStore(loader: ConfigLoader());
  final usage = UsageStore();

  await usage.load();

  final prefs = await SharedPreferences.getInstance();
  final dark = prefs.getBool('km.theme.dark') ?? false;

  runApp(KmlabApp(configStore: configStore, usage: usage, initialDark: dark));

  // 首屏已经用内置快照渲染出来了，后台再静默拉远端配置。
  unawaited(configStore.bootstrap());
}

void unawaited(Future<void> f) {
  f.catchError((_) {});
}

class KmlabApp extends StatefulWidget {
  const KmlabApp({
    super.key,
    required this.configStore,
    required this.usage,
    required this.initialDark,
  });

  final ConfigStore configStore;
  final UsageStore usage;
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
        darkMode: _dark,
        onDarkModeChanged: _setDark,
      ),
    );
  }
}
