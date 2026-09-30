import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_vps/src/api.dart';
import 'package:app_vps/src/controller.dart';
import 'package:app_vps/src/key_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  VpsController createController({bool reject = false}) => VpsController(
    keyStorage: ApiKeyStorage(browser: true),
    api: CloudingApi(
      client: MockClient((request) async {
        expect(request.headers['X-API-KEY'], 'fixture-key');
        return http.Response(
          jsonEncode(
            reject
                ? {}
                : {
                    'servers': [],
                    'links': {'next': null},
                  },
          ),
          reject ? 401 : 200,
        );
      }),
    ),
  );

  test(
    'La clave validada se recupera en otra sesión y se borra al eliminarla',
    () async {
      final first = createController();
      await first.initialize();
      await first.connect('  fixture-key  ');
      expect(first.connected, isTrue);
      first.dispose();

      final reopened = createController();
      await reopened.initialize();
      expect(reopened.connected, isTrue);
      expect(reopened.updatedAt, isNotNull);
      await reopened.disconnect();
      reopened.dispose();

      final afterDeletion = createController();
      await afterDeletion.initialize();
      expect(afterDeletion.connected, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(ApiKeyStorage.storageKey), isFalse);
      afterDeletion.dispose();
    },
  );

  test('Una clave rechazada no se guarda en la caché', () async {
    final controller = createController(reject: true);
    await controller.initialize();
    await controller.connect('fixture-key');
    expect(controller.connected, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(ApiKeyStorage.storageKey), isFalse);
    controller.dispose();
  });
}
