import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclash_client/controller_store.dart';
import 'package:openclash_client/dashboard_controller.dart';
import 'package:openclash_client/main.dart';
import 'support/profile_fixture.dart';

void main() {
  Future<DashboardController> mount(
    WidgetTester tester,
    MemoryControllerStore store,
    ApiRecorder api,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = DashboardController(store: store, apiFactory: api.create);
    await tester.pumpWidget(OpenClashApp(controller: c));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> cleanup(WidgetTester tester, DashboardController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  Future<void> enter(WidgetTester tester, String address, String secret) async {
    await tester.enterText(
      find.byKey(const ValueKey('controller-address')),
      address,
    );
    await tester.enterText(
      find.byKey(const ValueKey('controller-secret')),
      secret,
    );
  }

  testWidgets('automatic reconnect does not interrupt manual editing', (
    tester,
  ) async {
    final store = MemoryControllerStore()
      ..profile = ControllerProfile('http://offline', 'keep-key');
    final api = ApiRecorder();
    final c = await mount(tester, store, api);
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改控制器'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(api.credentials.length, 1);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('controller-address')),
          )
          .enabled,
      isTrue,
    );
    await tester.tap(find.text('取消修改'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(api.credentials.length, 2);
    expect(store.profile!.secret, 'keep-key');
    expect(store.writes, 0);
    expect(tester.takeException(), isNull);
    await cleanup(tester, c);
  });

  testWidgets('first launch cannot enter dashboard without saving controller', (
    tester,
  ) async {
    final store = MemoryControllerStore();
    final api = ApiRecorder();
    final c = await mount(tester, store, api);
    expect(find.text('连接你的控制器'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('演示模式'), findsNothing);
    await tester.tap(find.text('保存并进入'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效的 http:// 或 https:// 地址'), findsOneWidget);
    expect(api.credentials, isEmpty);
    expect(store.writes, 0);
    expect(tester.takeException(), isNull);
    await cleanup(tester, c);
  });
  testWidgets(
    'setup waits until successful validation and local persistence before entry',
    (tester) async {
      final store = MemoryControllerStore()..pendingWrite = Completer<void>();
      final c = await mount(tester, store, ApiRecorder());
      await enter(tester, 'http://router:9090', 'saved-key');
      await tester.tap(find.text('保存并进入'));
      await tester.pump();
      expect(c.hasProfile, isFalse);
      expect(find.byType(NavigationBar), findsNothing);
      store.pendingWrite!.complete();
      await tester.pumpAndSettle();
      expect(c.hasProfile, isTrue);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(store.profile!.secret, 'saved-key');
      expect(store.writes, 1);
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );
  testWidgets('authentication failure stays on setup and keeps storage empty', (
    tester,
  ) async {
    final store = MemoryControllerStore();
    final c = await mount(tester, store, ApiRecorder());
    await enter(tester, 'http://router', 'wrong');
    await tester.tap(find.text('保存并进入'));
    await tester.pumpAndSettle();
    expect(find.textContaining('认证失败'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(store.profile, isNull);
    await cleanup(tester, c);
  });
  testWidgets(
    'saved profile opens dashboard and requires explicit editing to change credentials',
    (tester) async {
      final store = MemoryControllerStore()
        ..profile = ControllerProfile('http://old-router', 'old-key');
      final api = ApiRecorder();
      final c = await mount(tester, store, api);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(api.credentials.single, ('http://old-router', 'old-key'));
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      final address = find.byKey(const ValueKey('controller-address'));
      final secret = find.byKey(const ValueKey('controller-secret'));
      expect(tester.widget<TextFormField>(address).enabled, isFalse);
      expect(tester.widget<TextFormField>(secret).controller!.text, 'old-key');
      await tester.tap(find.text('修改控制器'));
      await tester.pumpAndSettle();
      await enter(tester, 'http://discard-router', 'discard-key');
      await tester.tap(find.text('取消修改'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(address).controller!.text,
        'http://old-router',
      );
      expect(tester.widget<TextFormField>(secret).controller!.text, 'old-key');
      expect(store.writes, 0);
      await tester.tap(find.text('修改控制器'));
      await tester.pumpAndSettle();
      await enter(tester, 'http://new-router', 'new-key');
      await tester.tap(find.text('保存并连接'));
      await tester.pumpAndSettle();
      expect(store.profile!.address, 'http://new-router');
      expect(store.profile!.secret, 'new-key');
      expect(tester.widget<TextFormField>(address).enabled, isFalse);
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );
  testWidgets(
    'saved offline profile keeps dashboard accessible without fake nodes',
    (tester) async {
      final store = MemoryControllerStore()
        ..profile = ControllerProfile('http://offline', 'keep-key');
      final c = await mount(tester, store, ApiRecorder());
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('连接你的控制器'), findsNothing);
      await tester.tap(find.text('代理').last);
      await tester.pumpAndSettle();
      expect(find.text('控制器未连接'), findsOneWidget);
      expect(c.proxies, isEmpty);
      expect(store.profile!.secret, 'keep-key');
      expect(store.writes, 0);
      expect(tester.takeException(), isNull);
      await cleanup(tester, c);
    },
  );
}
