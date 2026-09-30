class Server {
  Server(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get name => data['name'] as String? ?? id;
  String get status => data['status'] as String? ?? 'Unknown';
  bool get archived => status == 'Archived';
  bool get running => data['powerState'] == 'Running';
  bool get stable => ['Active', 'Stopped', 'Archived'].contains(status);
  num? get cpu => data['vCores'] as num?;
  num? get ram => data['ramGb'] as num?;
  num? get disk => data['volumeSizeGb'] as num?;
  Map<String, dynamic>? get cost => data['cost'] as Map<String, dynamic>?;
  List<String> get ips {
    final ports = [
      ...?data['publicPorts'] as List?,
      ...?data['vpcPorts'] as List?,
    ];
    final values = ports.map((p) => p['ipAddress']).whereType<String>().toSet();
    if (values.isEmpty) {
      values.addAll([data['publicIp'], data['privateIp']].whereType<String>());
    }
    return values.toList();
  }
}

class ArchiveSchedule {
  ArchiveSchedule({
    required this.id,
    required this.serverId,
    required this.days,
    required this.hour,
    required this.minute,
    this.enabled = true,
    this.lastRun,
  });
  final String id, serverId;
  final List<int> days;
  final int hour, minute;
  bool enabled;
  String? lastRun;
  String occurrence(DateTime now) => '${now.year}-${now.month}-${now.day}';
  bool due(DateTime now) =>
      enabled &&
      days.contains(now.weekday) &&
      now.hour == hour &&
      now.minute == minute &&
      lastRun != occurrence(now);
  Map<String, dynamic> toJson() => {
    'id': id,
    'serverId': serverId,
    'days': days,
    'hour': hour,
    'minute': minute,
    'enabled': enabled,
    'lastRun': lastRun,
  };
  factory ArchiveSchedule.fromJson(Map<String, dynamic> j) => ArchiveSchedule(
    id: j['id'],
    serverId: j['serverId'],
    days: List<int>.from(j['days']),
    hour: j['hour'],
    minute: j['minute'],
    enabled: j['enabled'],
    lastRun: j['lastRun'],
  );
}
