import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'clash_api.dart';
import 'models.dart';
import 'controller_store.dart';
import 'group_traffic.dart';
import 'connection_history.dart';
import 'delay_settings.dart';

enum DashboardSection {
  session,
  overview,
  proxies,
  providers,
  groupTraffic,
  connections,
  logs,
  streams,
}

class DashboardController extends ChangeNotifier {
  DashboardController({
    ControllerStore? store,
    ClashApi Function(String, String)? apiFactory,
  }) : _store = store ?? LocalControllerStore(),
       _apiFactory = apiFactory ?? ClashApi.new;
  final ControllerStore _store;
  final ClashApi Function(String, String) _apiFactory;
  final _updates = {
    for (final section in DashboardSection.values) section: ValueNotifier(0),
  };
  Listenable updatesFor(DashboardSection section) => _updates[section]!;
  ControllerProfiles? _savedControllers;
  ControllerProfile? get _profile => _savedControllers?.active;
  List<ControllerProfile> get savedControllers =>
      _savedControllers?.profiles ?? const [];
  String get controllerName => _profile?.name ?? '';
  Future<void>? _initialization;
  bool initialized = false, hasProfile = false, savingProfile = false;
  bool connected = false, connecting = false, testing = false;
  String address = '', version = '—', mode = 'rule';
  String get secret => _profile?.secret ?? '';
  String? error;
  ApiFailure? connectionFailure;
  final _lastConnected = <String, DateTime>{};
  DateTime? get lastConnected => _lastConnected[address];
  final interruptedStreams = <String>{};
  bool get backgrounded => _backgrounded;
  DelaySettings delaySettings = const DelaySettings();

  Future<void> saveDelaySettings(DelaySettings settings) async {
    await settings.save();
    if (_disposed) return;
    delaySettings = settings;
    _emit(const [DashboardSection.session]);
  }

  Map<String, ProxyNode> proxies = {};
  final Map<String, ProxyNode> _providerNodes = {};
  final Set<String> _rootProxyNames = {};
  String? providerError;
  final _providerSummaries = <ProviderKind, List<ProviderSummary>>{};
  final _providerUpdates = <(ClashApi, ProviderKind, String)>{};
  List<ProviderSummary> providersFor(ProviderKind kind) =>
      _providerSummaries[kind] ?? const [];
  List<LogEntry> logs = [];
  List<Map<String, dynamic>> rules = [];
  List<Map<String, dynamic>> _connections = [];
  final _connectionHistory = ConnectionHistory();
  Timer? _connectionHistoryExpiry;
  List<Map<String, dynamic>> get connections => _connections;
  List<Map<String, dynamic>> get recentConnections =>
      _connectionHistory.connections;
  Duration? connectionDuration(
    Map<String, dynamic> item, {
    required bool active,
  }) {
    final start = DateTime.tryParse('${item['start'] ?? ''}');
    final endedAt = _connectionHistory.endedAt('${item['id']}');
    if (start == null || (!active && endedAt == null)) return null;
    final elapsed =
        DateTime.now().difference(start) -
        (active ? Duration.zero : _trafficClock.elapsed - endedAt!);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  set connections(List<Map<String, dynamic>> value) {
    _connections = value;
    _connectionHistory.update(value, now: _trafficClock.elapsed);
  }

  void _startConnectionHistoryExpiry() {
    if (_disposed) return;
    _connectionHistoryExpiry ??= Timer.periodic(const Duration(seconds: 1), (
      _,
    ) {
      if (_connectionHistory.prune(_trafficClock.elapsed)) {
        _emit(const [DashboardSection.connections]);
      }
    });
  }

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
  bool testCancelled = false;
  String? testFirstError;
  int delayOrderRevision = 0;
  _DelayTestRun? _delayRun;
  final _retryTargets = <String>{};
  bool _retryAllowsProviderBatch = false;
  bool get canRetryDelays =>
      connected && !testing && _retryTargets.any(canTest);
  String get testSummary =>
      '测速完成：成功 ${testCompleted - testFailures - testTimeouts}，超时 $testTimeouts，失败 $testFailures${testFirstError == null ? '' : '；$testFirstError'}';

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
  int get sessionGeneration => _generation;
  bool _disposed = false;
  bool _autoReconnectPaused = false;
  bool _backgrounded = false;
  int _streamGeneration = 0;
  bool _liveUpdatesStarted = false;
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

  @override
  void notifyListeners() => _emit();

  void _emit([Iterable<DashboardSection> sections = DashboardSection.values]) {
    if (_disposed) return;
    for (final section in sections) {
      final update = _updates[section]!;
      update.value++;
    }
    super.notifyListeners();
  }

  void _stop() {
    _generation++;
    _delayRun?.cancel();
    _delayRun = null;
    _retryTargets.clear();
    _reconnectTimer?.cancel();
    _stopStreams();
    _api?.close();
    _api = null;
    switching.clear();
    testing = false;
    testCancelled = false;
    testFirstError = null;
    testingNodes.clear();
    delayErrors.clear();
    testCompleted = testTotal = testFailures = testTimeouts = 0;
    testLabel = '';
  }

  void _stopStreams() {
    _streamGeneration++;
    _liveUpdatesStarted = false;
    _connectionHistoryExpiry?.cancel();
    _connectionHistoryExpiry = null;
    _connectionTrafficExpiry?.cancel();
    _groupTraffic.reset();
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
    interruptedStreams.clear();
  }

  void _resetMetrics() {
    up = down = uploadTotal = downloadTotal = memory = 0;
    downloadHistory = List.filled(40, 0);
    uploadHistory = List.filled(40, 0);
    _connections = [];
    _connectionHistory.clear();
    rules = [];
    logs = [];
    proxies = {};
    _providerNodes.clear();
    _providerSummaries.clear();
    _rootProxyNames.clear();
    providerError = null;
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    unawaited(_loadDelaySettings());
    try {
      final saved = await _store.readProfiles();
      if (_disposed) return;
      if (saved != null) {
        _savedControllers = saved;
        hasProfile = true;
        address = saved.activeAddress;
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

  Future<void> _loadDelaySettings() async {
    final previous = delaySettings;
    final settings = await DelaySettings.load();
    if (_disposed || !identical(delaySettings, previous)) return;
    delaySettings = settings;
    _emit(const [DashboardSection.session]);
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
    connectionFailure = null;
    _lastConnected[address] = DateTime.now();
    _startLiveUpdates();
  }

  void _startLiveUpdates() {
    if (_backgrounded || _liveUpdatesStarted || _api == null) return;
    _liveUpdatesStarted = true;
    for (final path in ['/traffic', '/memory', '/connections', '/logs']) {
      unawaited(_listen(path, _streamGeneration));
    }
    unawaited(loadRules());
  }

  Future<bool> saveController(
    String endpoint,
    String secret, {
    String name = '',
    bool add = false,
  }) async {
    final profile = ControllerProfile(endpoint, secret, name: name);
    final replacing = add ? null : _savedControllers?.activeAddress;
    if (savedControllers.any(
      (saved) => saved.address == profile.address && saved.address != replacing,
    )) {
      throw ApiException('此地址已有配置，请从控制器列表切换');
    }
    final profiles = [
      for (final saved in savedControllers)
        if (saved.address == replacing) profile else saved,
      if (replacing == null) profile,
    ];
    return _activateController(ControllerProfiles(profiles, profile.address));
  }

  Future<bool> switchController(String address) async {
    if (address == _savedControllers?.activeAddress) return true;
    return _activateController(ControllerProfiles(savedControllers, address));
  }

  Future<void> removeController(String address) async {
    final saved = _savedControllers;
    if (savingProfile ||
        connecting ||
        saved == null ||
        address == saved.activeAddress) {
      return;
    }
    final remaining = saved.profiles.where(
      (profile) => profile.address != address,
    );
    final next = ControllerProfiles(remaining, saved.activeAddress);
    if (next.profiles.length == saved.profiles.length) return;
    savingProfile = true;
    _emit(const [DashboardSection.session]);
    try {
      await _store.saveProfiles(next);
      if (!_disposed) _savedControllers = next;
    } catch (_) {
      throw ApiException('无法删除本机配置，请重试');
    } finally {
      savingProfile = false;
      _emit(const [DashboardSection.session]);
      if (!_backgrounded && !connected) _retrySavedLater();
    }
  }

  Future<bool> _activateController(ControllerProfiles next) async {
    if (savingProfile || connecting) return false;
    final profile = next.active;
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
        await _store.saveProfiles(next);
      } catch (_) {
        throw ApiException('无法保存到本机，请重试；原有配置未更改');
      }
      if (_disposed) return false;
      _stop();
      _resetMetrics();
      _savedControllers = next;
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
    if (profile != null && !connecting && !savingProfile && !_backgrounded) {
      await connect(profile.address, profile.secret);
    }
  }

  void _retrySavedLater() {
    _reconnectTimer?.cancel();
    if (_disposed || _autoReconnectPaused || _backgrounded) return;
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

  Future<void> setBackgrounded(bool backgrounded) async {
    if (_disposed || _backgrounded == backgrounded) return;
    _backgrounded = backgrounded;
    if (backgrounded) {
      _reconnectTimer?.cancel();
      _stopStreams();
      up = down = 0;
      _emit(const [
        DashboardSection.overview,
        DashboardSection.groupTraffic,
        DashboardSection.logs,
        DashboardSection.streams,
      ]);
      return;
    }

    if (_connectionHistory.prune(_trafficClock.elapsed)) {
      _emit(const [DashboardSection.connections]);
    }
    if (!connected) {
      if (!_autoReconnectPaused) await reconnect();
      return;
    }
    final api = _api;
    if (api == null) return;
    _startLiveUpdates();
    if (savingProfile) return;
    final generation = _streamGeneration;
    bool current() =>
        !_disposed && !_backgrounded && generation == _streamGeneration;
    try {
      final values = await _fetchInitial(api);
      if (!current() || savingProfile) return;
      _applyInitial(values);
      _emit(const [
        DashboardSection.proxies,
        DashboardSection.providers,
        DashboardSection.streams,
      ]);
    } catch (e) {
      if (!current() || savingProfile) return;
      _stopStreams();
      connected = false;
      _recordConnectionFailure(e);
      _emit();
      _retrySavedLater();
    }
  }

  void disconnect() {
    _stop();
    _resetMetrics();
    connected = false;
    connecting = false;
    connectionFailure = null;
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
    connectionFailure = null;
    version = '—';
    _emit();
    try {
      final values = await _fetchInitial(api);
      if (generation != _generation) return;
      _applyInitial(values);
    } catch (e) {
      if (generation == _generation) {
        _recordConnectionFailure(e);
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

  void _recordConnectionFailure(Object failure) {
    error = failure.toString();
    connectionFailure = failure is ApiException
        ? failure.failure ??
              switch (failure.statusCode) {
                401 || 403 => ApiFailure.authentication,
                _ => ApiFailure.response,
              }
        : ApiFailure.response;
  }

  Future<void> _listen(String path, int generation) async {
    bool current() =>
        !_disposed && !_backgrounded && generation == _streamGeneration;
    if (!current() || _api == null) return;
    WebSocketChannel? channel;
    StreamSubscription<dynamic>? subscription;
    var retryScheduled = false;
    void streamStatusChanged() => _emit([
      DashboardSection.streams,
      if (path == '/logs') DashboardSection.logs,
      if (path == '/connections') DashboardSection.groupTraffic,
    ]);
    void retry() {
      if (retryScheduled || !current()) return;
      retryScheduled = true;
      liveStreams.remove(path);
      interruptedStreams.add(path);
      if (path == '/connections') {
        _connectionTrafficExpiry?.cancel();
        _groupTraffic.reset();
      }
      streamStatusChanged();
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
          if (!current() || retryScheduled) return;
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
              _startConnectionHistoryExpiry();
              uploadTotal = data['uploadTotal'] as num? ?? 0;
              downloadTotal = data['downloadTotal'] as num? ?? 0;
              _connectionTrafficExpiry?.cancel();
              _connectionTrafficExpiry = Timer(const Duration(seconds: 4), () {
                if (!current()) return;
                _groupTraffic.reset();
                _emit(const [DashboardSection.groupTraffic]);
              });
            }
            if (path == '/logs') _addLog(LogEntry.fromJson(data));
            final firstFrame = liveStreams.add(path);
            interruptedStreams.remove(path);
            _emit([
              if (path != '/logs') DashboardSection.overview,
              if (path == '/logs') DashboardSection.logs,
              if (path == '/connections') ...const [
                DashboardSection.connections,
                DashboardSection.groupTraffic,
              ],
              if (firstFrame) DashboardSection.streams,
            ]);
          } catch (_) {
            /* Ignore malformed frames, keep the stream alive. */
          }
        },
        onError: (Object _) => retry(),
        onDone: retry,
      );
      _subscriptions.add(subscription);
      await channel.ready.timeout(const Duration(seconds: 12));
      if (current() && !retryScheduled && liveStreams.add(path)) {
        interruptedStreams.remove(path);
        streamStatusChanged();
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
      final summaries = <ProviderSummary>[];
      for (final entry in providers.entries) {
        final provider = entry.value as Map<String, dynamic>;
        summaries.add(
          ProviderSummary(entry.key, ProviderKind.proxies, provider),
        );
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
      _providerSummaries[ProviderKind.proxies] = summaries;
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
      _emit(const [DashboardSection.proxies, DashboardSection.providers]);
    }
  }

  Future<void> loadProviders(ProviderKind kind) async {
    final api = _api;
    if (!connected || api == null) throw ApiException('请先连接控制器');
    final data = await api.request('GET', '/providers/${kind.path}');
    if (!identical(_api, api)) return;
    if (kind == ProviderKind.proxies) {
      _readProviders(data);
      if (providerError != null) throw ApiException(providerError!);
      _emit(const [DashboardSection.proxies, DashboardSection.providers]);
    } else {
      final entries = data['providers'] as Map<String, dynamic>;
      _providerSummaries[kind] = [
        for (final entry in entries.entries)
          ProviderSummary(entry.key, kind, entry.value as Map<String, dynamic>),
      ];
      _emit(const [DashboardSection.providers]);
    }
  }

  Future<void> updateProvider(ProviderSummary provider) async {
    final api = _api;
    if (!connected || api == null) throw ApiException('请先连接控制器');
    if (!provider.canUpdate) throw ApiException('此集合由内核管理');
    final key = (api, provider.kind, provider.name);
    if (!_providerUpdates.add(key)) throw ApiException('此集合正在更新');
    try {
      await api.request(
        'PUT',
        '/providers/${provider.kind.path}/${Uri.encodeComponent(provider.name)}',
        timeout: const Duration(seconds: 60),
      );
      if (!identical(_api, api)) return;
      try {
        if (provider.kind == ProviderKind.proxies) {
          await refresh();
          if (identical(_api, api) && providerError != null) {
            throw ApiException(providerError!);
          }
        } else {
          await loadProviders(ProviderKind.rules);
          if (identical(_api, api)) await loadRules();
        }
      } catch (e) {
        throw ApiException('已更新，但刷新列表失败：$e');
      }
    } finally {
      _providerUpdates.remove(key);
    }
  }

  Future<void> select(ProxyNode group, String name) async {
    if (!group.selectable || switching.contains(group.name)) return;
    final generation = _generation;
    switching.add(group.name);
    _emit(const [DashboardSection.proxies]);
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
      delayOrderRevision++;
    } finally {
      if (generation == _generation) {
        switching.remove(group.name);
        _emit(const [DashboardSection.proxies]);
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

  Future<void> retryFailedDelays() => _runDelayTests(
    _retryTargets,
    '重试失败或超时节点',
    allowProviderBatchFallback: _retryAllowsProviderBatch,
    retrying: true,
  );

  void cancelDelayTests() {
    final run = _delayRun;
    if (run == null || run.cancelled) return;
    testCancelled = true;
    run.cancel();
    _emit(const [DashboardSection.proxies]);
  }

  Future<void> _runDelayTests(
    Iterable<String> names,
    String label, {
    bool allowProviderBatchFallback = false,
    bool retrying = false,
  }) async {
    if (testing) return;
    if (!connected) throw ApiException('请先连接控制器');
    final targets = names.where(canTest).toSet().toList();
    if (targets.isEmpty) {
      throw ApiException(providerError ?? '没有可测速的节点，请刷新代理及订阅数据');
    }
    final api = _api!;
    final settings = delaySettings;
    final run = _delayRun = _DelayTestRun();
    bool active() => identical(_delayRun, run) && !run.cancelled;
    final providerChecks = <String, Future<Map<String, int?>>>{};
    if (!retrying) _retryTargets.clear();
    _retryAllowsProviderBatch = allowProviderBatchFallback;
    testing = true;
    testCancelled = false;
    testFirstError = null;
    testLabel = label;
    testTotal = targets.length;
    testCompleted = testFailures = testTimeouts = 0;
    void publish() => _emit(const [DashboardSection.proxies]);
    void scheduleUpdate() {
      run.updateTimer ??= Timer(const Duration(milliseconds: 80), () {
        run.updateTimer = null;
        if (active()) publish();
      });
    }

    Future<int> providerBatchDelay(ProxyNode node) async {
      final provider = node.providerName!;
      final values = await providerChecks.putIfAbsent(provider, () async {
        final path = '/providers/proxies/${Uri.encodeComponent(provider)}';
        final nodeCount = _providerNodes.values
            .where((n) => n.providerName == provider)
            .length;
        await api.request(
          'GET',
          '$path/healthcheck',
          timeout: Duration(seconds: 15 + ((nodeCount + 9) ~/ 10) * 5),
          abortTrigger: run.abort.future,
        );
        if (!active()) throw ApiException('测速已取消');
        final result = await api.request(
          'GET',
          path,
          abortTrigger: run.abort.future,
        );
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
      final url = node.testUrl?.trim() ?? '';
      try {
        final result = await api.request(
          'GET',
          path,
          abortTrigger: run.abort.future,
          timeout: Duration(seconds: 7, milliseconds: settings.timeoutMs),
          query: {
            'url': DelaySettings.supportsUrl(url) ? url : settings.url,
            'timeout': '${settings.timeoutMs}',
          },
        );
        final value = result['delay'];
        if (value is! num || value < 0) throw ApiException('控制器未返回有效延迟');
        return value.toInt();
      } on ApiException catch (e) {
        if (node.providerName != null && e.statusCode == 404) {
          if (allowProviderBatchFallback && active()) {
            return providerBatchDelay(node);
          }
          throw ApiException('当前内核不支持订阅节点单独测速，请使用全部节点测速或升级内核');
        }
        rethrow;
      }
    }

    Future<void> measure(String name) async {
      testingNodes.add(name);
      try {
        if (!canTest(name)) throw ApiException('节点已不在当前配置中');
        final delay = await requestDelay(proxies[name]!);
        if (!active()) return;
        proxies[name]?.delay = delay;
        delayErrors.remove(name);
        if (delay == 0) {
          testTimeouts++;
          _retryTargets.add(name);
        } else {
          _retryTargets.remove(name);
        }
      } catch (e) {
        if (!active()) return;
        _retryTargets.add(name);
        if (e is ApiException &&
            (e.statusCode == 504 || e.message.contains('超时'))) {
          proxies[name]?.delay = 0;
          delayErrors.remove(name);
          testTimeouts++;
        } else {
          proxies[name]?.delay = null;
          delayErrors[name] = e.toString();
          testFirstError ??= e.toString();
          testFailures++;
        }
      } finally {
        if (active()) {
          testingNodes.remove(name);
          testCompleted++;
          scheduleUpdate();
        }
      }
    }

    var next = 0;
    Future<void> worker() async {
      while (active() && next < targets.length) {
        await measure(targets[next++]);
      }
    }

    try {
      final workers = List.generate(
        targets.length.clamp(0, 6),
        (_) => worker(),
      );
      publish();
      await Future.wait(workers);
    } finally {
      run.updateTimer?.cancel();
      if (identical(_delayRun, run)) {
        _delayRun = null;
        testing = false;
        testingNodes.clear();
        delayOrderRevision++;
        publish();
      }
    }
  }

  Future<void> changeMode(String value) async {
    final generation = _generation;
    await _api!.request('PATCH', '/configs', body: {'mode': value});
    if (generation == _generation) {
      mode = value;
      _emit(const [DashboardSection.proxies]);
    }
  }

  Future<void> loadRules() async {
    if (_api == null) return;
    final generation = _generation;
    try {
      final data = await _api!.request('GET', '/rules');
      if (generation == _generation) {
        rules = (data['rules'] as List? ?? []).cast<Map<String, dynamic>>();
        _emit(const [DashboardSection.connections]);
      }
    } catch (e) {
      if (generation == _generation) {
        _addLog(LogEntry('warning', '规则读取失败：$e'));
        _emit(const [DashboardSection.logs]);
      }
    }
  }

  Future<void> closeConnection(String id) async {
    final generation = _generation;
    await _api!.request('DELETE', '/connections/${Uri.encodeComponent(id)}');
    if (generation == _generation) {
      connections = connections.where((c) => c['id'] != id).toList();
      _emit(const [DashboardSection.connections, DashboardSection.overview]);
    }
  }

  Future<void> closeAllConnections() async {
    final api = _api;
    if (!connected || api == null) throw ApiException('请先连接控制器');
    final ids = connections.map((item) => item['id']).toSet();
    await api.request('DELETE', '/connections');
    if (!identical(_api, api)) return;
    connections = connections
        .where((item) => !ids.contains(item['id']))
        .toList();
    _emit(const [DashboardSection.connections, DashboardSection.overview]);
  }

  void clearLogs() {
    logs.clear();
    _emit(const [DashboardSection.logs]);
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    for (final update in _updates.values) {
      update.dispose();
    }
    super.dispose();
  }
}

class _DelayTestRun {
  final abort = Completer<void>();
  Timer? updateTimer;
  bool get cancelled => abort.isCompleted;

  void cancel() {
    updateTimer?.cancel();
    if (!cancelled) abort.complete();
  }
}
