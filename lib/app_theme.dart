import 'package:flutter/material.dart';

extension AppColors on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  Color get accent => colors.primary;
  Color get ink => colors.onSurface;
  Color get muted => colors.onSurfaceVariant;
  Color get surface => colors.surface;
  Color get stroke => colors.outlineVariant;
  Color get canvasColor => Theme.of(this).scaffoldBackgroundColor;
  Color get selectedSurface => colors.primaryContainer;
}

ThemeData openClashTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xFF087F72),
    brightness: brightness,
    primary: dark ? const Color(0xFF81D8C4) : const Color(0xFF087F72),
    onPrimary: dark ? const Color(0xFF00382F) : Colors.white,
    surface: dark ? const Color(0xFF172425) : Colors.white,
    onSurface: dark ? const Color(0xFFE1EDEC) : const Color(0xFF172C30),
    onSurfaceVariant: dark ? const Color(0xFFAEBCBC) : const Color(0xFF65787D),
    outlineVariant: dark ? const Color(0xFF3B4D4C) : const Color(0xFFE5ECEB),
    primaryContainer: dark ? const Color(0xFF22433C) : const Color(0xFFDDF3EC),
    onPrimaryContainer: dark
        ? const Color(0xFFBCEBDD)
        : const Color(0xFF15584F),
    surfaceContainerLow: dark
        ? const Color(0xFF1D2E2F)
        : const Color(0xFFFAFBFB),
    surfaceContainerHighest: dark
        ? const Color(0xFF283939)
        : const Color(0xFFF0F4F4),
  );
  final canvas = dark ? const Color(0xFF101B1C) : const Color(0xFFF4F7F7);
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: canvas,
    colorScheme: colors,
    fontFamily: 'Microsoft YaHei',
    fontFamilyFallback: const ['Noto Sans CJK SC', 'Roboto', 'sans-serif'],
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: colors.onSurface, fontSize: 13),
      bodyLarge: TextStyle(color: colors.onSurface, fontSize: 14),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      foregroundColor: colors.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    dividerColor: colors.outlineVariant,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHighest,
      hintStyle: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: colors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surface,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      indicatorColor: colors.primaryContainer,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? colors.primary : colors.onSurfaceVariant,
        );
      }),
    ),
  );
}
