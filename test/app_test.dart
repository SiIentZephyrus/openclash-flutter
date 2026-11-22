import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openclash_client/dashboard_controller.dart';
import 'support/fixture_controller.dart';
import 'package:openclash_client/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<DashboardController> mount(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = FixtureController();
    await tester.pumpWidget(OpenClashApp(controller: controller));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('phone supports selecting a proxy and searching nodes', (
    tester,
  ) async {
    final c = await mount(tester, const Size(390, 844));
    expect(find.text('演示模式'), findsNothing);
    await tester.tap(find.text('代理').last);
    await tester.pumpAndSettle();
    expect(find.text('代理节点'), findsOneWidget);
    await tester.tap(find.text('香港 · HKT 02').first);
    await tester.pumpAndSettle();
    expect(c.proxies['节点选择']!.now, '香港 · HKT 02');
    await tester.enterText(find.byType(TextField).first, '不存在的节点');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的节点'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('logs support pause filtering and clearing', (tester) async {
    final c = await mount(tester, const Size(390, 844));
    await tester.tap(find.text('日志').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('WARNING'));
    await tester.pumpAndSettle();
    expect(find.text('1 条记录'), findsOneWidget);
    await tester.tap(find.byTooltip('暂停日志'));
    await tester.pumpAndSettle();
    expect(find.text('已暂停'), findsOneWidget);
    await tester.tap(find.byTooltip('清空日志'));
    await tester.pumpAndSettle();
    expect(c.logs, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
    'strategy-group search only matches group names and can be cleared',
    (tester) async {
      final c = await mount(tester, const Size(390, 844));
      await tester.tap(find.text('代理').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('策略组'));
      await tester.enterText(
        find.byKey(const ValueKey('proxy-search')),
        ' 节点选择 ',
      );
      await tester.pumpAndSettle();
      expect(find.text('1 / 5 个策略组'), findsOneWidget);
      expect(find.byKey(const ValueKey('proxy-group-节点选择')), findsOneWidget);
      expect(find.byKey(const ValueKey('proxy-group-全球直连')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('proxy-search')), '不存在');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的策略组'), findsOneWidget);
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      expect(find.text('5 个策略组'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('fixed toolbar collapses hidden groups and returns to the top', (
    tester,
  ) async {
    final c = await mount(tester, const Size(360, 740));
    await tester.tap(find.text('代理').last);
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('proxy-list')),
    );
    list.controller!.jumpTo(550);
    await tester.pumpAndSettle();
    expect(list.controller!.offset, greaterThan(300));
    await tester.tap(find.byTooltip('返回顶部'));
    await tester.pumpAndSettle();
    expect(list.controller!.offset, 0);
    // Filtering must not limit the scope of the collapse-all action.
    await tester.tap(find.text('策略组'));
    await tester.enterText(find.byKey(const ValueKey('proxy-search')), '流媒体');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('collapse-all-groups')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('proxy-members-节点选择')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('proxy-search')), '全球直连');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('proxy-members-全球直连')), findsNothing);
    await tester.tap(find.byTooltip('展开所有策略组'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('proxy-members-全球直连')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('proxy-group-header-全球直连')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('proxy-members-全球直连')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets('small phone and wide layout render all pages without overflow', (
    tester,
  ) async {
    final c = await mount(tester, const Size(360, 740));
    for (final label in ['代理', '连接', '日志', '设置', '概览']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
    'search stays fixed when scrolling and filters from the current position',
    (tester) async {
      final c = await mount(tester, const Size(360, 740));
      await tester.tap(find.text('代理').last);
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('proxy-search'));
      final initial = tester.getTopLeft(field);
      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('proxy-list')),
      );
      list.controller!.jumpTo(650);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(field), initial);
      await tester.tap(find.text('策略组'));
      await tester.enterText(field, '流媒体');
      await tester.pumpAndSettle();
      expect(find.text('1 / 5 个策略组'), findsOneWidget);
      expect(tester.getTopLeft(field), initial);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('node test button measures only that node without selecting it', (
    tester,
  ) async {
    final c = await mount(tester, const Size(390, 844));
    await tester.tap(find.text('代理').last);
    await tester.pumpAndSettle();
    final previous = c.proxies['节点选择']!.now;
    final button = find.byKey(const ValueKey('test-node-节点选择-香港 · HKT 02'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(c.testingNodes, contains('香港 · HKT 02'));
    expect(c.proxies['节点选择']!.now, previous);
    await tester.pumpAndSettle();
    expect(c.testTotal, 1);
    expect(c.testCompleted, 1);
    expect(c.proxies['香港 · HKT 02']!.delay, 37);
    expect(c.proxies['节点选择']!.now, previous);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  testWidgets(
    'floating menu tests all nodes and all layouts persist without overflow',
    (tester) async {
      final c = await mount(tester, const Size(360, 740));
      await tester.tap(find.text('代理').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('代理快捷菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试所有节点延迟'));
      await tester.pumpAndSettle();
      expect(c.testTotal, 8);
      expect(c.testCompleted, 8);
      await tester.tap(find.byKey(const ValueKey('dismiss-app-notice')));
      await tester.pumpAndSettle();
      for (final item in {
        '列表': 'list',
        '紧凑': 'compact',
        '卡片': 'card',
      }.entries) {
        await tester.tap(find.byTooltip('页面布局'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(item.key));
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey('proxy-layout-${item.value}-节点选择')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: item.key);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('proxyLayout'), item.value);
      }
      await tester.tap(find.byTooltip('页面布局'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('列表'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('概览').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('代理').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('proxy-layout-list-节点选择')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('settings validates a controller URL', (tester) async {
    final c = await mount(tester, const Size(390, 844));
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('修改控制器'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'router');
    await tester.tap(find.text('保存并连接'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效的 http:// 或 https:// 地址'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
