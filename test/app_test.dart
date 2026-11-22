import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openclash_client/dashboard_controller.dart';
import 'support/fixture_controller.dart';
import 'package:openclash_client/main.dart';
import 'package:openclash_client/group_traffic.dart';
import 'package:openclash_client/models.dart';

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
  testWidgets('live group traffic updates while collapsed in every layout', (
    tester,
  ) async {
    final c = (await mount(tester, const Size(320, 740))) as FixtureController;
    await tester.tap(find.text('代理').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('collapse-all-groups')));
    await tester.pumpAndSettle();
    final upload = find.byKey(const ValueKey('group-upload-节点选择'));
    final download = find.byKey(const ValueKey('group-download-节点选择'));
    expect(tester.widget<Text>(upload).data, '128.0 KB/s');
    expect(tester.widget<Text>(download).data, '2.4 MB/s');
    expect(find.byKey(const ValueKey('proxy-members-节点选择')), findsNothing);
    c.updateTraffic('节点选择', const TrafficRate(upload: 2048, download: 512000));
    await tester.pump();
    expect(tester.widget<Text>(upload).data, '2.0 KB/s');
    expect(tester.widget<Text>(download).data, '500.0 KB/s');
    for (final label in ['列表', '紧凑', '卡片']) {
      await tester.tap(find.byTooltip('页面布局'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(download, findsOneWidget);
      expect(tester.takeException(), isNull, reason: label);
    }
    // Exercise wrapping with enlarged text and large rates on a narrow screen.
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    c.updateTraffic(
      '节点选择',
      const TrafficRate(upload: 512000, download: 999999999),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  for (final option in {'卡片': 'card', '列表': 'list', '紧凑': 'compact'}.entries) {
    testWidgets(
      'selected group tile opens its group without selecting again in ${option.value}',
      (tester) async {
        final c =
            (await mount(tester, const Size(320, 740))) as FixtureController;
        await tester.tap(find.text('代理').last);
        await tester.pumpAndSettle();
        if (option.value != 'card') {
          await tester.tap(find.byTooltip('页面布局'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(option.key));
          await tester.pumpAndSettle();
        }
        final node = find.text('自动选择').first;
        await tester.tap(node);
        await tester.pumpAndSettle();
        expect(c.proxies['节点选择']!.now, '自动选择');
        expect(c.selectionCalls, 1);
        await tester.tap(node);
        await tester.pumpAndSettle();
        final listTop = tester
            .getTopLeft(find.byKey(const ValueKey('proxy-list')))
            .dy;
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('proxy-group-header-自动选择')))
              .dy,
          closeTo(listTop + 4, 2),
        );
        expect(c.selectionCalls, 1);
        expect(
          tester
              .widget<Wrap>(
                find.byKey(ValueKey('proxy-layout-${option.value}-自动选择')),
              )
              .children
              .length,
          c.proxies['自动选择']!.members.length,
        );
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets(
      'group button reveals all members without selection in ${option.value}',
      (tester) async {
        final c = await mount(tester, const Size(320, 740));
        await tester.tap(find.text('代理').last);
        await tester.pumpAndSettle();
        if (option.value != 'card') {
          await tester.tap(find.byTooltip('页面布局'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(option.key));
          await tester.pumpAndSettle();
        }
        final original = c.proxies['节点选择']!.now;
        await tester.tap(find.text('节点', skipOffstage: false).first);
        await tester.enterText(
          find.byKey(const ValueKey('proxy-search')),
          '自动选择',
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('proxy-group-自动选择')), findsNothing);
        expect(
          find.byKey(const ValueKey('view-group-节点选择-香港 · HKT 01')),
          findsNothing,
        );
        final menu = find.byKey(const ValueKey('view-group-节点选择-自动选择'));
        await tester.ensureVisible(menu);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(c.proxies['节点选择']!.now, original);
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('proxy-search')))
              .controller!
              .text,
          isEmpty,
        );
        final target = find.byKey(const ValueKey('proxy-group-header-自动选择'));
        final listTop = tester
            .getTopLeft(find.byKey(const ValueKey('proxy-list')))
            .dy;
        expect(tester.getTopLeft(target).dy, closeTo(listTop, 4));
        final members = find.byKey(
          ValueKey('proxy-layout-${option.value}-自动选择'),
        );
        expect(
          tester.widget<Wrap>(members).children.length,
          c.proxies['自动选择']!.members.length,
        );
        expect(
          find.descendant(of: members, matching: find.text('美国 · San Jose')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }

  testWidgets(
    'jump reaches an unbuilt hidden group and navigates back up a long list',
    (tester) async {
      final c = await mount(tester, const Size(360, 740));
      final names = c.proxies['自动选择']!.members;
      for (var i = 0; i < 40; i++) {
        c.proxies['中间组-$i'] = ProxyNode(
          name: '中间组-$i',
          type: i.isEven ? 'Selector' : 'URLTest',
          members: names.take(4).toList(),
        );
      }
      c.proxies['远处的隐藏组'] = ProxyNode(
        name: '远处的隐藏组',
        type: 'URLTest',
        hidden: true,
        members: ['节点选择', ...names],
      );
      c.proxies['节点选择']!.members.insert(0, '远处的隐藏组');
      final original = c.proxies['节点选择']!.now;
      await tester.tap(find.text('代理').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('proxy-group-远处的隐藏组')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('view-group-节点选择-远处的隐藏组')));
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('proxy-list')),
      );
      expect(list.controller!.offset, greaterThan(4000));
      final listTop = tester
          .getTopLeft(find.byKey(const ValueKey('proxy-list')))
          .dy;
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('proxy-group-header-远处的隐藏组')))
            .dy,
        closeTo(listTop, 4),
      );
      expect(
        tester
            .widget<Wrap>(
              find.byKey(const ValueKey('proxy-layout-card-远处的隐藏组')),
            )
            .children
            .length,
        names.length + 1,
      );
      await tester.tap(find.byKey(const ValueKey('view-group-远处的隐藏组-节点选择')));
      await tester.pumpAndSettle();
      expect(
        tester
            .getTopLeft(find.byKey(const ValueKey('proxy-group-header-节点选择')))
            .dy,
        closeTo(listTop, 4),
      );
      expect(c.proxies['节点选择']!.now, original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  for (final (label, value) in [
    ('卡片', 'card'),
    ('列表', 'list'),
    ('紧凑', 'compact'),
  ]) {
    testWidgets(
      'jump aligns a small last group after expanding a filtered long list in $value',
      (tester) async {
        final c = await mount(tester, const Size(390, 844));
        final nodes = List.generate(100, (i) => '真实节点-$i');
        for (final name in nodes) {
          c.proxies[name] = ProxyNode(name: name, type: 'Trojan', delay: 45);
        }
        c.proxies['节点选择']!.members.addAll(nodes);
        for (var i = 0; i < 12; i++) {
          c.proxies['大组-$i'] = ProxyNode(
            name: '大组-$i',
            type: 'Selector',
            members: nodes,
          );
        }
        c.proxies['末尾目标'] = ProxyNode(
          name: '末尾目标',
          type: 'URLTest',
          members: ['香港 · HKT 01'],
        );
        c.proxies['节点选择']!.members.insert(0, '末尾目标');
        await tester.tap(find.text('代理').last);
        await tester.pumpAndSettle();
        if (value != 'card') {
          await tester.tap(find.byTooltip('页面布局'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('节点', skipOffstage: false).first);
        await tester.enterText(
          find.byKey(const ValueKey('proxy-search')),
          '末尾目标',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('view-group-节点选择-末尾目标')));
        await tester.pumpAndSettle();
        final header = find.byKey(const ValueKey('proxy-group-header-末尾目标'));
        expect(header, findsOneWidget);
        final listTop = tester
            .getTopLeft(find.byKey(const ValueKey('proxy-list')))
            .dy;
        expect(tester.getTopLeft(header).dy, closeTo(listTop + 4, 4));
        expect(
          find.byKey(ValueKey('proxy-layout-$value-末尾目标')),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(header).dy, closeTo(listTop + 4, 2));
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }

  testWidgets('selected nested group is viewable inside an automatic group', (
    tester,
  ) async {
    final c = (await mount(tester, const Size(360, 740))) as FixtureController;
    c.proxies['自动选择']!.members.insert(0, '流媒体');
    c.proxies['自动选择']!.now = '流媒体';
    await tester.tap(find.text('代理').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('策略组'));
    await tester.enterText(find.byKey(const ValueKey('proxy-search')), '自动选择');
    await tester.pumpAndSettle();
    await tester.tap(find.text('流媒体').first);
    await tester.pumpAndSettle();
    expect(c.selectionCalls, 0);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('proxy-search')))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('操作未完成'), findsNothing);
    expect(find.text('未能定位策略组'), findsNothing);
    final top = tester.getTopLeft(find.byKey(const ValueKey('proxy-list'))).dy;
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('proxy-group-header-流媒体')))
          .dy,
      closeTo(top + 4, 2),
    );
    expect(c.selectionCalls, 0);
    expect(c.proxies['自动选择']!.now, '流媒体');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('jump waits for keyboard dismissal before aligning the header', (
    tester,
  ) async {
    final c = await mount(tester, const Size(390, 844));
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(find.text('代理').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('proxy-search')), '自动选择');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('view-group-节点选择-自动选择'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 50));
    tester.view.viewInsets = const FakeViewPadding(bottom: 150);
    await tester.pump(const Duration(milliseconds: 100));
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(find.byKey(const ValueKey('proxy-list'))).dy;
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('proxy-group-header-自动选择')))
          .dy,
      closeTo(top + 4, 2),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('leaving the proxy page during a group jump is safe', (
    tester,
  ) async {
    final c = await mount(tester, const Size(360, 740));
    await tester.tap(find.text('代理').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-group-节点选择-自动选择')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('概览').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

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
