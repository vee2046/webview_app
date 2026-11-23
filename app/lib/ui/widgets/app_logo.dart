/// App 品牌图标 —— kmlab_site 的 favicon。
///
/// 路径来自配置的 `app.icon`（默认 `assets/icon.svg`）：
/// **配置即契约** —— 换图标只改配置，不改代码。
///
/// 素材来源：`kmlab_site/public/favicon.svg`（= `dist/favicon.svg`），
/// 与桌面图标、自适应图标前景层、单色层共用同一套描边数据。
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../icons/doodle_icons.dart';
import '../../theme/paper_theme.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    required this.path,
    this.size = 28,
  });

  /// 资产路径（相对 Flutter 资产根），来自 `app.icon`。
  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.paper;
    return SvgPicture.asset(
      path,
      width: size,
      height: size,
      fit: BoxFit.contain,
      // 资源读不到时（路径写错 / 没进 pubspec）不能崩 —— 退回工具盒 doodle。
      placeholderBuilder: (_) =>
          DoodleIcon('box', size: size * 0.8, color: p.ink),
    );
  }
}
