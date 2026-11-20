// 「牛皮纸速写本」主题 —— token 与 kmlab_site 的 `src/styles/global.css` 严格一致。
//
// 设计禁忌（与 kmlab_site 相同）：
//   ❌ emoji 图标 → 只用内联 SVG 线稿（见 `lib/icons/doodle_icons.dart`）
//   ❌ 彩色渐变铺底 / 玻璃拟态 / 霓虹发光
//   ❌ 卡片旋转角雷同 → 按 id 哈希取稳定种子，每张都不一样
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

// 与 kmlab_site 一一对应的设计 token。
@immutable
class PaperTokens extends ThemeExtension<PaperTokens> {
  const PaperTokens({
    required this.paper,
    required this.paperDeep,
    required this.paperCard,
    required this.ink,
    required this.inkSoft,
    required this.crayonRed,
    required this.crayonBlue,
    required this.crayonGreen,
    required this.crayonAmber,
    required this.crayonPurple,
    required this.lineWidth,
    required this.shadowPaper,
    required this.shadowHover,
    required this.isDark,
  });

  final Color paper;
  final Color paperDeep;
  final Color paperCard;
  final Color ink;
  final Color inkSoft;
  final Color crayonRed;
  final Color crayonBlue;
  final Color crayonGreen;
  final Color crayonAmber;
  final Color crayonPurple;
  final double lineWidth;
  final List<BoxShadow> shadowPaper;
  final List<BoxShadow> shadowHover;
  final bool isDark;

  static const PaperTokens light = PaperTokens(
    paper: Color(0xFFF6F1E4),
    paperDeep: Color(0xFFECE4D0),
    paperCard: Color(0xFFFBF7EC),
    ink: Color(0xFF2F2A24),
    inkSoft: Color(0xFF6B6256),
    crayonRed: Color(0xFFD9534F),
    crayonBlue: Color(0xFF3D6B8A),
    crayonGreen: Color(0xFF6F9264),
    crayonAmber: Color(0xFFD9A441),
    crayonPurple: Color(0xFF8A6FA3),
    lineWidth: 2.5,
    shadowPaper: [
      BoxShadow(color: Color(0x292F2A24), offset: Offset(3, 4), blurRadius: 0),
    ],
    shadowHover: [
      BoxShadow(color: Color(0x242F2A24), offset: Offset(6, 10), blurRadius: 0),
    ],
    isDark: false,
  );

  static const PaperTokens dark = PaperTokens(
    paper: Color(0xFF1B140E),
    paperDeep: Color(0xFF2A211A),
    paperCard: Color(0xFF302619),
    ink: Color(0xFFF2E8DA),
    inkSoft: Color(0xFFB8A892),
    crayonRed: Color(0xFFE07571),
    crayonBlue: Color(0xFF6C9CBA),
    crayonGreen: Color(0xFF8FB083),
    crayonAmber: Color(0xFFE3B45C),
    crayonPurple: Color(0xFFA98CBD),
    lineWidth: 2.5,
    shadowPaper: [
      BoxShadow(color: Color(0x80000000), offset: Offset(3, 4), blurRadius: 0),
    ],
    shadowHover: [
      BoxShadow(color: Color(0x73000000), offset: Offset(6, 10), blurRadius: 0),
    ],
    isDark: true,
  );

  @override
  PaperTokens copyWith({
    Color? paper,
    Color? paperDeep,
    Color? paperCard,
    Color? ink,
    Color? inkSoft,
    Color? crayonRed,
    Color? crayonBlue,
    Color? crayonGreen,
    Color? crayonAmber,
    Color? crayonPurple,
    double? lineWidth,
    List<BoxShadow>? shadowPaper,
    List<BoxShadow>? shadowHover,
    bool? isDark,
  }) =>
      PaperTokens(
        paper: paper ?? this.paper,
        paperDeep: paperDeep ?? this.paperDeep,
        paperCard: paperCard ?? this.paperCard,
        ink: ink ?? this.ink,
        inkSoft: inkSoft ?? this.inkSoft,
        crayonRed: crayonRed ?? this.crayonRed,
        crayonBlue: crayonBlue ?? this.crayonBlue,
        crayonGreen: crayonGreen ?? this.crayonGreen,
        crayonAmber: crayonAmber ?? this.crayonAmber,
        crayonPurple: crayonPurple ?? this.crayonPurple,
        lineWidth: lineWidth ?? this.lineWidth,
        shadowPaper: shadowPaper ?? this.shadowPaper,
        shadowHover: shadowHover ?? this.shadowHover,
        isDark: isDark ?? this.isDark,
      );

  @override
  PaperTokens lerp(ThemeExtension<PaperTokens>? other, double t) {
    if (other is! PaperTokens) return this;
    return PaperTokens(
      paper: Color.lerp(paper, other.paper, t)!,
      paperDeep: Color.lerp(paperDeep, other.paperDeep, t)!,
      paperCard: Color.lerp(paperCard, other.paperCard, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      crayonRed: Color.lerp(crayonRed, other.crayonRed, t)!,
      crayonBlue: Color.lerp(crayonBlue, other.crayonBlue, t)!,
      crayonGreen: Color.lerp(crayonGreen, other.crayonGreen, t)!,
      crayonAmber: Color.lerp(crayonAmber, other.crayonAmber, t)!,
      crayonPurple: Color.lerp(crayonPurple, other.crayonPurple, t)!,
      lineWidth: lerpDouble(lineWidth, other.lineWidth, t)!,
      shadowPaper: BoxShadow.lerpList(shadowPaper, other.shadowPaper, t)!,
      shadowHover: BoxShadow.lerpList(shadowHover, other.shadowHover, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// 便捷访问
extension PaperTokensX on BuildContext {
  PaperTokens get paper => Theme.of(this).extension<PaperTokens>()!;
}

/// 「手绘」圆角：Flutter 的 BorderRadius 每一角都能给不同的 x/y，
/// 正好复刻 CSS 的 `border-radius: 22px 12px 22px 12px / 12px 22px 12px 22px`。
BorderRadius paperBorderRadius(double base, {double? alternate}) {
  final a = alternate ?? base * 0.55;
  return BorderRadius.only(
    topLeft: Radius.elliptical(base, a),
    topRight: Radius.elliptical(a, base),
    bottomRight: Radius.elliptical(base, a),
    bottomLeft: Radius.elliptical(a, base),
  );
}

/// Transform.rotate 的 `angle` 用的是**弧度**，而 seededTilt 返回的是「度」。
/// 直接把度塞进 Transform.rotate 会让 1.2° 变成 68°，卡片会歪到天上去。
double tiltToRadians(double degrees) => degrees * math.pi / 180;

/// 稳定的伪随机角度 —— 同一 id 永远得到同一个角，不会在 rebuild 时跳动。
///
/// kmlab_site 用 `seededBetween` 做同一件事。
double seededTilt(String seed, {double min = -1.2, double max = 1.2}) {
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  final rnd = math.Random(hash);
  return min + rnd.nextDouble() * (max - min);
}

/// 主题构建
ThemeData buildPaperTheme({required bool dark}) {
  final t = dark ? PaperTokens.dark : PaperTokens.light;

  final base = ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: t.paper,
    colorScheme: ColorScheme.fromSeed(
      seedColor: t.crayonAmber,
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(
      surface: t.paper,
      onSurface: t.ink,
      primary: t.crayonAmber,
      secondary: t.crayonBlue,
      error: t.crayonRed,
    ),
  );

  // 中文字体走系统里的手写/圆体，回退到默认，避免出现方框
  const zhFallback = <String>[
    'PingFang SC',
    'Hiragino Sans GB',
    'Heiti SC',
    'Microsoft YaHei',
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  TextStyle ink(TextStyle? base) => base?.copyWith(color: t.ink) ?? TextStyle(color: t.ink);

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[t],
    scaffoldBackgroundColor: t.paper,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    dividerColor: t.ink.withValues(alpha: 0.16),
    textTheme: base.textTheme
        .copyWith(
          displaySmall: ink(base.textTheme.displaySmall).copyWith(
            fontSize: 28,
            height: 1.25,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: zhFallback,
          ),
          titleLarge: ink(base.textTheme.titleLarge).copyWith(
            fontSize: 20,
            height: 1.3,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: zhFallback,
          ),
          titleMedium: ink(base.textTheme.titleMedium).copyWith(
            fontSize: 15,
            height: 1.35,
            letterSpacing: 0.4,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: zhFallback,
          ),
          bodyMedium: ink(base.textTheme.bodyMedium).copyWith(
            fontSize: 13.5,
            height: 1.5,
            fontFamilyFallback: zhFallback,
          ),
          bodySmall: ink(base.textTheme.bodySmall).copyWith(
            fontSize: 12,
            height: 1.45,
            color: t.inkSoft,
            fontFamilyFallback: zhFallback,
          ),
          labelLarge: ink(base.textTheme.labelLarge).copyWith(
            fontSize: 13,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: zhFallback,
          ),
          labelSmall: ink(base.textTheme.labelSmall).copyWith(
            fontSize: 10.5,
            color: t.inkSoft,
            letterSpacing: 0.6,
            fontFamilyFallback: zhFallback,
          ),
        )
        .apply(bodyColor: t.ink, displayColor: t.ink),
    appBarTheme: AppBarTheme(
      backgroundColor: t.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: t.ink, size: 20),
      titleTextStyle: TextStyle(
        color: t.ink,
        fontSize: 20,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w600,
        fontFamilyFallback: zhFallback,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.paperCard,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.paperCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: paperBorderRadius(18),
        side: BorderSide(color: t.ink, width: t.lineWidth),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.ink,
      contentTextStyle: TextStyle(
        color: t.paper,
        fontSize: 13,
        fontFamilyFallback: zhFallback,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: paperBorderRadius(14)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? t.paperCard : t.paperCard,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? t.crayonGreen
            : t.paperDeep,
      ),
      trackOutlineColor: WidgetStatePropertyAll(t.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.paperCard,
      hintStyle: TextStyle(color: t.inkSoft, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      // ⚠️ OutlineInputBorder 只支持「圆角」（Flutter 内部断言 _cornersAreCircular）。
      //    纸片风格的椭圆不规则角花在这里会在 paint 阶段直接抛断言，
      //    所以输入框统一走圆角，纸片的味道留给卡片和按钮。
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.ink, width: t.lineWidth),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.ink, width: t.lineWidth),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.ink, width: t.lineWidth + 0.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.crayonRed, width: t.lineWidth),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.crayonRed, width: t.lineWidth + 0.8),
      ),
    ),
  );
}
