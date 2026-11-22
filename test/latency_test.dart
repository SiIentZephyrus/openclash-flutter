import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclash_client/dashboard_controller.dart';

class _ControllerFixture {
  final controller = DashboardController();
  late HttpServer server;
  final sockets = <WebSocket>[];
  final calls = <String, int>{};
  int active = 0, peak = 0, selections = 0;
  Completer<void>? hold;
  bool closing = false;

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
      Object data = {};
      final path = request.uri.path;
      if (request.method == 'PUT') selections++;
      if (path == '/version') data = {'version': 'test'};
      if (path == '/configs') data = {'mode': 'rule'};
      if (path == '/rules') data = {'rules': []};
      if (path == '/proxies') {
        data = {
          'proxies': {
            'Group A': {
              'type': 'Selector',
              'all': [
                'Group B',
                ...List.generate(12, (i) => '节点 / $i'),
                'DIRECT',
                'REJECT',
              ],
              'now': '节点 / 0',
            },
            'Group B': {
              'type': 'Selector',
              'all': ['Group A', '节点 / 0', '节点 / 1'],
              'now': '节点 / 1',
            },
            'DIRECT': {'type': 'Direct'},
            'REJECT': {'type': 'Reject'},
            for (var i = 0; i < 12; i++)
              '节点 / $i': {'type': 'Trojan', 'history': []},
          },
        };
      }
      if (request.uri.pathSegments.last == 'delay') {
        expect(request.headers.value('Authorization'), 'Bearer fixture-secret');
        expect(request.uri.queryParameters['timeout'], '5000');
        final name = request.uri.pathSegments[1];
        calls.update(name, (value) => value + 1, ifAbsent: () => 1);
        active++;
        peak = max(peak, active);
        if (hold != null) await hold!.future;
        await Future<void>.delayed(const Duration(milliseconds: 25));
        active--;
        if (name == '节点 / 10') {
          request.response.statusCode = 504;
        } else if (name == '节点 / 11') {
          request.response.statusCode = 401;
        } else {
          data = {'delay': 42};
        }
      }
      try {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(data));
        await request.response.close();
      } on SocketException {
        /* Session cancellation may close a request. */
      }
    });
    await controller.connect(
      'http://127.0.0.1:${server.port}',
      'fixture-secret',
    );
    expect(controller.connected, isTrue);
  }

  Future<void> close() async {
    closing = true;
    if (hold != null && !hold!.isCompleted) hold!.complete();
    controller.dispose();
    for (final socket in List<WebSocket>.of(sockets)) {
      await socket.close();
    }
    await server.close(force: true);
  }
}

void main() {
  test('single-node latency test does not change group selection', () async {
    final fixture = _ControllerFixture();
    await fixture.start();
    addTearDown(fixture.close);
    final c = fixture.controller;
    await c.testNodeDelay('节点 / 1');
    expect(fixture.calls, {'节点 / 1': 1});
    expect(fixture.selections, 0);
    expect(c.proxies['Group A']!.now, '节点 / 0');
    expect(c.delayFor('节点 / 1'), 42);
    expect(c.delayFor('Group B'), 42);
    expect(c.testCompleted, 1);
    expect(c.testing, isFalse);
  });
  test(
    'test-all deduplicates physical nodes bounds concurrency and distinguishes failures',
    () async {
      final fixture = _ControllerFixture();
      await fixture.start();
      addTearDown(fixture.close);
      final c = fixture.controller;
      await c.testAllDelays();
      expect(fixture.calls.length, 12);
      expect(fixture.calls.values.every((count) => count == 1), isTrue);
      expect(fixture.peak, inInclusiveRange(2, 6));
      expect(fixture.calls.containsKey('Group A'), isFalse);
      expect(fixture.calls.containsKey('DIRECT'), isFalse);
      expect(c.testCompleted, 12);
      expect(c.testTotal, 12);
      expect(c.testTimeouts, 1);
      expect(c.testFailures, 1);
      expect(c.proxies['节点 / 10']!.delay, 0);
      expect(c.delayErrors['节点 / 11'], contains('认证失败'));
      expect(c.proxies['节点 / 11']!.delay, isNull);
      expect(c.testingNodes, isEmpty);
      c.proxies['Group B']!.now = '节点 / 11';
      expect(c.delayErrorFor('Group B'), contains('认证失败'));
    },
  );
  test(
    'group testing terminates cycles and measures shared members only once',
    () async {
      final fixture = _ControllerFixture();
      await fixture.start();
      addTearDown(fixture.close);
      await fixture.controller.testDelay(
        fixture.controller.proxies['Group A']!,
      );
      expect(fixture.calls.length, 14);
      expect(fixture.calls.values.every((count) => count == 1), isTrue);
      expect(fixture.calls.containsKey('REJECT'), isFalse);
      expect(fixture.controller.delayFor('Group A'), 42);
    },
  );
  test('changing controller session cancels queued latency updates', () async {
    final fixture = _ControllerFixture();
    await fixture.start();
    addTearDown(fixture.close);
    fixture.hold = Completer<void>();
    final c = fixture.controller;
    final job = c.testAllDelays();
    for (var i = 0; i < 100 && fixture.calls.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    c.disconnect();
    fixture.hold!.complete();
    await job;
    expect(c.connected, isFalse);
    expect(c.testing, isFalse);
    expect(c.testTotal, 0);
    expect(c.delayErrors, isEmpty);
    expect(fixture.calls.length, lessThanOrEqualTo(6));
    expect(c.proxies.containsKey('节点 / 0'), isFalse);
  });
}
