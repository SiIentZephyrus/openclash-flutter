import 'package:shared_preferences/shared_preferences.dart';

class DelaySettings {
  const DelaySettings({this.url = defaultUrl, this.timeoutMs = defaultTimeout});

  static const defaultUrl = 'https://www.gstatic.com/generate_204';
  static const defaultTimeout = 5000;
  static const _storageKey = 'openclash.delaySettings';
  final String url;
  final int timeoutMs;

  static bool supportsUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment;
  }

  static bool supportsTimeout(int? milliseconds) =>
      milliseconds != null && milliseconds >= 250 && milliseconds <= 30000;

  static Future<DelaySettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = prefs.getStringList(_storageKey);
      if (values != null && values.length == 2) {
        final timeout = int.tryParse(values[1]);
        if (supportsUrl(values[0]) && supportsTimeout(timeout)) {
          return DelaySettings(url: values[0], timeoutMs: timeout!);
        }
      }
    } catch (_) {
      // Use the built-in defaults when stored preferences are unavailable.
    }
    return const DelaySettings();
  }

  Future<void> save() async {
    if (!supportsUrl(url) || !supportsTimeout(timeoutMs)) {
      throw const FormatException('测速地址或超时无效');
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(_storageKey, [url, '$timeoutMs'])) {
      throw StateError('无法保存测速设置，请重试');
    }
  }
}
