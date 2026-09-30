import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'models.dart';
class VpsController extends ChangeNotifier {
  VpsController({CloudingApi? api}) : api = api ?? CloudingApi();
  final CloudingApi api;
  final _secure = const FlutterSecureStorage();
  SharedPreferences? _prefs;
  String _key = '';
  bool initialized = false, loading = false, configuring = false, foreground = true;
  String? error;
  DateTime? updatedAt;
  ThemeMode theme = ThemeMode.system;
  List<Server> servers = [];
  List<ArchiveSchedule> schedules = [];
  final Map<String, String> progress = {}, pendingActions = {};
  final List<String> activity = [];
  Timer? _timer;
  bool _ticking = false;
  bool get connected => _key.isNotEmpty;
  bool get busy => loading || configuring || progress.isNotEmpty || _ticking;
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      theme = ThemeMode.values[_prefs!.getInt('theme') ?? 0];
      schedules = (jsonDecode(_prefs!.getString('schedules') ?? '[]') as List)
          .map((s) => ArchiveSchedule.fromJson(Map<String, dynamic>.from(s))).toList();
      if (!kIsWeb) _key = await _secure.read(key: 'clouding_api_key') ?? '';
    } catch (_) { error = 'No se pudo leer la configuración local.'; }
    initialized = true; notifyListeners();
    if (connected) await refresh();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => tick());
  }
  Future<void> setTheme(ThemeMode value) async {
    theme = value; notifyListeners(); await _prefs?.setInt('theme', value.index);
  }
  Future<void> connect(String key) async {
    if (busy) return;
    configuring = true; error = null; notifyListeners();
    try {
      final result = await api.servers(key.trim());
      if (!kIsWeb) await _secure.write(key: 'clouding_api_key', value: key.trim());
      if (_key != key.trim()) { schedules.clear(); await persistSchedules(); }
      _key = key.trim(); servers = result; updatedAt = DateTime.now();
    } catch (e) { error = e.toString(); }
    finally { configuring = false; notifyListeners(); }
  }
  Future<void> disconnect() async {
    if (busy) return;
    try {
      if (!kIsWeb) await _secure.delete(key: 'clouding_api_key');
      _key = ''; servers = []; updatedAt = null; error = null;
      schedules.clear(); await persistSchedules();
    } catch (_) { error = 'No se pudo eliminar la clave del almacenamiento seguro.'; }
    notifyListeners();
  }
  Future<void> refresh() async {
    if (!connected || loading || configuring) return;
    loading = true; error = null; notifyListeners();
    try { servers = await api.servers(_key); updatedAt = DateTime.now(); }
    catch (e) { error = e.toString(); }
    finally { loading = false; notifyListeners(); }
  }
  Future<Server> detail(Server server) async {
    final result = await api.detail(_key, server.id);
    final index = servers.indexWhere((s) => s.id == server.id);
    if (index >= 0) servers[index] = result;
    notifyListeners(); return result;
  }
  Future<void> operate(Server server, String action, {String? name}) async {
    if (progress.containsKey(server.id) || !connected || configuring) return;
    progress[server.id] = 'Enviando…'; error = null; notifyListeners();
    try {
      if (action == 'rename') {
        await api.rename(_key, server.id, name!);
        progress.remove(server.id); await refresh();
      } else {
        final result = await api.action(_key, server.id, action);
        final id = result['id'] as String?;
        if (id == null) throw ApiException('Operación enviada sin identificador. Actualiza antes de repetir.');
        pendingActions[server.id] = id;
        progress[server.id] = result['status'] as String? ?? 'pending';
      }
      log('${server.name}: $action solicitado.');
    } catch (e) {
      progress[server.id] = 'Revisar resultado';
      error = e.toString(); log('${server.name}: $error');
    }
    notifyListeners();
  }
  Future<void> reconcile(String id) async {
    await refresh();
    if (error == null && !pendingActions.containsKey(id)) progress.remove(id);
    notifyListeners();
  }
  void log(String message) {
    activity.insert(0, '${DateTime.now().toLocal().toString().substring(0, 19)} · $message');
    if (activity.length > 50) activity.removeLast();
  }
  Future<void> persistSchedules() async {
    await _prefs?.setString('schedules', jsonEncode(schedules.map((s) => s.toJson()).toList()));
  }
  Future<void> addSchedule(ArchiveSchedule schedule) async {
    schedules.add(schedule); await persistSchedules(); notifyListeners();
  }
  Future<void> removeSchedule(ArchiveSchedule schedule) async {
    schedules.remove(schedule); await persistSchedules(); notifyListeners();
  }
  Future<void> tick() async {
    if (_ticking || !connected || !foreground || configuring) return;
    _ticking = true;
    try {
      for (final entry in pendingActions.entries.toList()) {
        try {
          final result = await api.request(_key, '/actions/${Uri.encodeComponent(entry.value)}');
          final status = result['status'] as String? ?? 'Unknown';
          progress[entry.key] = status;
          if (status == 'completed' || status == 'errored') {
            pendingActions.remove(entry.key); progress.remove(entry.key);
            log('Operación ${entry.value}: $status');
            await refresh();
            if (status == 'errored') error = 'Clouding informó que la operación falló.';
          }
        } catch (e) { error = 'No se pudo consultar el progreso: $e'; }
      }
      final now = DateTime.now();
      for (final schedule in schedules.where((s) => s.due(now)).toList()) {
        schedule.lastRun = schedule.occurrence(now);
        await persistSchedules();
        try {
          if (progress.containsKey(schedule.serverId)) {
            log('Programación omitida: servidor con operación pendiente.'); continue;
          }
          final server = await api.detail(_key, schedule.serverId);
          if (server.archived) { log('${server.name}: ya está archivado.'); continue; }
          if (!server.stable) { log('${server.name}: archivado omitido por estado ${server.status}.'); continue; }
          await operate(server, 'archive');
        } catch (e) { error = e.toString(); log('Programación fallida: $e'); }
      }
    } finally { _ticking = false; notifyListeners(); }
  }
  @override
  void dispose() { _timer?.cancel(); api.client.close(); super.dispose(); }
}
