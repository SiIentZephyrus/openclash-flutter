/// Keeps ended connections searchable without changing the live connection list.
class ConnectionHistory {
  ConnectionHistory({this.maxEnded = 2000}) : assert(maxEnded >= 0);

  static const retention = Duration(minutes: 5);
  final int maxEnded;
  final _records = <String, _Record>{};
  final _ended = <String>{};

  List<Map<String, dynamic>> get connections =>
      _records.values.map((record) => record.data).toList();

  void update(List<Map<String, dynamic>> connections, {required Duration now}) {
    prune(now);
    final active = <String>{};
    for (final item in connections) {
      final id = item['id'];
      if (id is! String || id.isEmpty || !active.add(id)) continue;
      // Replacing a value preserves its position as counters and metadata change.
      _records[id] = _Record(Map<String, dynamic>.of(item));
      _ended.remove(id);
    }
    for (final entry in _records.entries) {
      if (!active.contains(entry.key) && _ended.add(entry.key)) {
        entry.value.endedAt = now;
      }
    }
    while (_ended.length > maxEnded) {
      _removeOldest();
    }
  }

  bool prune(Duration now) {
    final before = _ended.length;
    while (_ended.isNotEmpty &&
        now - _records[_ended.first]!.endedAt! >= retention) {
      _removeOldest();
    }
    return before != _ended.length;
  }

  void _removeOldest() {
    final id = _ended.first;
    _ended.remove(id);
    _records.remove(id);
  }

  void clear() {
    _records.clear();
    _ended.clear();
  }
}

class _Record {
  _Record(this.data);
  final Map<String, dynamic> data;
  Duration? endedAt;
}
