import 'package:flutter/material.dart';
import 'dashboard_controller.dart';
import 'screens.dart';
import 'app_notice.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OpenClashApp());
}

const accent = Color(0xFF087F72);
const ink = Color(0xFF172C30);
const muted = Color(0xFF7B8C90);
const canvas = Color(0xFFF4F7F7);
const stroke = Color(0xFFE5ECEB);

class OpenClashApp extends StatefulWidget {
  const OpenClashApp({super.key, this.controller});
  final DashboardController? controller;
  @override
  State<OpenClashApp> createState() => _OpenClashAppState();
}

class _OpenClashAppState extends State<OpenClashApp> {
  late final controller = widget.controller ?? DashboardController();
  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OpenClash',
    debugShowCheckedModeBanner: false,
    builder: (context, child) =>
        AppNoticeHost(child: child ?? const SizedBox.shrink()),
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        primary: accent,
        surface: Colors.white,
      ),
      fontFamily: 'Microsoft YaHei',
      fontFamilyFallback: const ['Noto Sans CJK SC', 'Roboto', 'sans-serif'],
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: ink, fontSize: 13),
        bodyLarge: TextStyle(color: ink, fontSize: 14),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: canvas,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerColor: stroke,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: stroke),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF0F4F4),
        hintStyle: const TextStyle(color: muted, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: stroke),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFDDF3EC),
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? accent : muted,
          ),
        ),
      ),
    ),
    home: DashboardShell(controller: controller),
  );
}
