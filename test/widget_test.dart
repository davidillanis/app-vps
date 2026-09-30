import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_vps/src/api.dart';
import 'package:app_vps/src/app.dart';
import 'package:app_vps/src/controller.dart';

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
  for (final width in [390.0, 1280.0]) {
    testWidgets('Dashboard y configuración adaptables a $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = VpsController();
      await controller.initialize();
      await tester.pumpWidget(VpsApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('Conecta tus servidores'), findsOneWidget);
      expect(find.text('Flutter Demo'), findsNothing);
      await tester.tap(find.text('Configurar API KEY'));
      await tester.pumpAndSettle();
      expect(find.text('Validar y guardar'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
  for (final width in [360.0, 1280.0]) {
    testWidgets('Pantallas con datos y cancelación segura a $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var writes = 0;
      final controller = VpsController(
        api: CloudingApi(
          client: MockClient((r) async {
            if (r.method != 'GET') writes++;
            final fixture = {
              'id': 'test-server',
              'name': 'Servidor de prueba con nombre largo',
              'status': 'Active',
              'powerState': 'Running',
              'vCores': 1,
              'ramGb': 2,
              'volumeSizeGb': 10,
              'publicPorts': [
                {'ipAddress': '192.0.2.1'},
              ],
              'cost': {'pricePerHour': 0.01, 'pricePerMonthApprox': 7.3},
            };
            return http.Response(
              jsonEncode(
                r.url.path == '/v1/servers'
                    ? {
                        'servers': [fixture],
                        'links': {'next': null},
                      }
                    : fixture,
              ),
              200,
            );
          }),
        ),
      );
      await controller.initialize();
      await controller.connect('test-key');
      await tester.pumpWidget(VpsApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(PopupMenuButton<String>));
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archivar'));
      await tester.pumpAndSettle();
      expect(find.text('Archivar servidor'), findsOneWidget);
      expect(writes, 0);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      for (final label in ['Costes', 'Programaciones', 'Configuración']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(writes, 0);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
