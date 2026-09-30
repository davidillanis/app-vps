import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_vps/src/api.dart';
import 'package:app_vps/src/models.dart';

void main() {
  test('Recorre todas las páginas sin seguir enlaces a otros hosts', () async {
    final requests = <http.Request>[];
    final api = CloudingApi(
      client: MockClient((r) async {
        requests.add(r);
        final page = r.url.queryParameters['page'];
        return http.Response(
          jsonEncode({
            'servers': [
              {'id': page, 'name': 'fixture'},
            ],
            'links': {
              'next': page == '1' ? 'https://untrusted.invalid/' : null,
            },
          }),
          200,
        );
      }),
    );
    final servers = await api.servers('test-key');
    expect(servers.map((s) => s.id), ['1', '2']);
    expect(
      requests.every(
        (r) =>
            r.url.host == 'api.clouding.io' &&
            r.headers['X-API-KEY'] == 'test-key',
      ),
      isTrue,
    );
  });
  test(
    'Renombrado usa PATCH y newServerName, sin credenciales en URL',
    () async {
      final api = CloudingApi(
        client: MockClient((r) async {
          expect(r.method, 'PATCH');
          expect(r.url.path, '/v1/servers/server-id/rename');
          expect(jsonDecode(r.body), {'newServerName': 'Nuevo nombre'});
          expect(r.url.toString(), isNot(contains('test-key')));
          return http.Response('', 204);
        }),
      );
      await api.rename('test-key', 'server-id', 'Nuevo nombre');
    },
  );
  test('401 y 429 producen mensajes accionables', () async {
    for (final status in [401, 429]) {
      final api = CloudingApi(
        client: MockClient((r) async => http.Response('{}', status)),
      );
      await expectLater(api.servers('test-key'), throwsA(isA<ApiException>()));
    }
  });
  test('Programación respeta días, minuto y un intento por fecha', () {
    final schedule = ServerSchedule(
      id: 'fixture',
      serverId: 'server',
      days: [1, 3],
      hour: 22,
      minute: 30,
    );
    final now = DateTime(2026, 9, 30, 22, 30);
    expect(schedule.due(now), isTrue);
    expect(schedule.due(now.add(const Duration(minutes: 1))), isFalse);
    schedule.lastRun = schedule.occurrence(now);
    expect(schedule.due(now), isFalse);
    expect(
      ServerSchedule.fromJson(schedule.toJson()).lastRun,
      schedule.lastRun,
    );
    schedule.enabled = false;
    expect(schedule.due(DateTime(2026, 10, 5, 22, 30)), isFalse);
  });
  test('IP modernas y costes ausentes no se inventan', () {
    final s = Server({
      'id': 'fixture',
      'publicPorts': [
        {'ipAddress': '192.0.2.1'},
      ],
      'vpcPorts': [
        {'ipAddress': '10.0.0.1'},
      ],
    });
    expect(s.ips, ['192.0.2.1', '10.0.0.1']);
    expect(s.cost, isNull);
    expect(s.cpu, isNull);
  });
}
