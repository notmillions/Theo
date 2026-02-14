import 'app_log_buffer.dart';

/// Instance globale léger du buffer de logs pour l'app.
/// Utilisé par BluetoothService et le TerminalPage pour TX/RX/INFO/ERROR.
final AppLogBuffer appLog = AppLogBuffer();
