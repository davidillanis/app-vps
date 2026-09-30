import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_vps/src/api.dart';
import 'package:app_vps/src/controller.dart';

Map<String, dynamic> fixture() => {
  'id': 'test-server',
  'name': 'Test fixture',
  'status': 'Active',
  'powerState': 'Running',
  'vCores': 1,
  'ramGb': 2,
  'volumeSizeGb': 10,
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
  });
  test('Impide doble envío, guarda el ID y libera al completar', () async {
    final response = Completer<http.Response>();
    var posts = 0;
    final controller = VpsController(
      api: CloudingApi(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            posts++;
            return response.future;
          }
          if (r.url.path.startsWith('/v1/actions/')) {
            return http.Response('{"status":"completed"}', 200);
          }
          return http.Response(
            jsonEncode({
              'servers': [fixture()],
              'links': {'next': null},
            }),
            200,
          );
        }),
      ),
    );
    await controller.initialize();
    await controller.connect('test-key');
    final server = controller.servers.first;
    final first = controller.operate(server, 'archive');
    await controller.operate(server, 'archive');
    response.complete(
      http.Response('{"id":"test-action","status":"inProgress"}', 202),
    );
    await first;
    expect(posts, 1);
    expect(controller.pendingActions[server.id], 'test-action');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pendingActions'), contains('test-action'));
    await controller.tick();
    expect(controller.progress, isEmpty);
    expect(controller.pendingActions, isEmpty);
    controller.dispose();
  });
  test('Fallo de red en escritura conserva bloqueo hasta revisión', () async {
    var posts = 0;
    final controller = VpsController(
      api: CloudingApi(
        client: MockClient((r) async {
          if (r.method == 'POST') {
            posts++;
            throw http.ClientException('test network failure');
          }
          return http.Response(
            jsonEncode({
              'servers': [fixture()],
              'links': {'next': null},
            }),
            200,
          );
        }),
      ),
    );
    await controller.initialize();
    await controller.connect('test-key');
    final server = controller.servers.first;
    await controller.operate(server, 'stop');
    await controller.operate(server, 'stop');
    expect(posts, 1);
    expect(controller.progress[server.id], 'Revisar resultado');
    await controller.reconcile(server.id);
    expect(controller.progress, isEmpty);
    controller.dispose();
  });
}
