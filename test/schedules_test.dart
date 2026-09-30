import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_vps/src/api.dart';
import 'package:app_vps/src/controller.dart';
import 'package:app_vps/src/key_storage.dart';
import 'package:app_vps/src/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 30, 22, 30);
  ServerSchedule rule(
    ScheduledAction action, {
    String id = 'rule',
    bool enabled = true,
  }) => ServerSchedule(
    id: id,
    serverId: 'server',
    days: [3],
    hour: 22,
    minute: 30,
    action: action,
    enabled: enabled,
  );
  Map<String, dynamic> state(String status, String power) => {
    'id': 'server',
    'name': 'Fixture',
    'status': status,
    'powerState': power,
  };
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Las reglas antiguas conservan el archivado y la última ocurrencia', () {
    final s = ServerSchedule.fromJson({
      'id': 'old',
      'serverId': 'server',
      'days': [3],
      'hour': 22,
      'minute': 30,
      'enabled': true,
      'lastRun': '2026-9-30',
    });
    expect(s.action, ScheduledAction.archive);
    expect(s.due(now), isFalse);
    expect(s.nextOccurrence(now), DateTime(2026, 10, 7, 22, 30));
  });
  test(
    'Calcula próxima ejecución y no propone horarios pasados o pausados',
    () {
      final s = rule(ScheduledAction.stop);
      expect(s.nextOccurrence(now), now);
      expect(
        s.nextOccurrence(now.add(const Duration(minutes: 1))),
        DateTime(2026, 10, 7, 22, 30),
      );
      s.enabled = false;
      expect(s.nextOccurrence(now), isNull);
    },
  );

  for (final action in ScheduledAction.values) {
    test(
      '${action.label}: envía la ruta correcta una vez, sigue progreso y guarda resultado',
      () async {
        var posts = 0;
        final server = action == ScheduledAction.unarchive
            ? state('Archived', 'Shutdown')
            : action == ScheduledAction.start
            ? state('Stopped', 'Shutdown')
            : state('Active', 'Running');
        final api = CloudingApi(
          client: MockClient((request) async {
            if (request.method == 'POST') {
              posts++;
              expect(request.url.path, '/v1/servers/server/${action.name}');
              return http.Response(
                '{"id":"action-id","status":"inProgress"}',
                202,
              );
            }
            if (request.url.path.startsWith('/v1/actions/')) {
              return http.Response('{"status":"completed"}', 200);
            }
            return http.Response(
              jsonEncode(
                request.url.path == '/v1/servers'
                    ? {
                        'servers': [server],
                        'links': {'next': null},
                      }
                    : server,
              ),
              200,
            );
          }),
        );
        VpsController create() => VpsController(
          api: api,
          keyStorage: ApiKeyStorage(browser: true),
          clock: () => now,
        );
        final c = create();
        await c.initialize();
        await c.connect('fixture-key');
        await c.saveSchedule(rule(action));
        await c.tick();
        expect(posts, 1);
        expect(c.schedules.single.lastResult, 'En curso');
        expect(c.schedules.single.lastActionId, 'action-id');
        await c.tick();
        expect(posts, 1);
        expect(c.schedules.single.lastResult, 'Completada');
        final prefs = await SharedPreferences.getInstance();
        final saved = ServerSchedule.fromJson(
          (jsonDecode(prefs.getString('schedules')!) as List).single,
        );
        expect(saved.lastResult, 'Completada');
        expect(saved.action, action);
        c.dispose();
        final restored = VpsController(
          api: CloudingApi(
            client: MockClient((request) async {
              expect(request.method, 'GET');
              return http.Response(
                jsonEncode({
                  'servers': [server],
                  'links': {'next': null},
                }),
                200,
              );
            }),
          ),
          keyStorage: ApiKeyStorage(browser: true),
          clock: () => now,
        );
        await restored.initialize();
        await restored.tick();
        expect(restored.schedules.single.due(now), isFalse);
        restored.dispose();
      },
    );
  }

  test(
    'Omite estados ya alcanzados, archivados y transitorios sin escribir',
    () async {
      for (final entry in [
        (ScheduledAction.start, 'Active', 'Running'),
        (ScheduledAction.start, 'Archived', 'Shutdown'),
        (ScheduledAction.stop, 'Stopped', 'Shutdown'),
        (ScheduledAction.archive, 'Archived', 'Shutdown'),
        (ScheduledAction.unarchive, 'Active', 'Running'),
        (ScheduledAction.archive, 'Archiving', 'Shutdown'),
      ]) {
        SharedPreferences.setMockInitialValues({});
        final server = state(entry.$2, entry.$3);
        final c = VpsController(
          api: CloudingApi(
            client: MockClient((request) async {
              expect(request.method, 'GET');
              return http.Response(
                jsonEncode(
                  request.url.path == '/v1/servers'
                      ? {
                          'servers': [server],
                          'links': {'next': null},
                        }
                      : server,
                ),
                200,
              );
            }),
          ),
          keyStorage: ApiKeyStorage(browser: true),
          clock: () => now,
        );
        await c.initialize();
        await c.connect('fixture-key');
        await c.saveSchedule(rule(entry.$1));
        await c.tick();
        expect(c.schedules.single.lastResult, startsWith('Omitida:'));
        c.dispose();
      }
    },
  );

  test('Conflictos al guardar, editar o reactivar; pausar permite guardar otra regla', () async {
    final c = VpsController(
      api: CloudingApi(
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({
              'servers': [state('Active', 'Running')],
              'links': {'next': null},
            }),
            200,
          ),
        ),
      ),
      keyStorage: ApiKeyStorage(browser: true),
      clock: () => now,
    );
    await c.initialize();
    await c.connect('fixture-key');
    await c.saveSchedule(rule(ScheduledAction.stop));
    await expectLater(
      c.saveSchedule(rule(ScheduledAction.start, id: 'other')),
      throwsArgumentError,
    );
    expect(c.schedules.length, 1);
    await c.setScheduleEnabled(c.schedules.single, false);
    await c.saveSchedule(rule(ScheduledAction.start, id: 'other'));
    await expectLater(
      c.setScheduleEnabled(c.schedules.first, true),
      throwsArgumentError,
    );
    expect(c.schedules.first.enabled, isFalse);
    final edit = ServerSchedule(
      id: 'other',
      serverId: 'server',
      days: [1, 2, 3],
      hour: 8,
      minute: 0,
      action: ScheduledAction.unarchive,
    );
    await c.saveSchedule(edit);
    expect(c.schedules.length, 2);
    expect(c.schedules.last.hour, 8);
    expect(c.schedules.last.action, ScheduledAction.unarchive);
    c.dispose();
  });

  test(
    'Reglas antiguas en conflicto se omiten sin enviar ninguna acción',
    () async {
      final c = VpsController(
        api: CloudingApi(
          client: MockClient((r) async {
            expect(r.method, 'GET');
            return http.Response(
              jsonEncode({
                'servers': [state('Active', 'Running')],
                'links': {'next': null},
              }),
              200,
            );
          }),
        ),
        keyStorage: ApiKeyStorage(browser: true),
        clock: () => now,
      );
      await c.initialize();
      await c.connect('fixture-key');
      c.schedules.addAll([
        rule(ScheduledAction.stop),
        rule(ScheduledAction.archive, id: 'duplicate'),
      ]);
      await c.persistSchedules();
      await c.tick();
      expect(
        c.schedules.every((s) => s.lastResult!.contains('conflicto')),
        isTrue,
      );
      c.dispose();
    },
  );
  test(
    'Error de red conserva el intento y no reenvía al siguiente tick',
    () async {
      var writes = 0;
      final server = state('Active', 'Running');
      final c = VpsController(
        api: CloudingApi(
          client: MockClient((r) async {
            if (r.method == 'POST') {
              writes++;
              throw http.ClientException('fixture network error');
            }
            return http.Response(
              jsonEncode(
                r.url.path == '/v1/servers'
                    ? {
                        'servers': [server],
                        'links': {'next': null},
                      }
                    : server,
              ),
              200,
            );
          }),
        ),
        keyStorage: ApiKeyStorage(browser: true),
        clock: () => now,
      );
      await c.initialize();
      await c.connect('fixture-key');
      await c.saveSchedule(rule(ScheduledAction.stop));
      await c.tick();
      await c.tick();
      expect(writes, 1);
      expect(c.schedules.single.lastResult, startsWith('Error:'));
      expect(c.progress['server'], 'Revisar resultado');
      c.dispose();
    },
  );
}
