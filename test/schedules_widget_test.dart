import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_vps/src/api.dart';
import 'package:app_vps/src/app.dart';
import 'package:app_vps/src/controller.dart';
import 'package:app_vps/src/key_storage.dart';
import 'package:app_vps/src/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'Crear, editar y pausar automatización a $width sin ejecutar acciones',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = VpsController(
          api: CloudingApi(
            client: MockClient((request) async {
              expect(request.method, 'GET');
              return http.Response(
                jsonEncode({
                  'servers': [
                    {'id': 'fixture', 'name': 'Servidor de prueba'},
                  ],
                  'links': {'next': null},
                }),
                200,
              );
            }),
          ),
          keyStorage: ApiKeyStorage(browser: true),
        );
        await c.initialize();
        await c.connect('fixture-key');
        await tester.pumpWidget(VpsApp(controller: c));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Programaciones'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Nueva programación'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<ScheduledAction>));
        await tester.pumpAndSettle();
        for (final action in ScheduledAction.values) {
          expect(find.text(action.label), findsWidgets);
        }
        await tester.tap(find.text('Apagar').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Lunes a viernes'));
        await tester.tap(find.text('Lunes a viernes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        expect(find.text('Autorizar programación'), findsOneWidget);
        expect(c.schedules, isEmpty);
        await tester.tap(find.text('Confirmar'));
        await tester.pumpAndSettle();
        expect(c.schedules.single.action, ScheduledAction.stop);
        expect(c.schedules.single.days, [1, 2, 3, 4, 5]);
        await tester.ensureVisible(find.text('Editar'));
        await tester.tap(find.text('Editar'));
        await tester.pumpAndSettle();
        expect(find.text('Editar programación'), findsOneWidget);
        await tester.tap(find.byType(DropdownButtonFormField<ScheduledAction>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Encender').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirmar'));
        await tester.pumpAndSettle();
        expect(c.schedules.length, 1);
        expect(c.schedules.single.action, ScheduledAction.start);
        await tester.ensureVisible(find.byType(Switch));
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(c.schedules.single.enabled, isFalse);
        expect(find.text('Programación pausada'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
