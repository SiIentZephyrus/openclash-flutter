import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openclash_client/dashboard_controller.dart';
import 'package:openclash_client/app_notice.dart';
import 'support/fixture_controller.dart';
import 'support/profile_fixture.dart';
import 'package:openclash_client/main.dart';

// Run with flutter test test/preview_capture.dart
// Add --dart-define=PREVIEW_FONT=<a local CJK font> for readable Chinese.
void main() {
  testWidgets('capture Android-sized app previews', (tester) async {
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = previousShadows);
    const font = String.fromEnvironment('PREVIEW_FONT');
    if (font.isNotEmpty) {
      final loader = FontLoader('Microsoft YaHei');
      loader.addFont(
        Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
      );
      await loader.load();
      final monospace = FontLoader('monospace');
      monospace.addFont(
        Future.value(ByteData.sublistView(File(font).readAsBytesSync())),
      );
      await monospace.load();
    }
    SharedPreferences.setMockInitialValues({});
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = FixtureController();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: OpenClashApp(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async => tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('screenshots/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
    await capture('overview');
    for (final page in {
      '代理': 'proxies',
      '日志': 'logs',
      '设置': 'settings',
    }.entries) {
      await tester.tap(find.text(page.key).last);
      await tester.pumpAndSettle();
      await capture(page.value);
      if (page.key == '代理') {
        await capture('group-node-button');
        await tester.tap(find.byKey(const ValueKey('view-group-节点选择-自动选择')));
        await tester.pumpAndSettle();
        await capture('group-node-jump');
        await tester.tap(find.byTooltip('返回顶部'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('collapse-all-groups')));
        await tester.pumpAndSettle();
        await capture('proxies-traffic');
        await tester.tap(find.byTooltip('展开所有策略组'));
        await tester.pumpAndSettle();
        for (final option in {
          '列表': 'list',
          '紧凑': 'compact',
          '卡片': 'card',
        }.entries) {
          await tester.tap(find.byTooltip('页面布局'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(option.key));
          await tester.pumpAndSettle();
          await capture('proxies-${option.value}');
        }
        await tester.tap(find.byTooltip('代理快捷菜单'));
        await tester.pumpAndSettle();
        await capture('proxies-menu');
        await tester.tap(find.text('测试所有节点延迟'));
        await tester.pumpAndSettle();
        await capture('notice-latency');
        await tester.tap(find.byKey(const ValueKey('dismiss-app-notice')));
        await tester.pumpAndSettle();
      }
    }
    final host = tester.state<AppNoticeHostState>(find.byType(AppNoticeHost));
    host.show(
      const AppNotice(
        title: '控制器已保存',
        message: '下次启动将自动连接，无需重复填写。',
        tone: NoticeTone.success,
      ),
    );
    await tester.pumpAndSettle();
    await capture('notice-success');
    host.show(
      const AppNotice(
        title: '操作未完成',
        message: '连接超时，请检查路由器地址和网络。',
        tone: NoticeTone.error,
      ),
    );
    await tester.pumpAndSettle();
    await capture('notice-error');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    final setupController = DashboardController(
      store: MemoryControllerStore(),
      apiFactory: ApiRecorder().create,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: OpenClashApp(controller: setupController),
      ),
    );
    await tester.pumpAndSettle();
    await capture('setup');
    await tester.pumpWidget(const SizedBox());
    setupController.dispose();
    debugDisableShadows = previousShadows;
  });
}
