import 'package:flutter_test/flutter_test.dart';
import 'package:openclash_client/group_traffic.dart';

Map<String, dynamic> connection(
  String id,
  num up,
  num down, {
  List<String> chains = const ['HK', 'inner', 'outer'],
  String start = 'start-1',
}) => {
  'id': id,
  'upload': up,
  'download': down,
  'chains': chains,
  'start': start,
};

void main() {
  test('uses elapsed time and never treats initial totals as live speed', () {
    final tracker = GroupTrafficTracker();
    tracker.update([
      connection('a', 1000000, 9000000),
    ], timestamp: Duration.zero);
    expect(tracker.rateFor('outer'), isNull);
    tracker.update([
      connection('a', 1002048, 9008192),
    ], timestamp: const Duration(seconds: 2));
    expect(tracker.rateFor('outer')!.upload, 1024);
    expect(tracker.rateFor('outer')!.download, 4096);
    expect(tracker.rateFor('unused')!.download, 0);
  });

  test('aggregates actual nested chains once per connection and group', () {
    final tracker = GroupTrafficTracker();
    tracker.update([
      connection('a', 0, 0),
      connection('b', 0, 0, chains: ['other-node', 'outer']),
    ], timestamp: Duration.zero);
    tracker.update([
      connection('a', 1000, 4000, chains: ['HK', 'inner', 'outer', 'inner']),
      connection('a', 1000, 4000), // Duplicate entries must not double count.
      connection('b', 500, 1000, chains: ['other-node', 'outer']),
    ], timestamp: const Duration(seconds: 1));
    expect(tracker.rateFor('outer')!.upload, 1500);
    expect(tracker.rateFor('outer')!.download, 5000);
    expect(tracker.rateFor('inner')!.upload, 1000);
    expect(tracker.rateFor('inner')!.download, 4000);
    expect(tracker.rateFor('unrelated-group')!.download, 0);
  });

  test('includes new connections and clears idle or disappeared traffic', () {
    final tracker = GroupTrafficTracker();
    tracker.update([connection('a', 1000, 2000)], timestamp: Duration.zero);
    tracker.update([
      connection('a', 1500, 3000),
      connection('new', 200, 600),
    ], timestamp: const Duration(seconds: 1));
    expect(tracker.rateFor('outer')!.upload, 700);
    expect(tracker.rateFor('outer')!.download, 1600);
    tracker.update([
      connection('new', 200, 600),
    ], timestamp: const Duration(seconds: 2));
    expect(tracker.rateFor('outer')!.download, 0);
    tracker.update([], timestamp: const Duration(seconds: 3));
    expect(tracker.rateFor('outer')!.upload, 0);
  });

  test(
    'counter resets and reused IDs do not produce negative rates or spikes',
    () {
      final tracker = GroupTrafficTracker();
      tracker.update([connection('a', 1000, 2000)], timestamp: Duration.zero);
      tracker.update([
        connection('a', 10, 20),
      ], timestamp: const Duration(seconds: 1));
      expect(tracker.rateFor('outer')!.upload, 0);
      expect(tracker.rateFor('outer')!.download, 0);
      tracker.update([
        connection('a', 1000000, 2000000, start: 'different-start'),
      ], timestamp: const Duration(seconds: 2));
      expect(tracker.rateFor('outer')!.download, 0);
      tracker.update([
        connection('a', 1000100, 2000200, start: 'different-start'),
      ], timestamp: const Duration(seconds: 3));
      expect(tracker.rateFor('outer')!.download, 200);
    },
  );

  test(
    'ignores non-increasing timestamps and resets the reconnect baseline',
    () {
      final tracker = GroupTrafficTracker();
      tracker.update([connection('a', 100, 100)], timestamp: Duration.zero);
      tracker.update([connection('a', 900, 900)], timestamp: Duration.zero);
      tracker.update([
        connection('a', 200, 300),
      ], timestamp: const Duration(seconds: 1));
      expect(tracker.rateFor('outer')!.upload, 100);
      expect(tracker.rateFor('outer')!.download, 200);
      tracker.reset();
      expect(tracker.rateFor('outer'), isNull);
      tracker.update([
        connection('a', 90000, 90000),
      ], timestamp: const Duration(seconds: 20));
      expect(tracker.rateFor('outer'), isNull);
      tracker.update([
        connection('a', 90200, 90400),
      ], timestamp: const Duration(seconds: 22));
      expect(tracker.rateFor('outer')!.upload, 100);
      expect(tracker.rateFor('outer')!.download, 200);
    },
  );

  test(
    'ignores invalid counters and missing chains without breaking samples',
    () {
      final tracker = GroupTrafficTracker();
      tracker.update([], timestamp: Duration.zero);
      tracker.update([
        connection('valid', 100, 200),
        connection('negative', -10, 500),
        connection('nan', double.nan, 600),
        connection('infinity', 0, double.infinity),
        {'id': 'missing'},
        {'id': '', 'upload': 0, 'download': 900},
        {'id': 'no-chain', 'upload': 1000, 'download': 5000},
      ], timestamp: const Duration(seconds: 1));
      expect(tracker.rateFor('outer')!.upload, 100);
      expect(tracker.rateFor('outer')!.download, 200);
      tracker.update([
        connection('valid', 200, 300),
        connection('nan', 1000000, 1000000),
      ], timestamp: const Duration(seconds: 2));
      expect(tracker.rateFor('outer')!.upload, 100);
      expect(tracker.rateFor('outer')!.download, 100);
      tracker.update([
        connection('valid', 200, 300),
        connection('nan', 1000100, 1000300),
      ], timestamp: const Duration(seconds: 3));
      expect(tracker.rateFor('outer')!.upload, 100);
      expect(tracker.rateFor('outer')!.download, 300);
    },
  );
}
