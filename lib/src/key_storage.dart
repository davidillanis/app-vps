import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Browser persistence is local storage, not a secret store.
class ApiKeyStorage {
  ApiKeyStorage({bool? browser}) : browser = browser ?? kIsWeb;
  final bool browser;
  static const storageKey = 'clouding_api_key';
  final _secure = const FlutterSecureStorage();

  Future<String> read(SharedPreferences prefs) async => browser
      ? prefs.getString(storageKey) ?? ''
      : await _secure.read(key: storageKey) ?? '';

  Future<void> write(SharedPreferences prefs, String key) async {
    if (browser) {
      if (!await prefs.setString(storageKey, key)) {
        throw StateError('No se pudo guardar la API KEY en el navegador.');
      }
    } else {
      await _secure.write(key: storageKey, value: key);
    }
  }

  Future<void> delete(SharedPreferences prefs) async {
    if (browser) {
      if (!await prefs.remove(storageKey)) {
        throw StateError('No se pudo eliminar la API KEY del navegador.');
      }
    } else {
      await _secure.delete(key: storageKey);
    }
  }
}
