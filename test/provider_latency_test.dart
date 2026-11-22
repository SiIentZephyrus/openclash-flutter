import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclash_client/dashboard_controller.dart';

class _ProviderFixture {
  final c = DashboardController();
  late HttpServer server;
  final sockets = <WebSocket>[];
  final names = List.generate(8, (i) => '订阅节点 / #$i');
  static const provider = '订阅 / #A';
  final singleCalls = <String, int>{};
  int providerChecks = 0, wrongGlobalCalls = 0, staticCalls = 0;
  bool legacy = false, unavailable = false, checked = false, closing = false;

  Map<String, dynamic> providerData() => {
    'name': provider,
    'type': 'Proxy',
    'vehicleType': 'HTTP',
    'testUrl': 'http://health.example/generate_204',
    'proxies': [
      for (var i = 0; i < names.length; i++)
        {
          'name': names[i],
          'type': checked ? 'VMess' : 'Trojan',
          'history': [
            {
              'time': checked ? '2026-11-22T10:00:00Z' : '2026-11-22T09:00:00Z',
              'delay': checked ? (i == 7 ? 0 : 50 + i) : 15,
            },
          ],
        },
      // An entry also present in /proxies must retain the global route.
      {'name': 'static-node', 'type': 'Shadowsocks', 'history': []},
    ],
  };

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        if (closing) {
          await socket.close();
        } else {
          sockets.add(socket);
        }
        return;
      }
      final segments = request.uri.pathSegments;
      Object data = {};
      switch (request.uri.path) {
        case '/version':
          data = {'version': 'fixture-provider-core'};
        case '/configs':
          data = {'mode': 'rule'};
        case '/rules':
          data = {'rules': []};
        case '/proxies':
          data = {
            'proxies': {
              'GLOBAL': {
                'type': 'Selector',
                'all': ['策略 / 组', 'empty-selector', 'static-node'],
                'now': '策略 / 组',
              },
              '策略 / 组': {
                'type': 'Selector',
                'all': [...names, 'static-node', 'DIRECT'],
                'now': names.first,
              },
              'empty-selector': {'type': 'Selector', 'all': [], 'now': ''},
              'static-node': {'type': 'Trojan', 'history': []},
              'DIRECT': {'type': 'Direct'},
            },
          };
        case '/providers/proxies':
          if (unavailable) {
            request.response.statusCode = 503;
          } else {
            data = {
              'providers': {provider: providerData()},
            };
          }
      }
      if (segments.length == 3 &&
          segments.first == 'proxies' &&
          segments.last == 'delay') {
        if (segments[1] == 'static-node') {
          staticCalls++;
          data = {'delay': 31};
        } else {
          wrongGlobalCalls++;
          request.response.statusCode = 404;
        }
      }
      if (segments.length >= 3 &&
          segments[0] == 'providers' &&
          segments[1] == 'proxies') {
        expect(segments[2], provider);
        expect(request.headers.value('Authorization'), 'Bearer fixture-key');
        if (segments.length == 3) data = providerData();
        if (segments.length == 4 && segments.last == 'healthcheck') {
          providerChecks++;
          checked = true;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          request.response.statusCode = 204;
        }
        if (segments.length == 5 && segments.last == 'healthcheck') {
          final name = segments[3];
          singleCalls.update(name, (v) => v + 1, ifAbsent: () => 1);
          expect(
            request.uri.queryParameters['url'],
            'http://health.example/generate_204',
          );
          expect(request.uri.queryParameters['timeout'], '5000');
          if (legacy) {
            request.response.statusCode = 404;
          } else {
            data = {'delay': 27};
          }
        }
      }
      try {
        if (request.response.statusCode != 204) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(data));
        }
        await request.response.close();
      } on SocketException {
        /* The client may cancel the fixture session. */
      }
    });
    await c.connect('http://127.0.0.1:${server.port}', 'fixture-key');
    expect(c.connected, isTrue);
  }

  Future<void> close() async {
    closing = true;
    c.dispose();
    for (final socket in List<WebSocket>.of(sockets)) {
      await socket.close();
    }
    await server.close(force: true);
  }
}

void main() {
  test(
    'provider-only nodes load metadata and test through their provider route',
    () async {
      final fixture = _ProviderFixture();
      await fixture.start();
      addTearDown(fixture.close);
      final c = fixture.c;
      expect(c.proxies[fixture.names.first]!.type, 'Trojan');
      expect(
        c.proxies[fixture.names.first]!.providerName,
        _ProviderFixture.provider,
      );
      expect(c.canTest(fixture.names.first), isTrue);
      expect(c.delayFor('策略 / 组'), 15);
      expect(c.proxies['empty-selector']!.isGroup, isTrue);
      expect(c.proxies['static-node']!.type, 'Trojan');
      await c.testAllDelays();
      expect(c.testTotal, 9);
      expect(c.testCompleted, 9);
      expect(c.testFailures, 0);
      expect(fixture.singleCalls.length, 8);
      expect(fixture.singleCalls.values.every((n) => n == 1), isTrue);
      expect(fixture.staticCalls, 1);
      expect(fixture.wrongGlobalCalls, 0);
      expect(c.delayFor(fixture.names.first), 27);
    },
  );
  test(
    'single provider node test leaves group selection and other nodes unchanged',
    () async {
      final fixture = _ProviderFixture();
      await fixture.start();
      addTearDown(fixture.close);
      await fixture.c.testNodeDelay(fixture.names[1]);
      expect(fixture.singleCalls, {fixture.names[1]: 1});
      expect(fixture.providerChecks, 0);
      expect(fixture.wrongGlobalCalls, 0);
      expect(fixture.c.proxies['策略 / 组']!.now, fixture.names.first);
      expect(fixture.c.delayFor(fixture.names.first), 15);
      expect(fixture.c.delayFor(fixture.names[1]), 27);
    },
  );
  test(
    'old kernels fall back to one health check per provider for test-all',
    () async {
      final fixture = _ProviderFixture()..legacy = true;
      await fixture.start();
      addTearDown(fixture.close);
      await fixture.c.testAllDelays();
      expect(fixture.providerChecks, 1);
      expect(fixture.c.testTotal, 9);
      expect(fixture.c.testCompleted, 9);
      expect(fixture.c.testFailures, 0);
      expect(fixture.c.testTimeouts, 1);
      expect(fixture.c.delayFor(fixture.names.first), 50);
      expect(fixture.c.delayFor(fixture.names.last), 0);
      expect(fixture.wrongGlobalCalls, 0);
    },
  );
  test(
    'unsupported single-node API reports the limitation without testing other nodes',
    () async {
      final fixture = _ProviderFixture()..legacy = true;
      await fixture.start();
      addTearDown(fixture.close);
      await fixture.c.testNodeDelay(fixture.names.first);
      expect(fixture.c.testFailures, 1);
      expect(
        fixture.c.delayErrors[fixture.names.first],
        contains('不支持订阅节点单独测速'),
      );
      expect(fixture.providerChecks, 0);
    },
  );
  test(
    'refresh updates provider history and removes stale provider nodes',
    () async {
      final fixture = _ProviderFixture();
      await fixture.start();
      addTearDown(fixture.close);
      final removed = fixture.names.removeLast();
      fixture.checked = true;
      await fixture.c.refresh();
      expect(fixture.c.proxies.containsKey(removed), isFalse);
      expect(fixture.c.proxies[fixture.names.first]!.type, 'VMess');
      expect(fixture.c.delayFor(fixture.names.first), 50);
      expect(fixture.c.proxies['static-node']!.type, 'Trojan');
      expect(fixture.c.groups.map((g) => g.name), ['策略 / 组', 'empty-selector']);
    },
  );
}
