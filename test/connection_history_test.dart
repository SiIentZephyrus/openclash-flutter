import 'package:flutter_test/flutter_test.dart';
import 'package:openclash_client/connection_history.dart';

Map<String, dynamic> connection(String id, [int download = 0]) => {
  'id': id,
  'download': download,
  'metadata': {'host': '$id.example'},
};

void main() {
  test('merges new connections and latest counters in stable order', () {
    final history = ConnectionHistory();
    history.update([connection('a'), connection('b')], now: Duration.zero);
    history.update([
      connection('b', 100),
      connection('c'),
    ], now: const Duration(seconds: 1));
    expect(history.connections.map((item) => item['id']), ['a', 'b', 'c']);
    expect(history.connections[1]['download'], 100);
    history.update([
      connection('c'),
      connection('b', 200),
    ], now: const Duration(seconds: 2));
    expect(history.connections.map((item) => item['id']), ['a', 'b', 'c']);
    expect(history.connections[1]['download'], 200);
  });

  test('retains ended connections for five minutes without extending expiry', () {
    final history = ConnectionHistory();
    history.update([connection('old')], now: Duration.zero);
    history.update([connection('new')], now: const Duration(seconds: 20));
    history.update([connection('new')], now: const Duration(minutes: 5));
    expect(history.connections.map((item) => item['id']), ['old', 'new']);
    expect(history.prune(const Duration(minutes: 5, seconds: 19)), isFalse);
    expect(history.prune(const Duration(minutes: 5, seconds: 20)), isTrue);
    expect(history.connections.single['id'], 'new');
    // Live connections are kept regardless of their age or the last frame time.
    expect(history.prune(const Duration(hours: 1)), isFalse);
    expect(history.connections.single['id'], 'new');
  });

  test(
    'returning connections become live and get a fresh retention window',
    () {
      final history = ConnectionHistory();
      history.update([connection('a')], now: Duration.zero);
      history.update([], now: const Duration(seconds: 1));
      history.update([connection('a', 50)], now: const Duration(minutes: 4));
      expect(history.prune(const Duration(minutes: 6)), isFalse);
      history.update([], now: const Duration(minutes: 6));
      expect(history.prune(const Duration(minutes: 10, seconds: 59)), isFalse);
      expect(history.prune(const Duration(minutes: 11)), isTrue);
      expect(history.connections, isEmpty);
    },
  );

  test(
    'copies records, ignores invalid or duplicate IDs, and clears history',
    () {
      final history = ConnectionHistory();
      final item = connection('a', 10);
      history.update([
        item,
        connection('a', 20),
        {},
        {'id': ''},
      ], now: Duration.zero);
      item['download'] = 999;
      expect(history.connections.single['download'], 10);
      history.clear();
      expect(history.connections, isEmpty);
    },
  );
}
