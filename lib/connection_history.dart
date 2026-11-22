/// Keeps ended connections searchable without changing the live connection list.
class ConnectionHistory {
  static const retention = Duration(minutes: 5);
  final _records = <String, _Record>{};

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
    }
    for (final entry in _records.entries) {
      if (!active.contains(entry.key)) entry.value.endedAt ??= now;
    }
  }

  bool prune(Duration now) {
    final before = _records.length;
    _records.removeWhere((_, record) {
      final endedAt = record.endedAt;
      return endedAt != null && now - endedAt >= retention;
    });
    return before != _records.length;
  }

  void clear() => _records.clear();
}

class _Record {
  _Record(this.data);
  final Map<String, dynamic> data;
  Duration? endedAt;
}
