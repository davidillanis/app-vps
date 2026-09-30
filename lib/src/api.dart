import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';
class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
class CloudingApi {
  CloudingApi({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  static const base = 'https://api.clouding.io/v1';
  Future<Map<String, dynamic>> request(String key, String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final req = http.Request(method, Uri.parse('$base$path'));
    req.headers.addAll({'X-API-KEY': key, 'Content-Type': 'application/json'});
    if (body != null) req.body = jsonEncode(body);
    http.Response response;
    try {
      response = await (() async => http.Response.fromStream(await client.send(req)))()
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw ApiException('No se pudo conectar. Revisa la red y, en Web, CORS. Si enviaste una operación, actualiza antes de repetirla: su resultado es incierto.');
    }
    Map<String, dynamic> data = {};
    if (response.body.isNotEmpty) {
      try { data = jsonDecode(response.body) as Map<String, dynamic>; }
      catch (_) { throw ApiException('Respuesta inválida de Clouding (${response.statusCode}).'); }
    }
    if (response.statusCode >= 400) {
      final message = switch (response.statusCode) {
        401 => 'API KEY inválida o revocada.',
        403 => 'Tu API KEY no tiene permisos para esta operación.',
        429 => 'Límite de solicitudes alcanzado. Espera antes de actualizar.',
        _ => 'Clouding devolvió un error (${response.statusCode}).',
      };
      throw ApiException('$message ${data['detail'] ?? data['title'] ?? ''}');
    }
    return data;
  }
  Future<List<Server>> servers(String key) async {
    final result = <Server>[];
    for (var page = 1; ; page++) {
      final data = await request(key, '/servers?page=$page&pageSize=200');
      if (data['servers'] is! List) throw ApiException('Listado de servidores inválido.');
      result.addAll((data['servers'] as List).map((s) => Server(Map<String, dynamic>.from(s))));
      if ((data['links'] as Map?)?['next'] == null) break;
    }
    return result;
  }
  Future<Server> detail(String key, String id) async => Server(await request(key, '/servers/${Uri.encodeComponent(id)}'));
  Future<Map<String, dynamic>> action(String key, String id, String action) =>
      request(key, '/servers/${Uri.encodeComponent(id)}/$action', method: 'POST');
  Future<void> rename(String key, String id, String name) async {
    await request(key, '/servers/${Uri.encodeComponent(id)}/rename', method: 'PATCH', body: {'newServerName': name});
  }
}
