import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclash_client/dashboard_controller.dart';
import 'package:openclash_client/models.dart';

void main() {
  test(
    'connection stream updates group speed and clears stale or closed streams',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final ready = Completer<WebSocket>();
      final logsReady = Completer<WebSocket>();
      final sockets = <WebSocket>[];
      final openedByPath = <String, List<WebSocket>>{};
      final c = DashboardController();
      final listener = server.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          openedByPath.putIfAbsent(request.uri.path, () => []).add(socket);
          if (request.uri.path == '/connections' && !ready.isCompleted) {
            ready.complete(socket);
          }
          if (request.uri.path == '/logs' && !logsReady.isCompleted) {
            logsReady.complete(socket);
          }
          return;
        }
        final data = switch (request.uri.path) {
          '/version' => {'version': 'test'},
          '/configs' => {'mode': 'rule'},
          '/proxies' => {'proxies': <String, dynamic>{}},
          '/providers/proxies' => {'providers': <String, dynamic>{}},
          _ => {
            'rules': [
              {'type': 'MATCH'},
            ],
          },
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(data));
        await request.response.close();
      });
      Future<void> until(bool Function() condition) async {
        for (var i = 0; i < 200 && !condition(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(condition(), isTrue);
      }

      try {
        await c.connect('http://127.0.0.1:${server.port}', '');
        final socket = await ready.future.timeout(const Duration(seconds: 3));
        final logSocket = await logsReady.future.timeout(
          const Duration(seconds: 3),
        );
        await until(() => c.liveStreams.length == 4 && c.rules.isNotEmpty);
        final updates = {
          for (final section in DashboardSection.values) section: 0,
        };
        for (final section in DashboardSection.values) {
          c
              .updatesFor(section)
              .addListener(() => updates[section] = updates[section]! + 1);
        }
        logSocket.add(jsonEncode({'type': 'info', 'payload': 'scoped update'}));
        await until(() => updates[DashboardSection.logs] == 1);
        expect(updates[DashboardSection.session], 0);
        expect(updates[DashboardSection.proxies], 0);
        expect(updates[DashboardSection.overview], 0);
        expect(updates[DashboardSection.connections], 0);
        void snapshot(int bytes) => socket.add(
          jsonEncode({
            'connections': [
              {
                'id': 'live',
                'upload': bytes,
                'download': bytes * 2,
                'chains': ['HK', 'inner', 'outer'],
              },
            ],
          }),
        );
        snapshot(10000);
        await until(() => c.connections.isNotEmpty);
        expect(c.trafficFor('outer'), isNull);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        snapshot(11000);
        await until(() => c.trafficFor('outer') != null);
        expect(c.trafficFor('outer')!.download, greaterThan(0));
        expect(updates[DashboardSection.groupTraffic], 2);
        expect(updates[DashboardSection.connections], greaterThanOrEqualTo(2));
        expect(updates[DashboardSection.session], 0);
        expect(updates[DashboardSection.proxies], 0);
        expect(updates[DashboardSection.logs], 1);
        expect(
          c.trafficFor('outer')!.download,
          c.trafficFor('inner')!.download,
        );
        await Future<void>.delayed(const Duration(milliseconds: 4100));
        expect(c.trafficFor('outer'), isNull);
        snapshot(1000000);
        await until(() => c.connections.single['upload'] == 1000000);
        expect(c.trafficFor('outer'), isNull);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        snapshot(1001000);
        await until(() => c.trafficFor('outer') != null);
        socket.add(jsonEncode({'connections': []}));
        await until(() => c.connections.isEmpty);
        expect(c.recentConnections.single['id'], 'live');
        expect(c.recentConnections.single['upload'], 1001000);
        await socket.close();
        await until(() => c.trafficFor('outer') == null);

        await c.setBackgrounded(true);
        expect(c.liveStreams, isEmpty);
        expect(c.recentConnections.single['id'], 'live');
        expect(c.logs.single.message, 'scoped update');
        await c.setBackgrounded(false);
        await until(() => c.liveStreams.length == 4);
        expect(
          openedByPath.values.every((channels) => channels.length == 2),
          isTrue,
        );
        expect(c.connected, isTrue);
        expect(c.trafficFor('outer'), isNull);
        expect(c.recentConnections.single['id'], 'live');
        c.disconnect();
        expect(c.trafficFor('inner'), isNull);
        expect(c.recentConnections, isEmpty);
      } finally {
        c.dispose();
        for (final socket in sockets) {
          await socket.close();
        }
        await listener.cancel();
        await server.close(force: true);
      }
    },
  );

  test(
    'strategy groups follow GLOBAL config order instead of response order',
    () {
      final controller = DashboardController();
      addTearDown(controller.dispose);
      ProxyNode group(
        String name, {
        List<String> members = const ['HK'],
        bool hidden = false,
      }) => ProxyNode(
        name: name,
        type: 'Selector',
        members: members,
        hidden: hidden,
      );
      controller.proxies = {
        'C': group('C'),
        'B': group('B'),
        'A': group('A'),
        'hidden': group('hidden', hidden: true),
        'tail-2': group('tail-2'),
        'tail-1': group('tail-1'),
        'HK': ProxyNode(name: 'HK', type: 'Trojan'),
        'GLOBAL': group(
          'GLOBAL',
          members: ['HK', 'A', 'hidden', 'missing', 'B', 'A', 'C'],
        ),
      };
      expect(controller.groups.map((g) => g.name), [
        'A',
        'B',
        'C',
        'tail-2',
        'tail-1',
      ]);
      controller.mode = 'global';
      expect(controller.groups.map((g) => g.name), [
        'GLOBAL',
        'A',
        'B',
        'C',
        'tail-2',
        'tail-1',
      ]);
      controller.mode = 'rule';
      controller.proxies.remove('GLOBAL');
      expect(controller.groups.map((g) => g.name), [
        'C',
        'B',
        'A',
        'tail-2',
        'tail-1',
      ]);
    },
  );
  test(
    'real HTTP/WS flow authenticates, streams logs, and preserves selection on failure',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final controller = DashboardController();
      var failSelection = true;
      final updates = <String>[];
      final listener = server.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          expect(request.uri.queryParameters['token'], 'secret');
          final socket = await WebSocketTransformer.upgrade(request);
          sockets.add(socket);
          final data = switch (request.uri.path) {
            '/logs' => {'type': 'info', 'payload': 'live test log'},
            '/traffic' => {'up': 1024, 'down': 4096},
            '/memory' => {'inuse': 2048},
            _ => {'connections': [], 'uploadTotal': 100, 'downloadTotal': 200},
          };
          socket.add(jsonEncode(data));
          return;
        }
        expect(request.headers.value('Authorization'), 'Bearer secret');
        Object data = {};
        if (request.uri.path == '/version') data = {'version': 'test-mihomo'};
        if (request.uri.path == '/configs') data = {'mode': 'rule'};
        if (request.uri.path == '/rules') data = {'rules': []};
        if (request.uri.path == '/proxies') {
          data = {
            'proxies': {
              '选择 / 组': {
                'type': 'Selector',
                'now': '香港',
                'all': ['香港', '日本'],
              },
              '香港': {'type': 'Trojan', 'history': []},
              '日本': {'type': 'Trojan', 'history': []},
            },
          };
        }
        if (request.method == 'PUT') {
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          updates.add(body['name'] as String);
          request.response.statusCode = failSelection ? 500 : 204;
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(data));
        }
        await request.response.close();
      });
      try {
        await controller.connect('http://127.0.0.1:${server.port}', 'secret');
        expect(controller.connected, isTrue);
        for (var i = 0; i < 100 && controller.logs.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(controller.logs.single.message, 'live test log');
        expect(controller.down, 4096);
        final group = controller.groups.single;
        await expectLater(controller.select(group, '日本'), throwsException);
        expect(group.now, '香港');
        expect(controller.switching, isEmpty);
        failSelection = false;
        await controller.select(group, '日本');
        expect(group.now, '日本');
        expect(updates, ['日本', '日本']);
        await controller.changeMode('direct');
        expect(controller.mode, 'direct');
        controller.disconnect();
        expect(controller.connected, isFalse);
        expect(controller.liveStreams, isEmpty);
      } finally {
        controller.dispose();
        for (final socket in sockets) {
          await socket.close();
        }
        await listener.cancel();
        await server.close(force: true);
      }
    },
  );
}
