import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openclash_client/clash_api.dart';
import 'package:openclash_client/dashboard_controller.dart';
import 'package:openclash_client/delay_settings.dart';
import 'package:openclash_client/main.dart';
import 'package:openclash_client/models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fixture_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'provider updates refresh nodes and rule counts, including encoded names',
    () async {
      var proxyUpdated = false;
      var ruleUpdated = false;
      final paths = <String>[];
      const proxyName = '香港 / 常用';
      const ruleName = '应用 #1';
      final c = controllerWith((request) async {
        final path = request.url.path;
        paths.add(path);
        if (request.method == 'PUT') {
          final name = request.url.pathSegments.last;
          if (name == proxyName) proxyUpdated = true;
          if (name == ruleName) ruleUpdated = true;
          return http.Response('', proxyUpdated || ruleUpdated ? 204 : 404);
        }
        return jsonResponse(switch (path) {
          '/providers/proxies' => {
            'providers': {
              proxyName: {
                'vehicleType': 'HTTP',
                'updatedAt': '2026-01-01T12:00:00Z',
                'proxies': [
                  {'name': proxyUpdated ? 'new' : 'old', 'type': 'Trojan'},
                ],
              },
            },
          },
          '/providers/rules' => {
            'providers': {
              ruleName: {'ruleCount': ruleUpdated ? 20 : 10},
              'inline': {'ruleCount': 1, 'vehicleType': 'Inline'},
            },
          },
          '/rules' => {
            'rules': [
              {'type': 'MATCH'},
            ],
          },
          _ => initialResponse(path),
        });
      });
      addTearDown(c.dispose);
      await connect(c);
      final proxy = c.providersFor(ProviderKind.proxies).single;
      expect(proxy.count, 1);
      expect(proxy.updatedAt?.toUtc().hour, 12);
      await c.updateProvider(proxy);
      expect(c.proxies.keys, contains('new'));
      expect(c.proxies.keys, isNot(contains('old')));
      await c.loadProviders(ProviderKind.rules);
      final rules = c.providersFor(ProviderKind.rules);
      expect(rules.first.count, 10);
      expect(rules.last.canUpdate, isFalse);
      await c.updateProvider(rules.first);
      expect(c.providersFor(ProviderKind.rules).first.count, 20);
      expect(paths, contains('/rules'));
    },
  );

  test(
    'saved delay preferences reach the API and keep the provider URL',
    () async {
      final queries = <Map<String, String>>[];
      final c = controllerWith((request) async {
        final path = request.url.path;
        if (path.endsWith('/delay') || path.endsWith('/healthcheck')) {
          queries.add(request.url.queryParameters);
          return jsonResponse({'delay': 25});
        }
        return jsonResponse(switch (path) {
          '/proxies' => {
            'proxies': {
              'direct-node': {'type': 'Trojan'},
            },
          },
          '/providers/proxies' => {
            'providers': {
              'p': {
                'testUrl': 'https://health.example/204',
                'proxies': [
                  {'name': 'provider-node', 'type': 'Trojan'},
                ],
              },
            },
          },
          _ => initialResponse(path),
        });
      });
      addTearDown(c.dispose);
      const settings = DelaySettings(
        url: 'https://custom.example/ping?x=1',
        timeoutMs: 2000,
      );
      await c.saveDelaySettings(settings);
      expect((await DelaySettings.load()).url, settings.url);
      await connect(c);
      await c.testNodeDelay('direct-node');
      await c.testNodeDelay('provider-node');
      expect(queries, [
        {'url': settings.url, 'timeout': '2000'},
        {'url': 'https://health.example/204', 'timeout': '2000'},
      ]);
    },
  );

  test(
    'closing every connection retains searchable history and diagnosis classifies errors',
    () async {
      var authFails = false;
      var networkFails = false;
      var closed = false;
      final c = controllerWith((request) async {
        if (networkFails) throw http.ClientException('offline');
        if (authFails) return http.Response('{}', 401);
        if (request.method == 'DELETE' && request.url.path == '/connections') {
          closed = true;
          return http.Response('', 204);
        }
        return jsonResponse(initialResponse(request.url.path));
      });
      addTearDown(c.dispose);
      await connect(c);
      final last = c.lastConnected;
      c.connections = [
        {
          'id': 'one',
          'start': DateTime.now()
              .subtract(const Duration(seconds: 30))
              .toIso8601String(),
        },
        {'id': 'two'},
      ];
      await c.closeAllConnections();
      expect(closed, isTrue);
      expect(c.connections, isEmpty);
      expect(c.recentConnections.map((item) => item['id']), ['one', 'two']);
      expect(
        c
            .connectionDuration(c.recentConnections.first, active: false)
            ?.inSeconds,
        closeTo(30, 1),
      );
      authFails = true;
      await connect(c);
      expect(c.connectionFailure, ApiFailure.authentication);
      expect(c.lastConnected, last);
      networkFails = true;
      await connect(c);
      expect(c.connectionFailure, ApiFailure.unreachable);
    },
  );

  testWidgets(
    'dark mode and Android export use the current filtered snapshot',
    (tester) async {
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      const channel = MethodChannel('openclash/log_export');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final c = FixtureController();
      await tester.pumpWidget(OpenClashApp(controller: c));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(NavigationBar))).brightness,
        Brightness.dark,
      );
      await tester.tap(find.text('日志').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('log-search')),
        'upstream timeout',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('导出筛选日志'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存为文本文件'));
      await tester.pumpAndSettle();
      expect(calls.single.method, 'save');
      final text = calls.single.arguments['text'] as String;
      expect(text.trim().split('\n'), hasLength(1));
      expect(text, contains('upstream timeout'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('connection details and filters work together on a phone', (
    tester,
  ) async {
    final c = FixtureController();
    c.connections = [
      {
        'id': 'one',
        'metadata': {
          'host': 'first.example',
          'sourceIP': '192.168.1.10',
          'sourcePort': '1234',
          'destinationIP': '2001:db8::1',
          'destinationPort': '443',
        },
        'rule': 'DomainSuffix',
        'rulePayload': 'example',
        'chains': ['香港 · HKT 01', '节点选择'],
      },
      {
        'id': 'two',
        'metadata': {'host': 'second.example', 'sourceIP': '192.168.1.11'},
        'chains': ['日本 · Tokyo 01', '流媒体'],
      },
    ];
    await tester.pumpWidget(OpenClashApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('筛选连接'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部策略组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('节点选择').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(find.text('second.example'), findsNothing);
    await tester.tap(find.text('first.example'));
    await tester.pumpAndSettle();
    expect(find.text('192.168.1.10:1234'), findsOneWidget);
    expect(find.text('2001:db8::1'), findsOneWidget);
    expect(find.text('DomainSuffix · example'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}

DashboardController controllerWith(
  Future<http.Response> Function(http.Request) handle,
) => DashboardController(
  apiFactory: (address, secret) =>
      ClashApi(address, secret, client: MockClient(handle)),
);

Future<void> connect(DashboardController controller) async {
  await controller.setBackgrounded(true);
  await controller.connect('http://controller.example', '');
}

Map<String, dynamic> initialResponse(String path) => switch (path) {
  '/version' => {'version': 'test'},
  '/configs' => {'mode': 'rule'},
  '/proxies' => {'proxies': <String, dynamic>{}},
  '/providers/proxies' => {'providers': <String, dynamic>{}},
  _ => {},
};

http.Response jsonResponse(Map<String, dynamic> data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
