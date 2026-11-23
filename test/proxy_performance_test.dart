import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclash_client/group_traffic.dart';
import 'package:openclash_client/main.dart';
import 'package:openclash_client/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixture_controller.dart';

void main() {
  final list = find.byKey(const ValueKey('proxy-list'));
  final builtNodes = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('proxy-node-');
  });

  for (final layout in ['card', 'list', 'compact']) {
    testWidgets('large proxy lists stay lazy and jump directly in $layout', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'proxyLayout': layout});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = FixtureController();
      final nodes = List.generate(3000, (i) => '性能测试节点-$i');
      for (final name in nodes) {
        c.proxies[name] = ProxyNode(name: name, type: 'Trojan', delay: 45);
      }
      c.proxies['节点选择']!.members
        ..insert(0, '远处目标')
        ..addAll(nodes);
      for (var i = 0; i < 24; i++) {
        c.proxies['大策略组-$i'] = ProxyNode(
          name: '大策略组-$i',
          type: 'Selector',
          members: nodes,
        );
      }
      c.proxies['远处目标'] = ProxyNode(
        name: '远处目标',
        type: 'URLTest',
        hidden: true,
        members: ['节点选择', nodes.first],
      );
      await tester.pumpWidget(OpenClashApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('代理').last);
      await tester.pumpAndSettle();

      // More than 75,000 node slots must not create 75,000 tile widgets.
      expect(builtNodes.evaluate().length, inExclusiveRange(0, 100));
      c.updateTraffic('节点选择', const TrafficRate(upload: 1024));
      await tester.pump();
      expect(builtNodes.evaluate().length, lessThan(100));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('group-upload-节点选择')))
            .data,
        '1.0 KB/s',
      );

      Future<void> jump(String source, String target) async {
        await tester.tap(find.byKey(ValueKey('view-group-$source-$target')));
        // Do not pumpAndSettle: a distant jump must finish within a small,
        // constant number of frames, regardless of preceding group sizes.
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final header = find.byKey(ValueKey('proxy-group-header-$target'));
        expect(
          tester.getTopLeft(header).dy,
          closeTo(tester.getTopLeft(list).dy + 4, 2),
        );
        expect(find.text('未能定位策略组'), findsNothing);
        expect(builtNodes.evaluate().length, lessThan(100));
      }

      await jump('节点选择', '远处目标');
      expect(
        tester.widget<ScrollView>(list).controller!.offset,
        greaterThan(100000),
      );
      await jump('远处目标', '节点选择');
      expect(c.selectionCalls, 0);
      expect(tester.takeException(), isNull);

      // Search for a node that was never built, then select it and verify
      // that the controller update still refreshes the tile.
      await tester.enterText(
        find.byKey(const ValueKey('proxy-search')),
        nodes.last,
      );
      await tester.pumpAndSettle();
      final lastNode = find.byKey(ValueKey('proxy-node-节点选择-${nodes.last}'));
      await tester.ensureVisible(lastNode);
      await tester.tap(lastNode);
      await tester.pump();
      expect(c.proxies['节点选择']!.now, nodes.last);
      expect(c.selectionCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets(
      'proxy grid scrolls to its last row after resizing in $layout',
      (tester) async {
        SharedPreferences.setMockInitialValues({'proxyLayout': layout});
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = FixtureController();
        final nodes = List.generate(3001, (i) => '节点-$i');
        c.proxies = {
          '大策略组': ProxyNode(name: '大策略组', type: 'Selector', members: nodes),
          for (final name in nodes) name: ProxyNode(name: name, type: 'Trojan'),
        };
        await tester.pumpWidget(OpenClashApp(controller: c));
        await tester.pumpAndSettle();
        await tester.tap(find.text('代理').last);
        await tester.pumpAndSettle();
        expect(find.text(nodes.last), findsNothing);
        final scroll = tester.widget<ScrollView>(list).controller!;
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(find.text(nodes.last), findsOneWidget);
        expect(builtNodes.evaluate().length, lessThan(40));

        tester.view.physicalSize = const Size(1280, 900);
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(find.text(nodes.last), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
