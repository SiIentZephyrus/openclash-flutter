import 'dart:async';
import 'dart:math';
import 'package:openclash_client/dashboard_controller.dart';
import 'package:openclash_client/models.dart';
import 'package:openclash_client/group_traffic.dart';

// UI fixtures are test-only. Production has no sample data or demo mode.
class FixtureController extends DashboardController {
  int selectionCalls = 0;
  final trafficRates = <String, TrafficRate>{
    '节点选择': const TrafficRate(upload: 128 * 1024, download: 2.4 * 1048576),
    '流媒体': const TrafficRate(upload: 24 * 1024, download: 1.2 * 1048576),
  };
  @override
  TrafficRate? trafficFor(String groupName) =>
      trafficRates[groupName] ?? const TrafficRate();

  void updateTraffic(String groupName, TrafficRate rate) {
    trafficRates[groupName] = rate;
    notifyListeners();
  }

  FixtureController() {
    initialized = true;
    hasProfile = true;
    connected = true;
    address = 'http://127.0.0.1:9090';
    version = 'test-core';
    final names = [
      '香港 · HKT 01',
      '香港 · HKT 02',
      '日本 · Tokyo 01',
      '日本 · Osaka 02',
      '新加坡 · SG 01',
      '新加坡 · SG 02',
      '美国 · Los Angeles',
      '美国 · San Jose',
    ];
    final delays = [24, 36, 68, 82, 57, 63, 168, 0];
    for (var i = 0; i < names.length; i++) {
      proxies[names[i]] = ProxyNode(
        name: names[i],
        type: i % 3 == 0 ? 'Trojan' : 'Shadowsocks',
        delay: delays[i],
      );
    }
    proxies['DIRECT'] = ProxyNode(name: 'DIRECT', type: 'Direct');
    proxies['自动选择'] = ProxyNode(
      name: '自动选择',
      type: 'URLTest',
      members: names,
      now: names.first,
      delay: 24,
    );
    proxies['节点选择'] = ProxyNode(
      name: '节点选择',
      type: 'Selector',
      members: ['自动选择', ...names, 'DIRECT'],
      now: names.first,
    );
    proxies['流媒体'] = ProxyNode(
      name: '流媒体',
      type: 'Selector',
      members: names.take(6).toList(),
      now: names[2],
    );
    proxies['人工智能'] = ProxyNode(
      name: '人工智能',
      type: 'Selector',
      members: names.skip(2).toList(),
      now: names[4],
    );
    proxies['全球直连'] = ProxyNode(
      name: '全球直连',
      type: 'Selector',
      members: ['DIRECT', '节点选择'],
      now: 'DIRECT',
    );
    // Put the primary selector first in the navigation.
    proxies = {'节点选择': proxies['节点选择']!, ...proxies};
    memory = 48.6 * 1048576;
    uploadTotal = 136.8 * 1048576;
    downloadTotal = 2.34 * 1073741824;
    connections = List.generate(
      6,
      (i) => {
        'id': 'demo-$i',
        'metadata': {
          'host': [
            'github.com',
            'www.youtube.com',
            'api.openai.com',
            'www.google.com',
            'cdn.jsdelivr.net',
            'www.apple.com',
          ][i],
          'network': 'tcp',
          'sourceIP': '192.168.1.${100 + i}',
          'destinationPort': '443',
        },
        'chains': [names[i]],
        'rule': 'DomainSuffix',
        'upload': 2048 * (i + 1),
        'download': 358400 * (i + 1),
      },
    );
    rules = [
      {'type': 'DOMAIN-SUFFIX', 'payload': 'github.com', 'proxy': '节点选择'},
      {'type': 'GEOSITE', 'payload': 'youtube', 'proxy': '流媒体'},
      {'type': 'GEOSITE', 'payload': 'openai', 'proxy': '人工智能'},
      {'type': 'GEOIP', 'payload': 'CN', 'proxy': 'DIRECT'},
      {'type': 'MATCH', 'payload': '*', 'proxy': '节点选择'},
    ];
    logs = List.generate(
      18,
      (i) => LogEntry(
        i == 5 ? 'warning' : 'info',
        i == 5
            ? '[DNS] upstream timeout, retrying with fallback'
            : '[TCP] 192.168.1.${100 + i % 4}:52481 → ${['github.com:443', 'www.google.com:443', 'api.openai.com:443'][i % 3]} match DomainSuffix using 节点选择[香港 · HKT 01]',
        time: DateTime.now().subtract(Duration(seconds: 18 - i)),
      ),
    );
    downloadHistory = List.generate(
      40,
      (i) => 2 + sin(i * .7) * 1.1 + (i % 7) * .3,
    );
    uploadHistory = List.generate(40, (i) => .3 + sin(i * .4).abs() * .5);

    down = 3.8 * 1048576;
    up = 528 * 1024;
  }
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refresh() async {
    notifyListeners();
  }

  @override
  Future<void> select(ProxyNode group, String name) async {
    selectionCalls++;
    group.now = name;
    notifyListeners();
  }

  @override
  Future<void> changeMode(String value) async {
    mode = value;
    notifyListeners();
  }

  @override
  Future<void> loadRules() async {}
  @override
  Future<void> closeConnection(String id) async {
    connections.removeWhere((c) => c['id'] == id);
    notifyListeners();
  }

  Future<void> _measure(Iterable<String> names) async {
    testing = true;
    testTotal = names.length;
    testCompleted = 0;
    testingNodes.addAll(names);
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final name in names) {
      final node = proxies[name];
      if (node != null && node.delay != 0) node.delay = (node.delay ?? 30) + 1;
    }
    testCompleted = testTotal;
    testing = false;
    testingNodes.clear();
    notifyListeners();
  }

  @override
  Future<void> testNodeDelay(String name) => _measure([name]);
  @override
  Future<void> testAllDelays() => _measure(
    proxies.values
        .where((p) => !p.isGroup && canTest(p.name))
        .map((p) => p.name)
        .toList(),
  );
  @override
  Future<void> testDelay(ProxyNode group) =>
      _measure(group.members.where(canTest).toList());
}
