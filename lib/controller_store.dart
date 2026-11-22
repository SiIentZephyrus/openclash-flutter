import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'clash_api.dart';

class ControllerProfile {
  ControllerProfile(String address, this.secret)
    : address = ClashApi.validateAddress(address).toString();
  final String address;
  final String secret;
  Map<String, dynamic> toJson() => {'address': address, 'secret': secret};
  factory ControllerProfile.fromJson(Map<String, dynamic> json) {
    if (json['address'] is! String || json['secret'] is! String) {
      throw const FormatException('Invalid controller profile');
    }
    return ControllerProfile(
      json['address'] as String,
      json['secret'] as String,
    );
  }
}

abstract class ControllerStore {
  Future<ControllerProfile?> read();
  Future<void> save(ControllerProfile profile);
  Future<String?> addressHint() async => null;
}

class LocalControllerStore extends ControllerStore {
  LocalControllerStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const profileKey = 'openclash.controller.v1';

  @override
  Future<ControllerProfile?> read() async {
    final raw = await _storage.read(key: profileKey);
    if (raw == null) return null;
    return ControllerProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(ControllerProfile profile) =>
      _storage.write(key: profileKey, value: jsonEncode(profile.toJson()));

  @override
  Future<String?> addressHint() async {
    // Older versions saved only the address. Prefill it, but require a new
    // successful connection before treating it as a complete saved profile.
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('controllerAddress');
  }
}
