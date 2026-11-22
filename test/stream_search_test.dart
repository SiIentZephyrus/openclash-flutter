import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclash_client/main.dart';
import 'package:openclash_client/models.dart';
import 'support/fixture_controller.dart';

class StreamFixture extends FixtureController {
  void publishConnections(List<Map<String, dynamic>> items) {
    connections = items;
    notifyListeners();
  }

  void publishLogs(List<LogEntry> items) {
    // The stream appends and trims the same list when the buffer is full.
    logs
      ..clear()
      ..addAll(items);
    notifyListeners();
  }

  @override
  Future<void> closeConnection(String id) async {
    connections = connections.where((item) => item['id'] != id).toList();
    notifyListeners();
  }
}

Map<String, dynamic> connection(String host) => {
  'id': host,
  'metadata': {'host': host},
};

void main() {
  Future<StreamFixture> mount(WidgetTester tester, String page) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = StreamFixture();
    c.connections = [connection('old.example'), connection('other.example')];
    c.logs = [
      LogEntry('info', 'old.example'),
      LogEntry('error', 'other.example'),
    ];
    await tester.pumpWidget(OpenClashApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text(page).last);
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
    return c;
  }

  testWidgets(
    'connection search includes recently ended and new connections without pausing',
    (tester) async {
      final c = await mount(tester, '连接');
      final search = find.byKey(const ValueKey('connection-search'));
      // A connection that ended before typing must also remain searchable.
      c.publishConnections([connection('new.example')]);
      await tester.pumpAndSettle();
      expect(find.text('old.example'), findsNothing);
      await tester.enterText(search, 'example');
      await tester.pumpAndSettle();
      expect(find.text('实时搜索 · 已结束保留 5 分钟'), findsOneWidget);
      c.publishConnections([connection('newest.example')]);
      await tester.pumpAndSettle();
      expect(find.text('old.example'), findsOneWidget);
      expect(find.text('new.example'), findsOneWidget);
      expect(find.text('近期连接 ${c.recentConnections.length}'), findsOneWidget);
      final oldClose = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(const ValueKey('connection-old.example')),
          matching: find.byType(IconButton),
        ),
      );
      expect(oldClose.onPressed, isNull);
      // The newest result is appended, preserving the position of older results.
      await tester.scrollUntilVisible(
        find.text('newest.example'),
        200,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('newest.example'), findsOneWidget);
      final latestClose = tester.widget<IconButton>(
        find.descendant(
          of: find.byKey(const ValueKey('connection-newest.example')),
          matching: find.byType(IconButton),
        ),
      );
      expect(latestClose.onPressed, isNotNull);

      await tester.enterText(search, 'old');
      await tester.pumpAndSettle();
      expect(find.text('old.example'), findsOneWidget);
      await tester.enterText(search, 'newest');
      await tester.pumpAndSettle();
      expect(find.text('old.example'), findsNothing);
      expect(find.text('newest.example'), findsOneWidget);
      expect(tester.widget<TextField>(search).controller!.text, 'newest');
      expect(find.byTooltip('暂停刷新连接'), findsOneWidget);

      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      c.publishConnections([connection('latest.example')]);
      await tester.pumpAndSettle();
      expect(find.text('latest.example'), findsOneWidget);
      expect(find.text('old.example'), findsNothing);
      expect(find.byTooltip('暂停刷新连接'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual connection pause survives clearing search and close removes snapshot',
    (tester) async {
      final c = await mount(tester, '连接');
      await tester.tap(find.byTooltip('暂停刷新连接'));
      await tester.enterText(
        find.byKey(const ValueKey('connection-search')),
        'old',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭连接').first);
      await tester.pumpAndSettle();
      expect(find.text('old.example'), findsNothing);
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      c.publishConnections([connection('new.example')]);
      await tester.pumpAndSettle();
      expect(find.text('other.example'), findsOneWidget);
      expect(find.text('new.example'), findsNothing);
      await tester.tap(find.byTooltip('继续刷新连接'));
      await tester.pumpAndSettle();
      expect(find.text('new.example'), findsOneWidget);
    },
  );

  testWidgets(
    'connection history keeps accumulating while viewing rules or another page',
    (tester) async {
      final c = await mount(tester, '连接');
      await tester.enterText(
        find.byKey(const ValueKey('connection-search')),
        'example',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('路由规则 ${c.rules.length}'));
      await tester.pumpAndSettle();
      expect(find.text('搜索已暂停刷新'), findsNothing);
      c.publishConnections([connection('new.example')]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('活跃连接 1'));
      await tester.pumpAndSettle();
      c.publishConnections([]);
      await tester.pumpAndSettle();
      expect(find.text('new.example'), findsOneWidget);
      expect(find.text('实时搜索 · 已结束保留 5 分钟'), findsOneWidget);
      await tester.tap(find.text('概览').last);
      await tester.pumpAndSettle();
      c.publishConnections([connection('background.example')]);
      c.publishConnections([]);
      await tester.tap(find.text('连接').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('connection-search')),
        'background',
      );
      await tester.pumpAndSettle();
      expect(find.text('background.example'), findsOneWidget);
      expect(find.text('已结束'), findsOneWidget);
    },
  );

  testWidgets(
    'log search survives buffer eviction and refresh preserves filter',
    (tester) async {
      final c = await mount(tester, '日志');
      final search = find.byKey(const ValueKey('log-search'));
      await tester.enterText(search, 'example');
      await tester.pumpAndSettle();
      c.publishLogs([LogEntry('info', 'new.example')]);
      await tester.pumpAndSettle();
      expect(find.text('old.example'), findsOneWidget);
      expect(find.text('new.example'), findsNothing);
      await tester.enterText(search, 'old');
      await tester.pumpAndSettle();
      expect(find.text('old.example'), findsOneWidget);
      await tester.enterText(search, 'example');
      await tester.tap(find.byTooltip('刷新日志快照'));
      await tester.pumpAndSettle();
      expect(find.text('new.example'), findsOneWidget);
      expect(find.text('old.example'), findsNothing);
      expect(find.text('搜索已暂停刷新'), findsOneWidget);
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      c.publishLogs([LogEntry('info', 'latest.example')]);
      await tester.pumpAndSettle();
      expect(find.text('latest.example'), findsOneWidget);
      expect(find.byTooltip('暂停日志'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual log pause survives clearing and user can resume while searching',
    (tester) async {
      final c = await mount(tester, '日志');
      final search = find.byKey(const ValueKey('log-search'));
      await tester.tap(find.byTooltip('暂停日志'));
      await tester.enterText(search, 'example');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      expect(find.text('已暂停'), findsOneWidget);
      await tester.enterText(search, 'example');
      await tester.tap(find.byTooltip('继续日志'));
      await tester.pumpAndSettle();
      c.publishLogs([LogEntry('info', 'new.example')]);
      await tester.pumpAndSettle();
      expect(find.text('new.example'), findsOneWidget);
      expect(find.byTooltip('刷新日志快照'), findsNothing);
    },
  );

  testWidgets(
    'search results do not auto-scroll on new logs even after resume',
    (tester) async {
      final c = await mount(tester, '日志');
      c.publishLogs(
        List.generate(50, (i) => LogEntry('info', 'example line $i')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('log-search')),
        'example',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('继续日志'));
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView));
      list.controller!.jumpTo(0);
      await tester.pumpAndSettle();
      c.publishLogs(
        List.generate(55, (i) => LogEntry('info', 'example line $i')),
      );
      await tester.pumpAndSettle();
      expect(list.controller!.offset, 0);
      expect(find.text('example line 0'), findsOneWidget);
    },
  );
}
