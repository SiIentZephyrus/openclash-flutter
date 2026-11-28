class ProxyNode {
  ProxyNode({
    required this.name,
    required this.type,
    this.members = const [],
    this.now = '',
    this.delay,
    this.hidden = false,
    this.providerName,
    this.testUrl,
  });
  final String name;
  final String type;
  final List<String> members;
  String now;
  int? delay;
  final bool hidden;
  final String? providerName;
  final String? testUrl;
  bool get isGroup =>
      members.isNotEmpty ||
      const [
        'selector',
        'urltest',
        'fallback',
        'loadbalance',
        'relay',
      ].contains(type.toLowerCase());
  bool get selectable =>
      const ['Selector', 'URLTest', 'Fallback'].contains(type);

  factory ProxyNode.fromJson(
    String name,
    Map<String, dynamic> json, {
    String? providerName,
    String? testUrl,
  }) {
    final history = json['history'] as List? ?? [];
    return ProxyNode(
      name: name,
      type: json['type'] as String? ?? 'Unknown',
      members: (json['all'] as List? ?? []).cast<String>(),
      now: json['now'] as String? ?? '',
      hidden: json['hidden'] == true,
      providerName: providerName,
      testUrl: testUrl ?? json['testUrl'] as String?,
      delay: history.isEmpty ? null : (history.last['delay'] as num?)?.toInt(),
    );
  }
}

class LogEntry {
  LogEntry(this.level, this.message, {DateTime? time})
    : time = time ?? DateTime.now();
  final String level;
  final String message;
  final DateTime time;
  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
    (json['type'] ?? json['level'] ?? 'info').toString(),
    (json['payload'] ?? json['message'] ?? '').toString(),
  );
  String get timestamp =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  String get line => '$timestamp [${level.toUpperCase()}] $message';
}

enum ProviderKind {
  proxies('proxies', '节点订阅', '节点'),
  rules('rules', '规则集', '规则');

  const ProviderKind(this.path, this.label, this.unit);
  final String path;
  final String label;
  final String unit;
}

class ProviderSummary {
  ProviderSummary(this.name, this.kind, Map<String, dynamic> json)
    : count = kind == ProviderKind.proxies
          ? (json['proxies'] as List?)?.length
          : (json['ruleCount'] as num?)?.toInt(),
      updatedAt = DateTime.tryParse('${json['updatedAt'] ?? ''}')?.toLocal(),
      canUpdate =
          json['vehicleType']?.toString().toLowerCase() != 'compatible' &&
          json['vehicleType']?.toString().toLowerCase() != 'inline';

  final String name;
  final ProviderKind kind;
  final int? count;
  final DateTime? updatedAt;
  final bool canUpdate;
}

String formatBytes(num bytes, {bool rate = false}) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}${rate ? '/s' : ''}';
}
