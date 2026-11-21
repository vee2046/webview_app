/// 图标库
///
/// * **Doodle** —— 直接复用 `kmlab_site/src/components/DoodleIcon.vue` 的 SVG 路径，
///   一个字节都不改（viewBox 0 0 64 64，stroke-width 2.6，fill none，round cap/join）。
/// * **Ui** —— App 自身的 chrome 图标（返回、⋯、设置……），24×24 线稿，同样不用 emoji。
///
/// 全部以 `SvgPicture.string` 内联渲染，避免为每个图标建一个资源文件。
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// kmlab_site 的 doodle 图标集（路径逐字复用 DoodleIcon.vue）
const Map<String, String> _doodles = {
  'checkin': '''
<path d="M14 16 h36 a3 3 0 0 1 3 3 v33 a3 3 0 0 1 -3 3 h-36 a3 3 0 0 1 -3 -3 v-33 a3 3 0 0 1 3 -3 z"/>
<path d="M11 27 h42"/>
<path d="M22 9 v9 M42 9 v9"/>
<path d="M22 39 l7 7 l14 -15"/>''',
  'water': '''
<path d="M18 14 h28 l-3.5 38 a3 3 0 0 1 -3 2.7 h-15 a3 3 0 0 1 -3 -2.7 z"/>
<path d="M18.5 30 h27"/>
<path d="M32 20 c-3.5 4 -5 6.4 -5 8.6 a5 5 0 0 0 10 0 c0 -2.2 -1.5 -4.6 -5 -8.6 z"/>''',
  'money': '''
<path d="M17 22 H47 a3 3 0 0 1 3 3 V39 a3 3 0 0 1 -3 3 H17 a3 3 0 0 1 -3 -3 V25 a3 3 0 0 1 3 -3 Z"/>
<circle cx="32" cy="32" r="6"/>
<path d="M19 28 V36 M45 28 V36"/>''',
  'pill': '''
<path d="M20.6 33.4 L33.6 46.4 A9 9 0 0 0 46.4 46.4 L33.4 20.6 A9 9 0 0 0 20.6 33.4 Z"/>
<path d="M27.1 39.9 L39.9 27.1"/>''',
  'key': '''
<circle cx="21" cy="43" r="8"/>
<circle cx="21" cy="43" r="2.6"/>
<path d="M27 37 L52 12"/>
<path d="M45 19 L50 24 M49 15 L54 20"/>''',
  'note': '''
<path d="M16 10 h32 a2.5 2.5 0 0 1 2.5 2.5 v28.5 l-11 13 h-23.5 a2.5 2.5 0 0 1 -2.5 -2.5 v-39 a2.5 2.5 0 0 1 2.5 -2.5 z"/>
<path d="M40 44.5 v9.5 l9.5 -9.5"/>
<path d="M23 24 h18 M23 32 h18 M23 40 h11"/>''',
  'rocket': '''
<path d="M32 7 c9 6 12 15 12 26 v6 l-12 13 l-12 -13 v-6 c0 -11 3 -20 12 -26 z"/>
<circle cx="32" cy="27" r="4.6"/>
<path d="M20 31 l-8 6 l6 9 M44 31 l8 6 l-6 9"/>
<path d="M28.5 52 l-1 6 M35.5 52 l1 6"/>''',
  'brain': '''
<path d="M17 48 C11 48 8 42 10 37 C5 33 6 25 11 22 C12 15 19 11 25 13 C28 8 36 8 39 13 C45 11 52 15 53 22 C58 25 59 33 54 37 C56 42 53 48 47 48 Z"/>
<path d="M32 12 V48"/>
<path d="M20 27 H28 M22 36 H28 M36 27 H44 M36 36 H42"/>''',
  'box': '''
<path d="M12 22 l20 -9 l20 9 v22 l-20 9 l-20 -9 z"/>
<path d="M12 22 l20 9 l20 -9 M32 31 v22"/>
<path d="M22 17.5 l10 4.5 l10 -4.5"/>''',
};

/// App chrome 图标（24×24 线稿）
const Map<String, String> _ui = {
  'back': '<path d="M15 5 L8 12 l7 7"/>',
  'more': '<circle cx="5.4" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="18.6" cy="12" r="1.7"/>',
  'close': '<path d="M6 6 l12 12 M18 6 L6 18"/>',
  'settings':
      '<path d="M3.6 7.4h11M18.4 7.4h2M3.6 16.6h2M9.6 16.6h10.8"/><circle cx="16.4" cy="7.4" r="2.2"/><circle cx="7.4" cy="16.6" r="2.2"/>',
  'search': '<circle cx="10.6" cy="10.6" r="6.6"/><path d="m15.4 15.4 4.4 4.4"/>',
  'grid':
      '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  'clock': '<circle cx="12" cy="12" r="8.6"/><path d="M12 7.2V12l3.2 2.2"/>',
  'history': '<circle cx="12" cy="12" r="8.6"/><path d="M12 7v5.4"/><path d="M3.6 9.6A8.6 8.6 0 0 1 12 3.4"/>',
  'cup':
      '<path d="M4.6 6.4h12v7a5 5 0 0 1-5 5h-2a5 5 0 0 1-5-5v-7Z"/><path d="M16.6 8.2h1.8a2.2 2.2 0 0 1 0 4.4h-1.8"/><path d="M3.4 20.4h14.2"/>',
  'check': '<circle cx="12" cy="12" r="8.6"/><path d="M8.2 12.2 11 15l5-5.4"/>',
  'book':
      '<path d="M12 6.4C10.4 5 8.4 4.4 4 4.6v13.2c4.4-.2 6.4.4 8 1.8 1.6-1.4 3.6-2 8-1.8V4.6c-4.4-.2-6.4.4-8 1.8Z"/><path d="M12 6.4v13.2"/>',
  'share':
      '<path d="M12 15.4V3.6M8.4 7.2 12 3.6l3.6 3.6"/><path d="M5 12.6v6.2a1.6 1.6 0 0 0 1.6 1.6h10.8a1.6 1.6 0 0 0 1.6-1.6v-6.2"/>',
  'download':
      '<path d="M12 3.6v11M7.8 10.4 12 14.6l4.2-4.2"/><path d="M4.4 17.4v1.4a1.6 1.6 0 0 0 1.6 1.6h12a1.6 1.6 0 0 0 1.6-1.6v-1.4"/>',
  'upload':
      '<path d="M12 15.4v-11M7.8 8.6 12 4.4l4.2 4.2"/><path d="M4.4 17.4v1.4a1.6 1.6 0 0 0 1.6 1.6h12a1.6 1.6 0 0 0 1.6-1.6v-1.4"/>',
  'trash':
      '<path d="M4.6 6.6h14.8M9.4 6.6V4.8h5.2v1.8M6.6 6.6l.9 12a1.6 1.6 0 0 0 1.6 1.5h5.8a1.6 1.6 0 0 0 1.6-1.5l.9-12"/><path d="M10.4 10v6M13.6 10v6"/>',
  'globe':
      '<circle cx="12" cy="12" r="8.6"/><path d="M3.6 12h16.8"/><path d="M12 3.4c2.2 2.4 3.4 5.4 3.4 8.6s-1.2 6.2-3.4 8.6c-2.2-2.4-3.4-5.4-3.4-8.6S9.8 5.8 12 3.4Z"/>',
  'pin': '<path d="M9 3.6h6l-.8 6 4.4 4.2H5.4L9.8 9.6Z"/><path d="M12 13.8v6.6"/>',
  'fullscreen':
      '<path d="M4.4 9V4.4H9M15 4.4h4.6V9M19.6 15v4.6H15M9 19.6H4.4V15"/>',
  'info': '<circle cx="12" cy="12" r="8.6"/><path d="M12 11v5.4"/><circle cx="12" cy="7.8" r="1.1" fill="currentColor" stroke="none"/>',
  'mail': '<rect x="3" y="5.4" width="18" height="13.2" rx="2.2"/><path d="m3.6 7 8.4 6 8.4-6"/>',
  'wifi':
      '<path d="M2.8 9.4a14 14 0 0 1 18.4 0M5.8 13a9.4 9.4 0 0 1 12.4 0M8.8 16.4a5 5 0 0 1 6.4 0"/><circle cx="12" cy="19.6" r="1.2" fill="currentColor" stroke="none"/>',
  'copy': '<rect x="8.4" y="8.4" width="11.2" height="11.2" rx="2"/><path d="M15.6 5.6a2 2 0 0 0-2-1.2H6a2 2 0 0 0-2 2v7.6a2 2 0 0 0 1.2 2"/>',
  'link': '<path d="M10.2 13.8a4 4 0 0 0 5.7 0l2.6-2.6a4 4 0 1 0-5.7-5.7l-1.4 1.4"/><path d="M13.8 10.2a4 4 0 0 0-5.7 0l-2.6 2.6a4 4 0 1 0 5.7 5.7l1.4-1.4"/>',
  'sun':
      '<circle cx="12" cy="12" r="4.2"/><path d="M12 2.6v2.4M12 19v2.4M2.6 12h2.4M19 12h2.4M5.4 5.4l1.7 1.7M16.9 16.9l1.7 1.7M18.6 5.4l-1.7 1.7M7.1 16.9l-1.7 1.7"/>',
  'moon': '<path d="M20 14.6A8.4 8.4 0 0 1 9.4 4a8.6 8.6 0 1 0 10.6 10.6Z"/>',
  'lock': '<rect x="4.8" y="10.4" width="14.4" height="9.4" rx="2.2"/><path d="M8.2 10.4V7.8a3.8 3.8 0 0 1 7.6 0v2.6"/>',
  'toolbox':
      '<path d="M3.4 10.4h17.2v8.2a1.8 1.8 0 0 1-1.8 1.8H5.2a1.8 1.8 0 0 1-1.8-1.8Z"/><path d="M8.6 10.4V7.8a1.8 1.8 0 0 1 1.8-1.8h3.2a1.8 1.8 0 0 1 1.8 1.8v2.6"/><path d="M3.4 14.6h17.2"/>',
  // 「分享长图」用：一张照片 + 右上角的小太阳（画框 + 折角 + 山）
  'image':
      '<rect x="3.2" y="4.6" width="17.6" height="14.8" rx="2.2"/><circle cx="8.6" cy="9.4" r="1.7"/><path d="M3.6 16.4l4.4-4 3.2 2.8 3.6-3.6 5.2 5"/>',
};

/// 取得 doodle 的 SVG 源码；未知名字回退到 `box`（与 kmlab_site 的 `doodleDefault` 一致）
String doodleSvg(String name, {required Color color}) {
  final body = _doodles[name] ?? _doodles['box']!;
  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" fill="none"
     stroke="rgb(${color.r},${color.g},${color.b})" stroke-width="2.6"
     stroke-linecap="round" stroke-linejoin="round">$body</svg>''';
}

/// 取得 UI 图标的 SVG 源码
String uiSvg(String name, {required Color color}) {
  final body = _ui[name] ?? _ui['box'] ?? _ui['grid']!;
  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
     stroke="rgb(${color.r},${color.g},${color.b})" stroke-width="1.8"
     stroke-linecap="round" stroke-linejoin="round">$body</svg>''';
}

/// kmlab doodle 图标
class DoodleIcon extends StatelessWidget {
  const DoodleIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.color = const Color(0xFF2F2A24),
  });

  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.string(
        doodleSvg(name, color: color),
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
}

/// App chrome 图标
class UiIcon extends StatelessWidget {
  const UiIcon(
    this.name, {
    super.key,
    this.size = 20,
    this.color = const Color(0xFF2F2A24),
    this.strokeWidth = 1.8,
  });

  final String name;
  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final svg = uiSvg(name, color: color).replaceFirst('stroke-width="1.8"', 'stroke-width="$strokeWidth"');
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
