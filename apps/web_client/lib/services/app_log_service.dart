import 'package:flutter/foundation.dart';

enum LogLevel { info, warning, error, success }

class LogEntry {
  const LogEntry({
    required this.id,
    required this.timestamp,
    required this.message,
    this.tag = 'System',
    this.level = LogLevel.info,
    this.details,
  });

  final String id;
  final DateTime timestamp;
  final String message;
  final String tag;
  final LogLevel level;
  final String? details;

  String get timeFormatted {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  String toString() {
    final lvl = level.name.toUpperCase();
    final d = details != null ? ' | Details: $details' : '';
    return '[$timeFormatted] [$lvl] [$tag] $message$d';
  }
}

/// ລະບົບບັນທຶກ Log ສຳລັບກວດສອບບັນຫາ WebRTC, Signaling ແລະ ການໂອນໄຟລ໌
class AppLogService extends ChangeNotifier {
  AppLogService._();
  static final AppLogService instance = AppLogService._();

  static const int _maxLogs = 300;
  final List<LogEntry> _logs = [];

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void add(
    String message, {
    String tag = 'System',
    LogLevel level = LogLevel.info,
    dynamic error,
  }) {
    final entry = LogEntry(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      timestamp: DateTime.now(),
      message: message,
      tag: tag,
      level: level,
      details: error?.toString(),
    );

    _logs.insert(0, entry);
    if (_logs.length > _maxLogs) {
      _logs.removeRange(_maxLogs, _logs.length);
    }

    if (kDebugMode) {
      debugPrint('[${entry.tag}] ${entry.message} ${error ?? ''}');
    }

    notifyListeners();
  }

  void info(String message, {String tag = 'System'}) {
    add(message, tag: tag, level: LogLevel.info);
  }

  void success(String message, {String tag = 'System'}) {
    add(message, tag: tag, level: LogLevel.success);
  }

  void warn(String message, {String tag = 'System', dynamic error}) {
    add(message, tag: tag, level: LogLevel.warning, error: error);
  }

  void error(String message, {String tag = 'System', dynamic error}) {
    add(message, tag: tag, level: LogLevel.error, error: error);
  }

  void clear() {
    _logs.clear();
    notifyListeners();
  }

  String exportText() {
    if (_logs.isEmpty) return 'ບໍ່ມີບັນທຶກ Log';
    return _logs.reversed.map((e) => e.toString()).join('\n');
  }
}
