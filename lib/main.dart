import 'package:flutter/material.dart';
import 'app_notice.dart';
import 'app_theme.dart';
import 'dashboard_controller.dart';
import 'screens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OpenClashApp());
}

class OpenClashApp extends StatefulWidget {
  const OpenClashApp({super.key, this.controller});
  final DashboardController? controller;

  @override
  State<OpenClashApp> createState() => _OpenClashAppState();
}

class _OpenClashAppState extends State<OpenClashApp> {
  late final controller = widget.controller ?? DashboardController();
  late final lightTheme = openClashTheme(Brightness.light);
  late final darkTheme = openClashTheme(Brightness.dark);

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
    theme: lightTheme,
    darkTheme: darkTheme,
    home: DashboardShell(controller: controller),
  );
}
