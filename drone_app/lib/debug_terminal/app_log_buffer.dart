import 'package:flutter/foundation.dart';

enum LogKind { tx, rx, info, error }

class LogEntry {
  final DateTime ts;
  final LogKind kind;
  final String msg;

  LogEntry({required this.ts, required this.kind, required this.msg});

  String get formattedKind {
    switch (kind) {
      case LogKind.tx:
        return 'TX';
      case LogKind.rx:
        return 'RX';
      case LogKind.info:
        return 'INFO';
      case LogKind.error:
        return 'ERROR';
    }
  }

  String get formatted {
    final h = ts.hour.toString().padLeft(2, '0');
    final m = ts.minute.toString().padLeft(2, '0');
    final s = ts.second.toString().padLeft(2, '0');
    final ms = ts.millisecond.toString().padLeft(3, '0');
    return '[$h:$m:$s.$ms] [$formattedKind] $msg';
  }
}

/// Buffer persistant pour logguer les événements Bluetooth (TX/RX/INFO/ERROR).
/// Max 500 lignes ; les plus anciennes sont supprimées automatiquement.
class AppLogBuffer extends ChangeNotifier {
  static const int maxEntries = 500;

  final List<LogEntry> _entries = [];

  /// Lister immédiatement les entrées (pour observateurs)
  List<LogEntry> get entries => List.unmodifiable(_entries);

  /// Ajouter une entrée TX
  void logTx(String msg) {
    _add(LogEntry(ts: DateTime.now(), kind: LogKind.tx, msg: msg));
  }

  /// Ajouter une entrée RX
  void logRx(String msg) {
    _add(LogEntry(ts: DateTime.now(), kind: LogKind.rx, msg: msg));
  }

  /// Ajouter une entrée INFO
  void logInfo(String msg) {
    _add(LogEntry(ts: DateTime.now(), kind: LogKind.info, msg: msg));
  }

  /// Ajouter une entrée ERROR
  void logError(String msg) {
    _add(LogEntry(ts: DateTime.now(), kind: LogKind.error, msg: msg));
  }

  void _add(LogEntry entry) {
    _entries.add(entry);
    // Supprimer les plus anciennes si dépassement
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    notifyListeners();
  }

  /// Vider tout le buffer
  void clear() {
    _entries.clear();
    notifyListeners();
  }

  /// Exporter le contenu au format texte (pour copie en presse-papiers)
  String exportText() {
    return _entries.map((e) => e.formatted).join('\n');
  }
}
