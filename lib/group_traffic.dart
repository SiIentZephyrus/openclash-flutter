class TrafficRate {
  const TrafficRate({this.upload = 0, this.download = 0});
  final double upload;
  final double download;
}

/// Derives bytes/second from cumulative per-connection counters. A connection
/// contributes once to each name in its actual chain, including nested groups.
class GroupTrafficTracker {
  Map<String, _Counters?> _previous = {};
  Map<String, TrafficRate> _rates = {};
  Duration? _sampleTime;
  bool _ready = false;

  TrafficRate? rateFor(String name) =>
      _ready ? _rates[name] ?? const TrafficRate() : null;

  void reset() {
    _previous = {};
    _rates = {};
    _sampleTime = null;
    _ready = false;
  }

  void update(
    List<Map<String, dynamic>> connections, {
    required Duration timestamp,
  }) {
    final previousTime = _sampleTime;
    if (previousTime != null && timestamp <= previousTime) return;
    final seconds = previousTime == null
        ? 0.0
        : (timestamp - previousTime).inMicroseconds /
              Duration.microsecondsPerSecond;
    final next = <String, _Counters?>{};
    final rates = <String, TrafficRate>{};
    for (final connection in connections) {
      final id = connection['id'];
      final upload = connection['upload'];
      final download = connection['download'];
      if (id is! String || id.isEmpty || next.containsKey(id)) {
        continue;
      }
      if (upload is! num ||
          !upload.isFinite ||
          upload < 0 ||
          download is! num ||
          !download.isFinite ||
          download < 0) {
        // The next valid counter needs a new baseline so its lifetime bytes
        // are not misreported as traffic from a newly opened connection.
        next[id] = null;
        continue;
      }
      final current = _Counters(upload, download, connection['start']);
      next[id] = current;
      if (previousTime == null) continue;
      final previous = _previous[id];
      if (previous == null && _previous.containsKey(id)) continue;
      // An ID reused for a different connection establishes a fresh baseline.
      if (previous != null && previous.start != current.start) continue;
      double delta(num value, num? before) => (before != null && value < before)
          ? 0
          : (value - (before ?? 0)) / seconds;
      final up = delta(upload, previous?.upload);
      final down = delta(download, previous?.download);
      final chains = connection['chains'];
      if (chains is! List) continue;
      for (final name in chains.whereType<String>().toSet()) {
        final rate = rates[name] ?? const TrafficRate();
        rates[name] = TrafficRate(
          upload: rate.upload + up,
          download: rate.download + down,
        );
      }
    }
    _previous = next;
    _sampleTime = timestamp;
    _rates = rates;
    _ready = previousTime != null;
  }
}

class _Counters {
  const _Counters(this.upload, this.download, this.start);
  final num upload;
  final num download;
  final Object? start;
}
