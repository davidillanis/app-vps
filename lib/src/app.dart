import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'models.dart';

const dayNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const actionNames = {
  'start': 'Encender',
  'stop': 'Apagar',
  'reboot': 'Reiniciar',
  'archive': 'Archivar',
  'unarchive': 'Desarchivar',
  'rename': 'Cambiar nombre',
};

class VpsApp extends StatelessWidget {
  const VpsApp({super.key, required this.controller});
  final VpsController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => MaterialApp(
      title: 'app_vps',
      debugShowCheckedModeBanner: false,
      themeMode: controller.theme,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: VpsHome(controller: controller),
    ),
  );
  ThemeData theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff4263eb),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xfff5f7fc)
          : const Color(0xff10131c),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class VpsHome extends StatefulWidget {
  const VpsHome({super.key, required this.controller});
  final VpsController controller;
  @override
  State<VpsHome> createState() => _VpsHomeState();
}

class _VpsHomeState extends State<VpsHome> with WidgetsBindingObserver {
  VpsController get c => widget.controller;
  int page = 0;
  String query = '';
  String filter = 'Todos';
  bool detailsLoading = false;
  final keyInput = TextEditingController();
  bool obscure = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    c.foreground = state == AppLifecycleState.resumed;
    if (c.foreground) c.tick();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    keyInput.dispose();
    super.dispose();
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;
  void toast(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> action(Server server, String action) async {
    String? newName;
    if (action == 'rename') {
      final input = TextEditingController(text: server.name);
      newName = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cambiar nombre'),
          content: TextField(
            controller: input,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nuevo nombre'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (input.text.trim().isNotEmpty) {
                  Navigator.pop(context, input.text.trim());
                }
              },
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      input.dispose();
      if (newName == null || !mounted) return;
    }
    final message = action == 'rename'
        ? '${server.name} pasará a llamarse "$newName".'
        : '${actionNames[action]} el servidor ${server.name}.'
              '${['stop', 'reboot', 'archive'].contains(action) ? '\nSus servicios pueden dejar de estar disponibles.' : ''}'
              '${action == 'unarchive' ? '\nClouding volverá a aplicar el coste del servidor activo.' : ''}';
    if (!await confirm('${actionNames[action]} servidor', message) ||
        !mounted) {
      return;
    }
    await c.operate(server, action, name: newName);
  }

  Future<void> showDetails(Server server) async {
    setState(() => detailsLoading = true);
    try {
      final result = await c.detail(server);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(result.name),
          content: SizedBox(
            width: 550,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  info('ID', result.id),
                  info(
                    'Estado',
                    '${result.status} · ${result.data['powerState'] ?? 'No disponible'}',
                  ),
                  info('Hostname', result.data['hostname']),
                  info('Sistema', (result.data['image'] as Map?)?['name']),
                  info('Direcciones IP', result.ips.join('\n')),
                  info('DNS', result.data['dnsAddress']),
                  info('Creado', result.data['createdAt']),
                  info(
                    'CPU / RAM / SSD',
                    '${result.cpu ?? '—'} vCPU · ${result.ram ?? '—'} GB · ${result.disk ?? '—'} GB',
                  ),
                  info(
                    'Precio por hora',
                    price(result.cost?['pricePerHour'], 6),
                  ),
                  info(
                    'Precio mensual aproximado',
                    price(result.cost?['pricePerMonthApprox'], 2),
                  ),
                  info('Backups', (result.data['backups'] as List?)?.length),
                  info(
                    'Snapshots',
                    (result.data['snapshots'] as List?)?.length,
                  ),
                  info(
                    'Características',
                    (result.data['features'] as List?)?.join(', '),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Recursos asignados, no uso en tiempo real. La API no documenta métricas de CPU/RAM ni consumo de tráfico.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      toast(e.toString());
    } finally {
      if (mounted) setState(() => detailsLoading = false);
    }
  }

  Widget info(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        SelectableText(
          value == null || value.toString().isEmpty
              ? 'No disponible'
              : value.toString(),
        ),
      ],
    ),
  );
  String price(Object? value, int decimals) =>
      value is num ? '${value.toStringAsFixed(decimals)} €' : 'No disponible';

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final titles = [
      'Servidores',
      'Costes y consumo',
      'Programaciones',
      'Configuración',
    ];
    final destinations = [
      const NavigationDestination(
        icon: Icon(Icons.dns_outlined),
        selectedIcon: Icon(Icons.dns),
        label: 'Servidores',
      ),
      const NavigationDestination(
        icon: Icon(Icons.payments_outlined),
        label: 'Costes',
      ),
      const NavigationDestination(
        icon: Icon(Icons.schedule_outlined),
        label: 'Programaciones',
      ),
      const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        label: 'Configuración',
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('app_vps / ${titles[page]}'),
        actions: [
          IconButton(
            tooltip: 'Cambiar tema',
            onPressed: () => c.setTheme(
              c.theme == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
            ),
            icon: Icon(
              c.theme == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Actualizar servidores',
            onPressed: c.connected && !c.loading && !c.configuring
                ? c.refresh
                : null,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 12),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: page,
              onDestinationSelected: (v) => setState(() => page = v),
              destinations: destinations,
            ),
      body: Row(
        children: [
          if (wide)
            NavigationRail(
              extended: true,
              selectedIndex: page,
              leading: const Padding(
                padding: EdgeInsets.all(18),
                child: Icon(Icons.cloud_outlined, size: 36),
              ),
              onDestinationSelected: (v) => setState(() => page = v),
              destinations: destinations
                  .map(
                    (d) => NavigationRailDestination(
                      icon: d.icon,
                      label: Text(d.label),
                    ),
                  )
                  .toList(),
            ),
          Expanded(
            child: Column(
              children: [
                if (c.loading || c.configuring || detailsLoading)
                  const LinearProgressIndicator(),
                if (c.error != null)
                  MaterialBanner(
                    content: Text(c.error!),
                    leading: const Icon(Icons.error_outline),
                    actions: [
                      TextButton(
                        onPressed: () {
                          c.error = null;
                          setState(() {});
                        },
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
                Expanded(
                  child: !c.initialized
                      ? const Center(child: CircularProgressIndicator())
                      : Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1400),
                            child: SingleChildScrollView(
                              padding: EdgeInsets.all(wide ? 32 : 16),
                              child: switch (page) {
                                1 => costs(),
                                2 => schedules(),
                                3 => settings(),
                                _ => dashboard(),
                              },
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
  Widget empty(String title, String description, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(description, textAlign: TextAlign.center),
            if (!c.connected)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: FilledButton(
                  onPressed: () => setState(() => page = 3),
                  child: const Text('Configurar API KEY'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  Widget stat(String label, String value, IconData icon) => SizedBox(
    width: 220,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label),
          ],
        ),
      ),
    ),
  );
  Widget dashboard() {
    final list = c.servers
        .where(
          (s) =>
              '${s.name} ${s.ips.join(' ')}'.toLowerCase().contains(
                query.toLowerCase(),
              ) &&
              (filter == 'Todos' ||
                  (filter == 'Archivados'
                      ? s.archived
                      : s.running && !s.archived)),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'Tu infraestructura, a un vistazo',
          c.updatedAt == null
              ? 'Conecta tu cuenta de Clouding para comenzar.'
              : 'Última actualización: ${c.updatedAt!.toLocal().toString().substring(0, 19)}',
        ),
        if (!c.connected)
          empty(
            'Conecta tus servidores',
            'Introduce tu API KEY. Los datos se consultan directamente en Clouding.',
            Icons.cloud_outlined,
          )
        else ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              stat('Servidores', '${c.servers.length}', Icons.dns_outlined),
              stat(
                'En ejecución',
                '${c.servers.where((s) => s.running && !s.archived).length}',
                Icons.power_settings_new,
              ),
              stat(
                'Archivados',
                '${c.servers.where((s) => s.archived).length}',
                Icons.inventory_2_outlined,
              ),
              stat(
                'RAM asignada',
                '${c.servers.fold<num>(0, (v, s) => v + (s.ram ?? 0))} GB',
                Icons.memory,
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar por nombre o IP',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: ['Todos', 'En ejecución', 'Archivados']
                .map(
                  (v) => ChoiceChip(
                    label: Text(v),
                    selected: filter == v,
                    onSelected: (_) => setState(() => filter = v),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
          if (list.isEmpty)
            empty(
              'Sin servidores',
              c.servers.isEmpty
                  ? 'Clouding no devolvió servidores para esta cuenta.'
                  : 'No hay coincidencias con el filtro.',
              Icons.dns_outlined,
            )
          else
            LayoutBuilder(
              builder: (context, box) {
                final columns = box.maxWidth >= 1050
                    ? 3
                    : box.maxWidth >= 650
                    ? 2
                    : 1;
                final width = (box.maxWidth - 16 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: list
                      .map((s) => SizedBox(width: width, child: serverCard(s)))
                      .toList(),
                );
              },
            ),
        ],
        if (c.activity.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text(
            'Actividad reciente',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          ...c.activity
              .take(10)
              .map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(s),
                ),
              ),
        ],
      ],
    );
  }

  Widget serverCard(Server s) {
    final pending = c.progress[s.id];
    final actions = s.archived
        ? ['unarchive', 'rename']
        : [
            if (!s.running) 'start',
            if (s.running) ...['stop', 'reboot'],
            'archive',
            'rename',
          ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.dns_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.name,
                    style: Theme.of(context).textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<String>(
                  enabled: pending == null && s.stable,
                  onSelected: (v) => action(s, v),
                  itemBuilder: (_) => actions
                      .map(
                        (a) => PopupMenuItem(
                          value: a,
                          child: Text(actionNames[a]!),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Chip(
              avatar: Icon(
                s.archived
                    ? Icons.inventory_2_outlined
                    : s.running
                    ? Icons.circle
                    : Icons.pause_circle_outline,
                size: 14,
                color: s.running && !s.archived ? Colors.green : null,
              ),
              label: Text('${s.status} · ${s.data['powerState'] ?? '—'}'),
            ),
            const SizedBox(height: 12),
            SelectableText(
              s.ips.isEmpty ? 'IP no disponible' : s.ips.join('\n'),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text('${s.cpu ?? '—'} vCPU'),
                Text('${s.ram ?? '—'} GB RAM'),
                Text('${s.disk ?? '—'} GB SSD'),
              ],
            ),
            if (pending != null) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(pending),
              if (pending == 'Revisar resultado')
                TextButton(
                  onPressed: () async {
                    if (await confirm(
                      'Revisar operación',
                      'Se actualizará el estado y se desbloqueará el servidor. Comprueba el resultado antes de repetir la acción.',
                    )) {
                      await c.reconcile(s.id);
                    }
                  },
                  child: const Text('Actualizar y revisar'),
                ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: detailsLoading ? null : () => showDetails(s),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Ver detalles'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> loadCosts() async {
    setState(() => detailsLoading = true);
    try {
      for (final server in c.servers.toList()) {
        await c.detail(server);
      }
    } catch (e) {
      toast(e.toString());
    } finally {
      if (mounted) setState(() => detailsLoading = false);
    }
  }

  Widget costs() {
    final known = c.servers
        .where((s) => s.cost?['pricePerMonthApprox'] is num)
        .toList();
    final total = known.fold<num>(
      0,
      (v, s) => v + (s.cost?['pricePerMonthApprox'] as num? ?? 0),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'Costes transparentes',
          'Precios devueltos por Clouding. El importe mensual es aproximado, no una factura.',
        ),
        if (!c.connected)
          empty(
            'Conecta tu cuenta',
            'Consulta los precios reales de tus servidores.',
            Icons.payments_outlined,
          )
        else ...[
          FilledButton.icon(
            onPressed: detailsLoading || c.loading ? null : loadCosts,
            icon: const Icon(Icons.refresh),
            label: const Text('Consultar costes actuales'),
          ),
          const SizedBox(height: 20),
          stat(
            'Mensual aproximado (${known.length}/${c.servers.length})',
            known.isEmpty ? 'No disponible' : price(total, 2),
            Icons.payments_outlined,
          ),
          const SizedBox(height: 20),
          ...c.servers.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: ListTile(
                  title: Text(s.name),
                  subtitle: Text(
                    'Por hora: ${price(s.cost?['pricePerHour'], 6)}\nMensual aprox.: ${price(s.cost?['pricePerMonthApprox'], 2)}',
                  ),
                  isThreeLine: true,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Consumo real de CPU, RAM, disco y tráfico: no disponible en los endpoints documentados. Las tarjetas muestran capacidad asignada. No se calculan facturas ni ahorros ficticios.',
          ),
        ],
      ],
    );
  }

  IconData scheduleIcon(ScheduledAction action) => switch (action) {
    ScheduledAction.start => Icons.power_settings_new,
    ScheduledAction.stop => Icons.power_off_outlined,
    ScheduledAction.archive => Icons.archive_outlined,
    ScheduledAction.unarchive => Icons.unarchive_outlined,
  };

  Future<void> createSchedule([ServerSchedule? existing]) async {
    if (c.servers.isEmpty) return;
    var serverId = existing?.serverId ?? c.servers.first.id;
    var selectedAction = existing?.action ?? ScheduledAction.archive;
    var time = TimeOfDay(
      hour: existing?.hour ?? 22,
      minute: existing?.minute ?? 0,
    );
    final days = {...?existing?.days};
    String? validation;
    ServerSchedule candidate() => ServerSchedule(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      serverId: serverId,
      action: selectedAction,
      days: days.toList()..sort(),
      hour: time.hour,
      minute: time.minute,
      enabled: existing?.enabled ?? true,
      lastRun: existing?.lastRun,
      lastAttemptAt: existing?.lastAttemptAt,
      lastResult: existing?.lastResult,
      lastActionId: existing?.lastActionId,
    );
    final result = await showDialog<ServerSchedule>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            existing == null ? 'Nueva programación' : 'Editar programación',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: serverId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Servidor'),
                    items: [
                      if (!c.servers.any((s) => s.id == serverId))
                        DropdownMenuItem(
                          value: serverId,
                          child: const Text('Servidor no disponible'),
                        ),
                      ...c.servers.map(
                        (s) => DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (value) => update(() {
                      serverId = value!;
                      validation = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<ScheduledAction>(
                    initialValue: selectedAction,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Acción automática',
                    ),
                    items: ScheduledAction.values
                        .map(
                          (a) => DropdownMenuItem(
                            value: a,
                            child: Row(
                              children: [
                                Icon(scheduleIcon(a), size: 20),
                                const SizedBox(width: 10),
                                Text(a.label),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => update(() {
                      selectedAction = value!;
                      validation = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  const Text('Repetir los días'),
                  Wrap(
                    spacing: 6,
                    children: List.generate(
                      7,
                      (i) => FilterChip(
                        label: Text(dayNames[i]),
                        selected: days.contains(i + 1),
                        onSelected: (selected) => update(() {
                          if (selected) {
                            days.add(i + 1);
                          } else {
                            days.remove(i + 1);
                          }
                          validation = null;
                        }),
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => update(() {
                          days.addAll([1, 2, 3, 4, 5, 6, 7]);
                          validation = null;
                        }),
                        child: const Text('Todos los días'),
                      ),
                      TextButton(
                        onPressed: () => update(() {
                          days.clear();
                          days.addAll([1, 2, 3, 4, 5]);
                          validation = null;
                        }),
                        child: const Text('Lunes a viernes'),
                      ),
                      TextButton(
                        onPressed: () => update(() {
                          days.clear();
                          days.addAll([6, 7]);
                          validation = null;
                        }),
                        child: const Text('Fin de semana'),
                      ),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final value = await showTimePicker(
                        context: context,
                        initialTime: time,
                        helpText: 'Hora de ejecución',
                      );
                      if (value != null && context.mounted) {
                        update(() {
                          time = value;
                          validation = null;
                        });
                      }
                    },
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      'Hora: ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(selectedAction.warning),
                  const SizedBox(height: 12),
                  const Text(
                    'Se repetirá cada semana en la hora local del dispositivo, con la app abierta y activa. La confirmación autoriza las futuras ejecuciones.',
                  ),
                  if (validation != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        validation!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: days.isEmpty
                  ? null
                  : () {
                      final value = candidate();
                      final problem = c.scheduleError(value);
                      if (problem != null) {
                        update(() => validation = problem);
                        return;
                      }
                      Navigator.pop(context, value);
                    },
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    final name = c.servers.firstWhere((s) => s.id == result.serverId).name;
    if (!await confirm(
          'Autorizar programación',
          '${result.action.label} "$name"\n${result.days.map((d) => dayNames[d - 1]).join(', ')} a las ${result.hour.toString().padLeft(2, '0')}:${result.minute.toString().padLeft(2, '0')} (hora local).\n\n${result.action.warning}\n\n${result.enabled ? 'Esta regla se activará al guardar.' : 'La regla seguirá pausada.'}',
        ) ||
        !mounted) {
      return;
    }
    try {
      await c.saveSchedule(result);
      toast('Programación guardada.');
    } catch (e) {
      toast(e.toString());
    }
  }

  Widget schedules() {
    final rules = c.schedules.toList()
      ..sort((a, b) {
        final left = a.nextOccurrence(c.clock());
        final right = b.nextOccurrence(c.clock());
        if (left == null) return right == null ? a.id.compareTo(b.id) : 1;
        return right == null ? -1 : left.compareTo(right);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'Automatiza tus servidores',
          'Encendido, apagado, archivado y desarchivado semanal. Hora local: ${c.clock().timeZoneName}.',
        ),
        if (!c.connected)
          empty(
            'Conecta tu cuenta',
            'Consulta tus servidores antes de programar.',
            Icons.schedule,
          )
        else ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: c.servers.isEmpty ? null : () => createSchedule(),
                icon: const Icon(Icons.add),
                label: const Text('Nueva programación'),
              ),
              Text(
                '${rules.where((s) => s.enabled).length} activas · ${rules.where((s) => !s.enabled).length} pausadas',
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (rules.isEmpty)
            empty(
              'Sin programaciones',
              'Elige un servidor, una acción, los días y la hora.',
              Icons.event_outlined,
            ),
          ...rules.map((s) {
            final names = c.servers.where((v) => v.id == s.serverId);
            final next = s.nextOccurrence(c.clock());
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            scheduleIcon(s.action),
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${s.action.label} · ${names.isEmpty ? s.serverId : names.first.name}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${s.days.map((d) => dayNames[d - 1]).join(', ')} · ${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        next == null
                            ? 'Programación pausada'
                            : 'Próxima ejecución: ${next.toString().substring(0, 16)}',
                      ),
                      if (s.lastAttemptAt != null || s.lastRun != null)
                        Text(
                          'Último intento: ${s.lastAttemptAt?.replaceFirst('T', ' ').substring(0, 16) ?? s.lastRun}',
                        ),
                      if (s.lastResult != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('Resultado: ${s.lastResult}'),
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: s.enabled,
                                onChanged: (enabled) async {
                                  if (enabled &&
                                      !await confirm(
                                        'Activar programación',
                                        '${s.action.label} este servidor automáticamente en los días y hora guardados.\n\n${s.action.warning}',
                                      )) {
                                    return;
                                  }
                                  try {
                                    await c.setScheduleEnabled(s, enabled);
                                  } catch (e) {
                                    toast(e.toString());
                                  }
                                },
                              ),
                              Text(s.enabled ? 'Activa' : 'Pausada'),
                            ],
                          ),
                          TextButton.icon(
                            onPressed: () => createSchedule(s),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Editar'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              if (!await confirm(
                                'Eliminar programación',
                                'Esta regla dejará de ejecutarse. Las operaciones ya enviadas continuarán en Clouding.',
                              )) {
                                return;
                              }
                              try {
                                await c.removeSchedule(s);
                              } catch (e) {
                                toast(e.toString());
                              }
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Eliminar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
        const SizedBox(height: 12),
        const Text(
          'Puedes crear, por ejemplo, una regla para encender por la mañana y otra para apagar por la noche. Archivar y desarchivar son acciones independientes. No se permiten dos reglas activas para el mismo servidor en el mismo minuto y días coincidentes.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Mantén la app abierta y activa. No se recuperan horarios perdidos ni se reintentan escrituras automáticamente. El estado se comprueba cada 15 segundos. Para ejecución permanente, configura un servicio externo; consulta README.md.',
        ),
      ],
    );
  }

  Widget settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'Tu conexión con Clouding',
        'Una API KEY, acceso directo a tu infraestructura.',
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    c.connected
                        ? Icons.check_circle_outline
                        : Icons.key_outlined,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      c.connected ? 'API KEY validada' : 'Configurar API KEY',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                kIsWeb
                    ? 'En Web, una conexión directa expone la clave al navegador. Se guarda en el almacenamiento local del navegador y se recupera al abrir la app. Otros scripts del mismo origen pueden acceder a ella; puedes borrarla con Eliminar clave. CORS permite las consultas y acciones comprobadas, pero puede cambiar. Usa HTTPS y un navegador de confianza.'
                    : 'La clave se guarda cifrada con flutter_secure_storage y protección de Android Keystore. Nunca se muestra la clave guardada.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: keyInput,
                obscureText: obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'API KEY',
                  hintText: c.connected
                      ? 'Introduce una nueva clave para reemplazarla'
                      : 'Introduce tu clave de Clouding',
                  suffixIcon: IconButton(
                    tooltip: obscure ? 'Mostrar clave' : 'Ocultar clave',
                    onPressed: () => setState(() => obscure = !obscure),
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: (c.busy || detailsLoading)
                        ? null
                        : () async {
                            if (keyInput.text.trim().isEmpty) {
                              toast('Introduce una API KEY.');
                              return;
                            }
                            if (c.connected &&
                                !await confirm(
                                  'Reemplazar API KEY',
                                  'Se validará la nueva clave y se eliminarán las programaciones actuales.',
                                )) {
                              return;
                            }
                            await c.connect(keyInput.text);
                            if (c.error == null) keyInput.clear();
                          },
                    icon: const Icon(Icons.link),
                    label: Text('Validar y guardar'),
                  ),
                  if (c.connected)
                    OutlinedButton.icon(
                      onPressed: (c.credentialBusy || detailsLoading)
                          ? null
                          : () async {
                              if (await confirm(
                                'Eliminar API KEY',
                                'Se eliminará la clave y las programaciones de este dispositivo. No afecta a tus servidores.',
                              )) {
                                await c.disconnect();
                                keyInput.clear();
                              }
                            },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Eliminar clave'),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'La validación solo consulta GET /servers. Para administrar necesitas permisos Operator; para cambiar nombres, Administrator.',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Apariencia', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: ThemeMode.values
                    .map(
                      (v) => ChoiceChip(
                        label: Text(switch (v) {
                          ThemeMode.system => 'Sistema',
                          ThemeMode.light => 'Claro',
                          ThemeMode.dark => 'Oscuro',
                        }),
                        selected: c.theme == v,
                        onSelected: (_) => c.setTheme(v),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
