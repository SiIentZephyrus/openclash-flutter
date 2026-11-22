import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openclash_client/clash_api.dart';
import 'package:openclash_client/models.dart';

void main() {
  test('validates controller endpoints and rejects embedded credentials', () {
    expect(
      ClashApi.validateAddress('http://192.168.1.1:9090/').toString(),
      'http://192.168.1.1:9090',
    );
    for (final address in [
      '192.168.1.1:9090',
      'ftp://router',
      'http://a:b@router',
      'https://',
      'http://router?secret=x',
    ]) {
      expect(
        () => ClashApi.validateAddress(address),
        throwsA(isA<ApiException>()),
      );
    }
  });
  test(
    'authenticated selection preserves Chinese and reserved characters',
    () async {
      final api = ClashApi(
        'http://router:9090',
        'test-secret',
        client: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.headers['Authorization'], 'Bearer test-secret');
          expect(request.url.pathSegments.last, '节点 / #1');
          expect(jsonDecode(request.body), {'name': '香港 #1'});
          return http.Response('', 204);
        }),
      );
      addTearDown(api.close);
      expect(
        await api.request(
          'PUT',
          '/proxies/${Uri.encodeComponent('节点 / #1')}',
          body: {'name': '香港 #1'},
        ),
        isEmpty,
      );
    },
  );
  test(
    'maps authentication and invalid responses into useful errors',
    () async {
      final unauthorized = ClashApi(
        'http://router',
        '',
        client: MockClient((_) async => http.Response('', 401)),
      );
      final invalid = ClashApi(
        'http://router',
        '',
        client: MockClient(
          (_) async => http.Response('<html>LuCI</html>', 200),
        ),
      );
      addTearDown(unauthorized.close);
      addTearDown(invalid.close);
      await expectLater(
        unauthorized.request('GET', '/version'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('认证失败'),
          ),
        ),
      );
      await expectLater(
        invalid.request('GET', '/version'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('无效数据'),
          ),
        ),
      );
    },
  );
  test('parses empty delay history and structured or classic logs', () {
    expect(
      ProxyNode.fromJson('HK', {'type': 'Trojan', 'history': []}).delay,
      isNull,
    );
    expect(
      ProxyNode.fromJson('HK', {
        'type': 'Trojan',
        'history': [
          {'delay': 35},
          {'delay': 0},
        ],
      }).delay,
      0,
    );
    expect(
      LogEntry.fromJson({'type': 'error', 'payload': 'failed'}).message,
      'failed',
    );
    expect(
      LogEntry.fromJson({'level': 'warning', 'message': 'retry'}).level,
      'warning',
    );
  });
}
