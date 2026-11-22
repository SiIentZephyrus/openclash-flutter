import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'clash_api.dart';
import 'models.dart';
import 'controller_store.dart';
import 'group_traffic.dart';

class DashboardController extends ChangeNotifier {
  DashboardController({
    ControllerStore? store,
    ClashApi Function(String, String)? apiFactory,
  }) : _store = store ?? LocalControllerStore(),
       _apiFactory = apiFactory ?? ClashApi.new;
  final ControllerStore _store;
  final ClashApi Function(String, String) _apiFactory;
  ControllerProfile? _profile;
  Future<void>? _initialization;
  bool initialized = false, hasProfile = false, savingProfile = false;
  bool connected = false, connecting = false, testing = false;
  String address = '', version = '—', mode = 'rule';
  String get secret => _profile?.secret ?? '';
  String? error;
  Map<String, ProxyNode> proxies = {};
  final Map<String, ProxyNode> _providerNodes = {};
  final Set<String> _rootProxyNames = {};
  String? providerError;
  List<LogEntry> logs = [];
  List<Map<String, dynamic>> connections = [], rules = [];
  final _groupTraffic = GroupTrafficTracker();
  final _trafficClock = Stopwatch()..start();
  Timer? _connectionTrafficExpiry;
  TrafficRate? trafficFor(String groupName) => _groupTraffic.rateFor(groupName);
  num up = 0, down = 0, uploadTotal = 0, downloadTotal = 0, memory = 0;
  List<double> downloadHistory = List.filled(40, 0),
      uploadHistory = List.filled(40, 0);
  final Set<String> switching = {};
  final Set<String> testingNodes = {};
  final Map<String, String> delayErrors = {};
  int testCompleted = 0, testTotal = 0, testFailures = 0, testTimeouts = 0;
  String testLabel = '';
  String get testSummary =>
      '测速完成：成功 ${testCompleted - testFailures - testTimeouts}，超时 $testTimeouts，失败 $testFailures${testFailures > 0 && delayErrors.isNotEmpty ? '；${delayErrors.values.first}' : ''}';

  bool canTest(String name) {
    final node = proxies[name];
    return node != null &&
        !const [
          'direct',
          'reject',
          'rejectdrop',
          'pass',
          'compatible',
          'dns',
        ].contains(node.type.toLowerCase()) &&
        !const [
          'DIRECT',
          'REJECT',
          'REJECT-DROP',
          'PASS',
          'COMPATIBLE',
        ].contains(name);
  }

  int? delayFor(String name, [Set<String>? visited]) {
    final seen = visited ?? <String>{};
    if (!seen.add(name)) return null;
    final node = proxies[name];
    if (node == null || delayErrors.containsKey(name)) return null;
    if (node.delay != null) return node.delay;
    return node.now.isEmpty ? null : delayFor(node.now, seen);
  }

  String? delayErrorFor(String name, [Set<String>? visited]) {
    final seen = visited ?? <String>{};
    if (!seen.add(name)) return null;
    if (delayErrors.containsKey(name)) return delayErrors[name];
    final node = proxies[name];
    if (node == null || node.delay != null || node.now.isEmpty) return null;
    return delayErrorFor(node.now, seen);
  }

  final Set<String> liveStreams = {};
  final List<WebSocketChannel> _sockets = [];
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<Timer> _retries = [];
  ClashApi? _api;
  Timer? _reconnectTimer;
  int _generation = 0;
  bool _disposed = false;
  bool _autoReconnectPaused = false;
  List<ProxyNode> get groups {
    // /proxies is an unordered object. GLOBAL.all retains the config order.
    // Keep groups missing from that list in their original response order.
    final ordered = <String, ProxyNode>{};
    final global = proxies['GLOBAL'];
    if (mode == 'global' && global?.isGroup == true && !global!.hidden) {
      ordered['GLOBAL'] = global;
    }
    for (final name in global?.members ?? const <String>[]) {
      final group = proxies[name];
      if (name != 'GLOBAL' && group?.isGroup == true && !group!.hidden) {
        ordered[name] = group;
      }
    }
    for (final group in proxies.values) {
      if (group.name != 'GLOBAL' && group.isGroup && !group.hidden) {
        ordered.putIfAbsent(group.name, () => group);
      }
    }
    return ordered.values.toList();
  }

  int get nodeCount => proxies.values
      .where(
        (p) =>
            !p.isGroup &&
            !['Direct', 'Reject', 'DIRECT', 'REJECT'].contains(p.type),
      )
      .length;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _stop() {
    _generation++;
    _connectionTrafficExpiry?.cancel();
    _groupTraffic.reset();
    _reconnectTimer?.cancel();
    for (final timer in _retries) {
      timer.cancel();
    }
    _retries.clear();
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();
    for (final socket in _sockets) {
      unawaited(socket.sink.close());
    }
    _sockets.clear();
    liveStreams.clear();
    _api?.close();
    _api = null;
    switching.clear();
    testing = false;
    testingNodes.clear();
    delayErrors.clear();
    testCompleted = testTotal = testFailures = testTimeouts = 0;
    testLabel = '';
  }

  void _resetMetrics() {
    up = down = uploadTotal = downloadTotal = memory = 0;
    downloadHistory = List.filled(40, 0);
    uploadHistory = List.filled(40, 0);
    connections = [];
    rules = [];
    logs = [];
    proxies = {};
    _providerNodes.clear();
    _rootProxyNames.clear();
    providerError = null;
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      final profile = await _store.read();
      if (_disposed) return;
      if (profile != null) {
        _profile = profile;
        hasProfile = true;
        address = profile.address;
      } else {
        address = await _store.addressHint() ?? '';
      }
    } catch (_) {
      if (!_disposed) error = '无法读取本地控制器配置，请重新配置并保存';
    }
    if (_disposed) return;
    initialized = true;
    _emit();
    if (_profile != null) await reconnect();
  }

  Future<List<Map<String, dynamic>>> _fetchInitial(ClashApi api) =>
      Future.wait([
        api.request('GET', '/version'),
        api.request('GET', '/configs'),
        api.request('GET', '/proxies'),
        _fetchProviders(api),
      ]);

  void _applyInitial(List<Map<String, dynamic>> values) {
    version = values[0]['version']?.toString() ?? 'Mihomo';
    mode = values[1]['mode']?.toString() ?? 'rule';
    _readProxies(values[2]);
    _readProviders(values[3]);
    connected = true;
    for (final path in ['/traffic', '/memory', '/connections', '/logs']) {
      unawaited(_listen(path, _generation));
    }
    unawaited(loadRules());
  }

  Future<bool> saveController(String endpoint, String secret) async {
    if (savingProfile || connecting) return false;
    final profile = ControllerProfile(endpoint, secret);
    final candidate = _apiFactory(profile.address, profile.secret);
    savingProfile = true;
    error = null;
    _emit();
    var adopted = false;
    try {
      final values = await _fetchInitial(candidate);
      // Parse before saving so a malformed controller response cannot replace
      // the user's last working profile.
      final entries = values[2]['proxies'] as Map<String, dynamic>;
      for (final entry in entries.entries) {
        ProxyNode.fromJson(entry.key, entry.value as Map<String, dynamic>);
      }
      if (_disposed) return false;
      try {
        await _store.save(profile);
      } catch (_) {
        throw ApiException('无法保存到本机，请重试；原有配置未更改');
      }
      if (_disposed) return false;
      _stop();
      _resetMetrics();
      _profile = profile;
      hasProfile = true;
      address = profile.address;
      _autoReconnectPaused = false;
      _api = candidate;
      adopted = true;
      _applyInitial(values);
      return true;
    } catch (e) {
      if (!_disposed) {
        error = e is ApiException ? e.message : '连接失败，请检查控制器地址、密钥和返回数据';
      }
      return false;
    } finally {
      if (!adopted) candidate.close();
      if (!_disposed) {
        savingProfile = false;
        if (!adopted &&
            !_autoReconnectPaused &&
            !connected &&
            _profile != null) {
          _retrySavedLater();
        }
        _emit();
      }
    }
  }

  Future<void> reconnect() async {
    final profile = _profile;
    if (profile != null && !connecting && !savingProfile) {
      await connect(profile.address, profile.secret);
    }
  }

  void _retrySavedLater() {
    _reconnectTimer?.cancel();
    if (_disposed || _autoReconnectPaused) return;
    _reconnectTimer = Timer(
      const Duration(seconds: 5),
      () => unawaited(reconnect()),
    );
  }

  void pauseAutoReconnect() {
    _autoReconnectPaused = true;
    _reconnectTimer?.cancel();
    if (connecting) {
      _stop();
      connecting = false;
      connected = false;
      _emit();
    }
  }

  void resumeAutoReconnect() {
    _autoReconnectPaused = false;
    if (!connected && _profile != null) _retrySavedLater();
  }

  void disconnect() {
    _stop();
    _resetMetrics();
    connected = false;
    connecting = false;
    _emit();
  }

  Future<void> connect(String endpoint, String secret) async {
    if (savingProfile || _disposed) return;
    final api = _apiFactory(endpoint, secret);
    _stop();
    _resetMetrics();
    _api = api;
    final generation = _generation;
    address = endpoint.trim();
    connected = false;
    connecting = true;
    error = null;
    version = '—';
    _emit();
    try {
      final values = await _fetchInitial(api);
      if (generation != _generation) return;
      _applyInitial(values);
    } catch (e) {
      if (generation == _generation) {
        error = e.toString();
        connected = false;
      }
    } finally {
      if (generation == _generation) {
        connecting = false;
        if (!connected && _profile?.address == address && !_disposed) {
          _retrySavedLater();
        }
        _emit();
      }
    }
  }

  Future<void> _listen(String path, int generation) async {
    if (generation != _generation || _api == null) return;
    WebSocketChannel? channel;
    StreamSubscription<dynamic>? subscription;
    var retryScheduled = false;
    void retry() {
      if (retryScheduled || generation != _generation || _disposed) return;
      retryScheduled = true;
      liveStreams.remove(path);
      if (path == '/connections') {
        _connectionTrafficExpiry?.cancel();
        _groupTraffic.reset();
      }
      _emit();
      if (channel != null) {
        _sockets.remove(channel);
        unawaited(channel.sink.close());
      }
      if (subscription != null) {
        _subscriptions.remove(subscription);
        unawaited(subscription.cancel());
      }
      late Timer timer;
      timer = Timer(const Duration(seconds: 4), () {
        _retries.remove(timer);
        unawaited(_listen(path, generation));
      });
      _retries.add(timer);
    }

    try {
      channel = _api!.socket(path, path == '/logs' ? {'level': 'debug'} : {});
      _sockets.add(channel);
      subscription = channel.stream.listen(
        (event) {
          if (generation != _generation) return;
          try {
            final data = jsonDecode(event as String) as Map<String, dynamic>;
            if (path == '/traffic') {
              up = data['up'] as num? ?? 0;
              down = data['down'] as num? ?? 0;
              _history();
            }
            if (path == '/memory') memory = data['inuse'] as num? ?? 0;
            if (path == '/connections') {
              final nextConnections = (data['connections'] as List? ?? [])
                  .cast<Map<String, dynamic>>();
              _groupTraffic.update(
                nextConnections,
                timestamp: _trafficClock.elapsed,
              );
              connections = nextConnections;
              uploadTotal = data['uploadTotal'] as num? ?? 0;
              downloadTotal = data['downloadTotal'] as num? ?? 0;
              _connectionTrafficExpiry?.cancel();
              _connectionTrafficExpiry = Timer(const Duration(seconds: 4), () {
                if (generation != _generation || _disposed) return;
                _groupTraffic.reset();
                _emit();
              });
            }
            if (path == '/logs') _addLog(LogEntry.fromJson(data));
            liveStreams.add(path);
            _emit();
          } catch (_) {
            /* Ignore malformed frames, keep the stream alive. */
          }
        },
        onError: (Object _) => retry(),
        onDone: retry,
      );
      _subscriptions.add(subscription);
      await channel.ready.timeout(const Duration(seconds: 12));
      if (generation == _generation && !retryScheduled) {
        liveStreams.add(path);
        _emit();
      }
    } catch (_) {
      retry();
    }
  }

  void _history() {
    downloadHistory = [...downloadHistory.skip(1), down / 1048576];
    uploadHistory = [...uploadHistory.skip(1), up / 1048576];
  }

  void _addLog(LogEntry log) {
    logs.add(log);
    if (logs.length > 1500) logs.removeRange(0, logs.length - 1500);
  }

  void _readProxies(Map<String, dynamic> data) {
    proxies = (data['proxies'] as Map<String, dynamic>).map(
      (name, value) => MapEntry(
        name,
        ProxyNode.fromJson(name, value as Map<String, dynamic>),
      ),
    );
    _rootProxyNames
      ..clear()
      ..addAll(proxies.keys);
    for (final entry in _providerNodes.entries) {
      proxies.putIfAbsent(entry.key, () => entry.value);
    }
  }

  Future<Map<String, dynamic>> _fetchProviders(ClashApi api) async {
    try {
      return await api.request('GET', '/providers/proxies');
    } on ApiException catch (e) {
      if (e.statusCode == 404) return {'providers': <String, dynamic>{}};
      return {'providerError': '订阅节点读取失败：${e.message}'};
    } catch (_) {
      return {'providerError': '订阅节点数据无效，请刷新重试'};
    }
  }

  void _readProviders(Map<String, dynamic> data) {
    if (data['providerError'] != null) {
      providerError = data['providerError'].toString();
      return;
    }
    final result = <String, ProxyNode>{};
    try {
      final providers = data['providers'] as Map<String, dynamic>? ?? {};
      for (final entry in providers.entries) {
        final provider = entry.value as Map<String, dynamic>;
        for (final raw in provider['proxies'] as List? ?? []) {
          final json = raw as Map<String, dynamic>;
          final name = json['name'] as String;
          result.putIfAbsent(
            name,
            () => ProxyNode.fromJson(
              name,
              json,
              providerName: entry.key,
              testUrl: provider['testUrl'] as String?,
            ),
          );
        }
      }
    } catch (_) {
      providerError = '订阅节点数据无效，请刷新重试';
      return;
    }
    for (final name in _providerNodes.keys) {
      if (!_rootProxyNames.contains(name)) proxies.remove(name);
    }
    _providerNodes
      ..clear()
      ..addAll(result);
    for (final entry in result.entries) {
      proxies.putIfAbsent(entry.key, () => entry.value);
    }
    providerError = null;
  }

  Future<void> refresh() async {
    final generation = _generation;
    final results = await Future.wait([
      _api!.request('GET', '/proxies'),
      _fetchProviders(_api!),
    ]);
    if (generation == _generation) {
      _readProxies(results[0]);
      _readProviders(results[1]);
      _emit();
    }
  }

  Future<void> select(ProxyNode group, String name) async {
    if (!group.selectable || switching.contains(group.name)) return;
    final generation = _generation;
    switching.add(group.name);
    _emit();
    try {
      await _api!.request(
        'PUT',
        '/proxies/${Uri.encodeComponent(group.name)}',
        body: {'name': name},
      );
      if (generation != _generation) return;
      group.now = name;
      for (final proxy in proxies.values.where((p) => p.isGroup)) {
        proxy.delay = null;
        delayErrors.remove(proxy.name);
      }
    } finally {
      if (generation == _generation) {
        switching.remove(group.name);
        _emit();
      }
    }
  }

  Future<void> testNodeDelay(String name) => _runDelayTests([name], '单节点测速');

  Future<void> testDelay(ProxyNode group) {
    final targets = <String>{};
    void visit(String name) {
      if (!canTest(name) || !targets.add(name)) return;
      for (final member in proxies[name]!.members) {
        visit(member);
      }
    }

    visit(group.name);
    return _runDelayTests(
      targets,
      '${group.name} · 组内测速',
      allowProviderBatchFallback: true,
    );
  }

  Future<void> testAllDelays() => _runDelayTests(
    proxies.values
        .where((p) => !p.isGroup && canTest(p.name))
        .map((p) => p.name),
    '全部节点测速',
    allowProviderBatchFallback: true,
  );

  Future<void> testGroupDelays() =>
      _runDelayTests(groups.map((g) => g.name), '策略组测速');

  Future<void> _runDelayTests(
    Iterable<String> names,
    String label, {
    bool allowProviderBatchFallback = false,
  }) async {
    if (testing) return;
    if (!connected) throw ApiException('请先连接控制器');
    final targets = names.where(canTest).toSet().toList();
    if (targets.isEmpty) {
      throw ApiException(providerError ?? '没有可测速的节点，请刷新代理及订阅数据');
    }
    final generation = _generation;
    final api = _api;
    final providerChecks = <String, Future<Map<String, int?>>>{};
    testing = true;
    testLabel = label;
    testTotal = targets.length;
    testCompleted = testFailures = testTimeouts = 0;
    _emit();
    Future<int> providerBatchDelay(ProxyNode node) async {
      final provider = node.providerName!;
      final values = await providerChecks.putIfAbsent(provider, () async {
        final path = '/providers/proxies/${Uri.encodeComponent(provider)}';
        final nodeCount = _providerNodes.values
            .where((n) => n.providerName == provider)
            .length;
        await api!.request(
          'GET',
          '$path/healthcheck',
          timeout: Duration(seconds: 15 + ((nodeCount + 9) ~/ 10) * 5),
        );
        final result = await api.request('GET', path);
        return {
          for (final raw in result['proxies'] as List? ?? [])
            (raw['name'] as String): ProxyNode.fromJson(
              raw['name'] as String,
              raw as Map<String, dynamic>,
            ).delay,
        };
      });
      final delay = values[node.name];
      if (delay == null) throw ApiException('订阅集合未返回节点测速结果，请检查集合的健康检查配置');
      return delay;
    }

    Future<int> requestDelay(ProxyNode node) async {
      if (node.providerName != null &&
          providerChecks.containsKey(node.providerName)) {
        return providerBatchDelay(node);
      }
      final path = node.providerName == null
          ? '/proxies/${Uri.encodeComponent(node.name)}/delay'
          : '/providers/proxies/${Uri.encodeComponent(node.providerName!)}/${Uri.encodeComponent(node.name)}/healthcheck';
      final url = Uri.tryParse(node.testUrl ?? '');
      try {
        final result = await api!.request(
          'GET',
          path,
          query: {
            'url':
                url != null &&
                    ['http', 'https'].contains(url.scheme) &&
                    url.host.isNotEmpty
                ? url.toString()
                : 'https://www.gstatic.com/generate_204',
            'timeout': '5000',
          },
        );
        final value = result['delay'];
        if (value is! num || value < 0) throw ApiException('控制器未返回有效延迟');
        return value.toInt();
      } on ApiException catch (e) {
        if (node.providerName != null && e.statusCode == 404) {
          if (allowProviderBatchFallback) return providerBatchDelay(node);
          throw ApiException('当前内核不支持订阅节点单独测速，请使用全部节点测速或升级内核');
        }
        rethrow;
      }
    }

    Future<void> measure(String name) async {
      if (generation != _generation) return;
      testingNodes.add(name);
      delayErrors.remove(name);
      _emit();
      try {
        final delay = await requestDelay(proxies[name]!);
        if (generation != _generation) return;
        proxies[name]?.delay = delay;
        if (delay == 0) testTimeouts++;
      } catch (e) {
        if (generation != _generation) return;
        if (e is ApiException &&
            (e.statusCode == 504 || e.message.contains('超时'))) {
          proxies[name]?.delay = 0;
          testTimeouts++;
        } else {
          proxies[name]?.delay = null;
          delayErrors[name] = e.toString();
          testFailures++;
        }
      } finally {
        if (generation == _generation) {
          testingNodes.remove(name);
          testCompleted++;
          _emit();
        }
      }
    }

    try {
      // Bound requests to six at a time, deduplicated across nested groups.
      for (var i = 0; i < targets.length; i += 6) {
        if (generation != _generation) return;
        await Future.wait(targets.skip(i).take(6).map(measure));
      }
    } finally {
      if (generation == _generation) {
        testing = false;
        _emit();
      }
    }
  }

  Future<void> changeMode(String value) async {
    final generation = _generation;
    await _api!.request('PATCH', '/configs', body: {'mode': value});
    if (generation == _generation) {
      mode = value;
      _emit();
    }
  }

  Future<void> loadRules() async {
    if (_api == null) return;
    final generation = _generation;
    try {
      final data = await _api!.request('GET', '/rules');
      if (generation == _generation) {
        rules = (data['rules'] as List? ?? []).cast<Map<String, dynamic>>();
        _emit();
      }
    } catch (e) {
      if (generation == _generation) {
        _addLog(LogEntry('warning', '规则读取失败：$e'));
        _emit();
      }
    }
  }

  Future<void> closeConnection(String id) async {
    final generation = _generation;
    await _api!.request('DELETE', '/connections/${Uri.encodeComponent(id)}');
    if (generation == _generation) {
      connections.removeWhere((c) => c['id'] == id);
      _emit();
    }
  }

  void clearLogs() {
    logs.clear();
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    super.dispose();
  }
}
