import 'package:flutter/material.dart';

/// "Follow the light": cream and indigo by day, night blue and lavender in dark mode.
/// Confidence is shown as how bright the star is, never in red or green, so a result never looks like a verdict.
@immutable
class LumisPalette extends ThemeExtension<LumisPalette> {
  const LumisPalette({
    required this.isDark,
    required this.background,
    required this.cardTop,
    required this.cardBottom,
    required this.border,
    required this.divider,
    required this.ink,
    required this.body,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.nebulaTop,
    required this.nebulaBottom,
    required this.nebulaBorder,
    required this.nebulaText,
    required this.buttonTop,
    required this.buttonBottom,
    required this.onButton,
    required this.secondaryBorder,
    required this.starStart,
    required this.starEnd,
    required this.glow,
    required this.starLow,
    required this.starOutline,
    required this.danger,
    required this.shadow,
    required this.warning,
  });

  final bool isDark;
  final Color background;
  final Color cardTop;
  final Color cardBottom;
  final Color border;
  final Color divider;
  final Color ink; // headings and main text
  final Color body; // longer reading text
  final Color muted; // labels
  final Color faint; // footnotes
  final Color accent; // links, icons, selected things
  final Color nebulaTop;
  final Color nebulaBottom;
  final Color nebulaBorder;
  final Color nebulaText;
  final Color buttonTop;
  final Color buttonBottom;
  final Color onButton;
  final Color secondaryBorder;
  final Color starStart;
  final Color starEnd;
  final Color glow;
  final Color starLow;
  final Color starOutline;
  final Color danger;
  final Color shadow;
  final Color warning; // the camera's "too dark" hint only

  static const light = LumisPalette(
    isDark: false,
    background: Color(0xFFF6F3EC), // cream
    cardTop: Color(0xFFFFFFFF), // paper
    cardBottom: Color(0xFFFBF9F4),
    border: Color(0xFFE6E1D6),
    divider: Color(0xFFEEEAE1),
    ink: Color(0xFF1C1B3A),
    body: Color(0xFF3A3958),
    muted: Color(0xFF5E5C7A),
    faint: Color(0xFF6E6C88),
    accent: Color(0xFF4C46D1), // indigo
    nebulaTop: Color(0xFFF3F1FF),
    nebulaBottom: Color(0xFFECE9FB),
    nebulaBorder: Color(0xFFDEDAF7),
    nebulaText: Color(0xFF2E2C5A),
    buttonTop: Color(0xFF5B55E0),
    buttonBottom: Color(0xFF423CC4),
    onButton: Color(0xFFFFFFFF),
    secondaryBorder: Color(0xFFD9D3C6),
    starStart: Color(0xFF3F39C7),
    starEnd: Color(0xFFA9A6F2),
    glow: Color(0xFF7F7BFF),
    starLow: Color(0xFFA9A6F2),
    starOutline: Color(0xFF8D8BA8),
    danger: Color(0xFFA3212B),
    shadow: Color(0x144C46D1),
    warning: Color(0xFFFFD98A),
  );

  static const dark = LumisPalette(
    isDark: true,
    background: Color(0xFF0F1022), // night
    cardTop: Color(0xFF1B1D3B),
    cardBottom: Color(0xFF16182F),
    border: Color(0xFF262948), // orbit
    divider: Color(0xFF23264A),
    ink: Color(0xFFF3EFE6), // moonlight
    body: Color(0xFFE3E1F2),
    muted: Color(0xFFA6A8C6),
    faint: Color(0xFF8C8EB0),
    accent: Color(0xFFC9C6FF),
    nebulaTop: Color(0xFF24264E),
    nebulaBottom: Color(0xFF1E2044),
    nebulaBorder: Color(0xFF33366A),
    nebulaText: Color(0xFFDCDAF5),
    buttonTop: Color(0xFFD3D1FF),
    buttonBottom: Color(0xFFA9A6FF), // lavender
    onButton: Color(0xFF0F1022),
    secondaryBorder: Color(0xFF34376A),
    starStart: Color(0xFFFFFFFF),
    starEnd: Color(0xFFB9B5FF),
    glow: Color(0xFFD6D3FF),
    starLow: Color(0xFF7D7AC4),
    starOutline: Color(0xFF8C8EB0),
    danger: Color(0xFFFF9C9C),
    shadow: Color(0x59000000),
    warning: Color(0xFFFFD98A),
  );

  LinearGradient get cardGradient =>
      LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [cardTop, cardBottom]);
  LinearGradient get nebulaGradient =>
      LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [nebulaTop, nebulaBottom]);
  LinearGradient get buttonGradient =>
      LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [buttonTop, buttonBottom]);

  @override
  LumisPalette copyWith() => this;

  @override
  LumisPalette lerp(ThemeExtension<LumisPalette>? other, double t) =>
      other is LumisPalette && t >= 0.5 ? other : this;
}

extension LumisContext on BuildContext {
  LumisPalette get palette => Theme.of(this).extension<LumisPalette>() ?? LumisPalette.light;
}

/// Jost for headings and the wordmark (thin, wide), Inter for reading text.
const headingFont = 'Jost';
const bodyFont = 'Inter';

ThemeData lumisTheme([Brightness brightness = Brightness.light]) {
  final p = brightness == Brightness.dark ? LumisPalette.dark : LumisPalette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.isDark ? p.buttonBottom : p.accent,
    onPrimary: p.onButton,
    secondary: p.accent,
    onSecondary: p.onButton,
    secondaryContainer: p.nebulaTop,
    onSecondaryContainer: p.nebulaText,
    error: p.danger,
    onError: p.onButton,
    surface: p.background,
    onSurface: p.ink,
    onSurfaceVariant: p.muted,
    outline: p.secondaryBorder,
    outlineVariant: p.border,
    surfaceContainerHighest: p.cardTop,
    surfaceContainerHigh: p.cardTop,
    surfaceContainer: p.cardTop,
    surfaceContainerLow: p.cardBottom,
    surfaceContainerLowest: p.cardTop,
  );
  TextStyle h(double size, {FontWeight weight = FontWeight.w300, double height = 1.18}) =>
      TextStyle(fontFamily: headingFont, fontSize: size, fontWeight: weight, height: height, color: p.ink);
  TextStyle b(double size, {FontWeight weight = FontWeight.w400, double height = 1.5, Color? color}) =>
      TextStyle(fontFamily: bodyFont, fontSize: size, fontWeight: weight, height: height, color: color ?? p.ink);
  final text = TextTheme(
    displaySmall: h(40),
    headlineLarge: h(34, height: 1.1),
    headlineMedium: h(30),
    headlineSmall: h(26, height: 1.2),
    titleLarge: h(22, weight: FontWeight.w400),
    titleMedium: b(15, weight: FontWeight.w500, height: 1.35),
    titleSmall: b(14, weight: FontWeight.w500),
    bodyLarge: b(16, weight: FontWeight.w300, height: 1.55),
    bodyMedium: b(15, weight: FontWeight.w300, height: 1.6),
    bodySmall: b(12, weight: FontWeight.w300, color: p.faint),
    labelLarge: b(15, weight: FontWeight.w500, height: 1.2),
    labelMedium: b(13, height: 1.2),
    labelSmall: b(11, height: 1.2, color: p.muted).copyWith(letterSpacing: 2),
  );
  final radius8 = BorderRadius.circular(8);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: bodyFont,
    textTheme: text,
    scaffoldBackgroundColor: p.background,
    extensions: [p],
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: h(22),
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: p.cardTop,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: p.border)),
    ),
    dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.cardTop,
      labelStyle: b(15, weight: FontWeight.w300, color: p.muted),
      border: OutlineInputBorder(borderRadius: radius8, borderSide: BorderSide(color: p.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius8, borderSide: BorderSide(color: p.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius8, borderSide: BorderSide(color: p.accent, width: 1.4)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: p.isDark ? p.buttonBottom : p.accent,
        foregroundColor: p.onButton,
        disabledBackgroundColor: p.border,
        shape: RoundedRectangleBorder(borderRadius: radius8),
        textStyle: b(15, weight: FontWeight.w500),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: p.ink,
        side: BorderSide(color: p.secondaryBorder),
        shape: RoundedRectangleBorder(borderRadius: radius8),
        textStyle: b(15, weight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.accent, textStyle: b(15, weight: FontWeight.w500)),
    ),
    chipTheme: ChipThemeData(
      color: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? (p.isDark ? p.buttonBottom : p.accent) : p.cardTop),
      labelStyle: WidgetStateTextStyle.resolveWith(
          (s) => b(13, height: 1.2, color: s.contains(WidgetState.selected) ? p.onButton : p.ink)),
      side: WidgetStateBorderSide.resolveWith((s) => BorderSide(
          color: s.contains(WidgetState.selected) ? (p.isDark ? p.buttonBottom : p.accent) : p.border)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onButton : p.cardTop),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? (p.isDark ? p.buttonBottom : p.accent) : p.border),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? (p.isDark ? p.buttonBottom : p.accent) : Colors.transparent),
      checkColor: WidgetStateProperty.all(p.onButton),
      side: BorderSide(color: p.starOutline, width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? (p.isDark ? p.buttonBottom : p.accent) : p.starOutline),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: p.cardBottom,
        selectedBackgroundColor: p.cardTop,
        selectedForegroundColor: p.ink,
        foregroundColor: p.muted,
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: radius8),
        textStyle: b(14),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent, linearTrackColor: p.border),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.isDark ? p.cardTop : p.ink,
      contentTextStyle: b(14, color: p.isDark ? p.ink : p.background),
      shape: RoundedRectangleBorder(borderRadius: radius8),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.cardTop,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titleTextStyle: h(22, weight: FontWeight.w400),
      contentTextStyle: b(15, weight: FontWeight.w300, color: p.body),
    ),
    listTileTheme: ListTileThemeData(iconColor: p.accent, textColor: p.ink),
  );
}
