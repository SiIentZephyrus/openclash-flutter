import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class ClashApi {
  ClashApi(String address, this.secret, {http.Client? client})
    : base = validateAddress(address),
      _client = client ?? http.Client();
  final Uri base;
  final String secret;
  final http.Client _client;

  static Uri validateAddress(String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ApiException('请输入完整控制器地址，例如 http://192.168.1.1:9090');
    }
    return uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), ''));
  }

  Uri uri(String path, [Map<String, String>? query]) =>
      base.replace(path: '${base.path}$path', queryParameters: query);

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final request = http.Request(method, uri(path, query));
    request.headers.addAll({
      'Content-Type': 'application/json',
      if (secret.isNotEmpty) 'Authorization': 'Bearer $secret',
    });
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(switch (response.statusCode) {
          401 || 403 => '认证失败，请检查 API Secret',
          404 => '接口不存在，请检查控制器地址和内核版本',
          _ => '请求失败（HTTP ${response.statusCode}）',
        }, statusCode: response.statusCode);
      }
      return response.body.isEmpty
          ? {}
          : (jsonDecode(response.body) as Map<String, dynamic>);
    } on TimeoutException {
      throw ApiException('连接超时，请检查路由器地址和网络');
    } on http.ClientException {
      throw ApiException('无法连接控制器，请检查网络、端口或浏览器跨域设置');
    } on FormatException {
      throw ApiException('控制器返回了无效数据，请确认地址不是 LuCI 管理页面');
    }
  }

  WebSocketChannel socket(
    String path, [
    Map<String, String> query = const {},
  ]) => WebSocketChannel.connect(
    uri(path, {
      ...query,
      if (secret.isNotEmpty) 'token': secret,
    }).replace(scheme: base.scheme == 'https' ? 'wss' : 'ws'),
  );

  void close() => _client.close();
}
