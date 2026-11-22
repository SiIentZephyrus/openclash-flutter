import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openclash_client/app_notice.dart';
import 'package:openclash_client/main.dart';
import 'package:openclash_client/ui_components.dart';
import 'support/fixture_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<FixtureController> mount(
    WidgetTester tester, {
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = FixtureController();
    await tester.pumpWidget(OpenClashApp(controller: c));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> cleanup(WidgetTester tester, FixtureController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  testWidgets('latest notice replaces older notices and restarts its timeout', (
    tester,
  ) async {
    final c = await mount(tester);
    final host = tester.state<AppNoticeHostState>(find.byType(AppNoticeHost));
    host.show(
      const AppNotice(
        title: '旧提示',
        tone: NoticeTone.success,
        duration: Duration(seconds: 3),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    host.show(
      const AppNotice(
        title: '最新提示',
        tone: NoticeTone.info,
        duration: Duration(seconds: 6),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('旧提示'), findsNothing);
    expect(find.text('最新提示'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('最新提示'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('最新提示'), findsNothing);
    expect(tester.takeException(), isNull);
    await cleanup(tester, c);
  });

  testWidgets(
    'close button and swipe dismiss notices without blocking page navigation',
    (tester) async {
      final c = await mount(tester);
      final host = tester.state<AppNoticeHostState>(find.byType(AppNoticeHost));
      host.show(const AppNotice(title: '可以关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dismiss-app-notice')));
      await tester.pumpAndSettle();
      expect(find.text('可以关闭'), findsNothing);
      host.show(const AppNotice(title: '可以滑动关闭'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(AppNoticeCard), const Offset(400, 0));
      await tester.pumpAndSettle();
      expect(find.text('可以滑动关闭'), findsNothing);
      await tester.tap(find.text('代理').last);
      await tester.pumpAndSettle();
      expect(find.text('代理节点'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );

  testWidgets('action failures use the error notice instead of a snackbar', (
    tester,
  ) async {
    final c = await mount(tester);
    final context = tester.element(find.byType(NavigationBar));
    await runAction(context, () async => throw StateError('连接失败，请检查网络'));
    await tester.pumpAndSettle();
    final card = tester.widget<AppNoticeCard>(find.byType(AppNoticeCard));
    expect(card.notice.tone, NoticeTone.error);
    expect(find.text('操作未完成'), findsOneWidget);
    expect(find.textContaining('连接失败'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await cleanup(tester, c);
  });

  testWidgets(
    'latency statistics and long errors fit small screens with larger text',
    (tester) async {
      final c = await mount(tester, width: 320);
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final host = tester.state<AppNoticeHostState>(find.byType(AppNoticeHost));
      host.show(
        const AppNotice(
          title: '测速完成',
          message: '已测试 104 个节点。部分节点暂不可达，请检查控制器连接后重试。',
          tone: NoticeTone.warning,
          metrics: [
            NoticeMetric('成功', 100, NoticeTone.success),
            NoticeMetric('超时', 3, NoticeTone.warning),
            NoticeMetric('失败', 1, NoticeTone.error),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('测速完成'), findsOneWidget);
      expect(find.byType(AppNoticeCard), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('dismiss-app-notice')));
      await tester.pumpAndSettle();
      expect(find.byType(AppNoticeCard), findsNothing);
      await cleanup(tester, c);
    },
  );
}
