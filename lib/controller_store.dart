import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'clash_api.dart';

class ControllerProfile {
  ControllerProfile(String address, this.secret, {String name = ''})
    : address = ClashApi.validateAddress(address).toString(),
      name = name.trim();
  final String address;
  final String secret;
  final String name;
  String get label => name.isEmpty ? address : name;
  Map<String, dynamic> toJson() => {
    'address': address,
    'secret': secret,
    'name': name,
  };
  factory ControllerProfile.fromJson(Map<String, dynamic> json) {
    if (json['address'] is! String || json['secret'] is! String) {
      throw const FormatException('Invalid controller profile');
    }
    return ControllerProfile(
      json['address'] as String,
      json['secret'] as String,
      name: json['name'] as String? ?? '',
    );
  }
}

class ControllerProfiles {
  ControllerProfiles(Iterable<ControllerProfile> profiles, this.activeAddress)
    : profiles = List.unmodifiable(profiles) {
    final addresses = this.profiles.map((profile) => profile.address).toSet();
    if (addresses.length != this.profiles.length ||
        !addresses.contains(activeAddress)) {
      throw const FormatException('Invalid saved controller list');
    }
  }

  ControllerProfiles.single(ControllerProfile profile)
    : this([profile], profile.address);

  final List<ControllerProfile> profiles;
  final String activeAddress;
  ControllerProfile get active =>
      profiles.firstWhere((profile) => profile.address == activeAddress);

  Map<String, dynamic> toJson() => {
    'activeAddress': activeAddress,
    'profiles': profiles.map((profile) => profile.toJson()).toList(),
  };

  factory ControllerProfiles.fromJson(Map<String, dynamic> json) {
    if (!json.containsKey('profiles')) {
      return ControllerProfiles.single(ControllerProfile.fromJson(json));
    }
    return ControllerProfiles(
      (json['profiles'] as List).map(
        (entry) => ControllerProfile.fromJson(entry as Map<String, dynamic>),
      ),
      json['activeAddress'] as String,
    );
  }
}

abstract class ControllerStore {
  Future<ControllerProfiles?> readProfiles();
  Future<void> saveProfiles(ControllerProfiles profiles);
  Future<String?> addressHint() async => null;
}

class LocalControllerStore extends ControllerStore {
  LocalControllerStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const profileKey = 'openclash.controller.v1';

  @override
  Future<ControllerProfiles?> readProfiles() async {
    final raw = await _storage.read(key: profileKey);
    if (raw == null) return null;
    return ControllerProfiles.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> saveProfiles(ControllerProfiles profiles) =>
      _storage.write(key: profileKey, value: jsonEncode(profiles.toJson()));

  @override
  Future<String?> addressHint() async {
    // Older versions saved only the address. Prefill it, but require a new
    // successful connection before treating it as a complete saved profile.
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('controllerAddress');
  }
}
