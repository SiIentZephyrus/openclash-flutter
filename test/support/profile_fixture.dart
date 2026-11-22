import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:openclash_client/clash_api.dart';
import 'package:openclash_client/controller_store.dart';

class MemoryControllerStore extends ControllerStore {
  ControllerProfile? profile;
  String? hint;
  int reads = 0, writes = 0;
  bool failRead = false, failWrite = false;
  Completer<void>? pendingWrite;
  @override
  Future<ControllerProfile?> read() async {
    reads++;
    if (failRead) throw StateError('storage unavailable');
    return profile;
  }

  @override
  Future<void> save(ControllerProfile value) async {
    if (pendingWrite != null) await pendingWrite!.future;
    if (failWrite) throw StateError('disk write failed');
    profile = value;
    writes++;
  }

  @override
  Future<String?> addressHint() async => hint;
}

class ApiRecorder {
  final credentials = <(String, String)>[];
  final requests = <http.Request>[];
  ClashApi create(String address, String secret) {
    credentials.add((address, secret));
    return _NoSocketApi(
      address,
      secret,
      client: MockClient((request) async {
        requests.add(request);
        if (secret == 'wrong') return http.Response('{}', 401);
        if (request.url.host == 'offline') return http.Response('{}', 503);
        final data = switch (request.url.path) {
          '/version' => {'version': 'fixture-core'},
          '/configs' => {'mode': 'rule'},
          '/proxies' => {
            'proxies': request.url.host == 'bad-data'
                ? []
                : <String, dynamic>{},
          },
          '/rules' => {'rules': []},
          _ => <String, dynamic>{},
        };
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }
}

class _NoSocketApi extends ClashApi {
  _NoSocketApi(super.address, super.secret, {super.client});
  @override
  WebSocketChannel socket(
    String path, [
    Map<String, String> query = const {},
  ]) => throw UnsupportedError('No stream needed for profile tests');
}
