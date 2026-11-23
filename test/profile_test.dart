import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openclash_client/controller_store.dart';
import 'package:openclash_client/dashboard_controller.dart';
import 'support/profile_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'fresh install has no controller and no sample data or network requests',
    () async {
      final store = MemoryControllerStore();
      final api = ApiRecorder();
      final c = DashboardController(store: store, apiFactory: api.create);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.initialized, isTrue);
      expect(c.hasProfile, isFalse);
      expect(c.address, isEmpty);
      expect(c.secret, isEmpty);
      expect(c.proxies, isEmpty);
      expect(c.logs, isEmpty);
      expect(c.down, 0);
      expect(api.credentials, isEmpty);
    },
  );
  test(
    'save persists address and secret, and next instance reconnects without rewriting',
    () async {
      final store = MemoryControllerStore();
      final api = ApiRecorder();
      final first = DashboardController(store: store, apiFactory: api.create);
      await first.initialize();
      expect(
        await first.saveController('http://router:9090/', 'persistent-key'),
        isTrue,
      );
      expect(first.hasProfile, isTrue);
      expect(first.connected, isTrue);
      expect(store.profile!.address, 'http://router:9090');
      expect(store.profile!.secret, 'persistent-key');
      expect(store.writes, 1);
      first.dispose();
      final next = DashboardController(store: store, apiFactory: api.create);
      addTearDown(next.dispose);
      await Future.wait([next.initialize(), next.initialize()]);
      expect(next.hasProfile, isTrue);
      expect(next.connected, isTrue);
      expect(next.address, 'http://router:9090');
      expect(next.secret, 'persistent-key');
      expect(api.credentials.last, ('http://router:9090', 'persistent-key'));
      expect(store.writes, 1);
      expect(store.reads, 2);
      expect(api.requests.where((r) => r.url.path == '/version').length, 2);
    },
  );
  test(
    'bad credentials or malformed responses never save a first profile',
    () async {
      final store = MemoryControllerStore();
      final api = ApiRecorder();
      final c = DashboardController(store: store, apiFactory: api.create);
      addTearDown(c.dispose);
      await c.initialize();
      expect(await c.saveController('http://router', 'wrong'), isFalse);
      expect(c.error, contains('认证失败'));
      expect(await c.saveController('http://bad-data', 'key'), isFalse);
      expect(c.hasProfile, isFalse);
      expect(store.profile, isNull);
      expect(store.writes, 0);
      expect(c.proxies, isEmpty);
    },
  );
  test(
    'failed edit and failed storage write retain the previous working profile',
    () async {
      final store = MemoryControllerStore()
        ..profile = ControllerProfile('http://old-router', 'old-key');
      final api = ApiRecorder();
      final c = DashboardController(store: store, apiFactory: api.create);
      addTearDown(c.dispose);
      await c.initialize();
      expect(await c.saveController('http://new-router', 'wrong'), isFalse);
      expect(c.address, 'http://old-router');
      expect(c.secret, 'old-key');
      expect(c.connected, isTrue);
      store.failWrite = true;
      expect(await c.saveController('http://new-router', 'new-key'), isFalse);
      expect(c.error, contains('无法保存'));
      expect(c.address, 'http://old-router');
      expect(c.connected, isTrue);
      expect(store.profile!.secret, 'old-key');
      expect(store.writes, 0);
    },
  );
  test(
    'offline startup retains saved credentials and does not require setup again',
    () async {
      final store = MemoryControllerStore()
        ..profile = ControllerProfile('http://offline', 'keep-key');
      final api = ApiRecorder();
      final c = DashboardController(store: store, apiFactory: api.create);
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.hasProfile, isTrue);
      expect(c.connected, isFalse);
      expect(c.address, 'http://offline');
      expect(c.secret, 'keep-key');
      expect(store.profile!.secret, 'keep-key');
      expect(store.writes, 0);
      expect(c.proxies, isEmpty);
      expect(c.logs, isEmpty);
    },
  );
  test('legacy address is only a form hint and cannot bypass setup', () async {
    final store = MemoryControllerStore()..hint = 'http://legacy:9090';
    final api = ApiRecorder();
    final c = DashboardController(store: store, apiFactory: api.create);
    addTearDown(c.dispose);
    await c.initialize();
    expect(c.address, 'http://legacy:9090');
    expect(c.hasProfile, isFalse);
    expect(api.credentials, isEmpty);
  });

  test(
    'named profiles survive restart and a failed switch keeps the active profile',
    () async {
      final store = MemoryControllerStore();
      final api = ApiRecorder();
      final c = DashboardController(store: store, apiFactory: api.create);
      addTearDown(c.dispose);
      await c.initialize();
      expect(
        await c.saveController('http://home', 'home-key', name: ' 家里 '),
        isTrue,
      );
      expect(
        await c.saveController(
          'http://work',
          'work-key',
          name: '办公室',
          add: true,
        ),
        isTrue,
      );
      expect(c.savedControllers.map((profile) => profile.name), ['家里', '办公室']);
      expect(store.profile!.name, '办公室');
      api.unavailableHosts.add('home');
      expect(await c.switchController('http://home'), isFalse);
      expect(c.connected, isTrue);
      expect(c.address, 'http://work');
      expect(store.writes, 2);
      api.unavailableHosts.remove('home');
      expect(await c.switchController('http://home'), isTrue);
      expect(c.secret, 'home-key');
      final restored = DashboardController(
        store: store,
        apiFactory: api.create,
      );
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.controllerName, '家里');
      expect(restored.savedControllers.length, 2);
      store.failWrite = true;
      await expectLater(
        restored.removeController('http://work'),
        throwsException,
      );
      expect(restored.savedControllers.length, 2);
      store.failWrite = false;
      await restored.removeController('http://work');
      expect(store.profiles!.profiles.single.name, '家里');
    },
  );
  test(
    'unreadable local profile requires setup and does not generate sample data',
    () async {
      final store = MemoryControllerStore()..failRead = true;
      final c = DashboardController(
        store: store,
        apiFactory: ApiRecorder().create,
      );
      addTearDown(c.dispose);
      await c.initialize();
      expect(c.initialized, isTrue);
      expect(c.hasProfile, isFalse);
      expect(c.error, contains('无法读取'));
      expect(c.proxies, isEmpty);
    },
  );
  test(
    'local store roundtrips one profile via secure storage and never writes secret to preferences',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        LocalControllerStore.profileKey:
            '{"address":"https://old-router:9090","secret":"legacy-key"}',
      });
      SharedPreferences.setMockInitialValues({});
      final store = LocalControllerStore();
      final legacy = (await store.readProfiles())!.active;
      expect(legacy.label, 'https://old-router:9090');
      expect(legacy.secret, 'legacy-key');
      await store.saveProfiles(
        ControllerProfiles([
          legacy,
          ControllerProfile('https://router:9090', 'secret-value', name: '备用'),
        ], 'https://router:9090'),
      );
      final loaded = (await LocalControllerStore().readProfiles())!;
      expect(loaded.active.address, 'https://router:9090');
      expect(loaded.active.secret, 'secret-value');
      expect(loaded.active.name, '备用');
      expect(loaded.profiles.first.secret, 'legacy-key');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      FlutterSecureStorage.setMockInitialValues({
        LocalControllerStore.profileKey: '{broken',
      });
      await expectLater(
        LocalControllerStore().readProfiles(),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
