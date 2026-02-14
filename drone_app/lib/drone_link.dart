import 'dart:async';
import 'bluetooth_service.dart';

// ============================================================================
// DroneLink Service
//
// Encapsule la communication Bluetooth avec le drone Arduino.
// Gère :
//   - Connexion/Déconnexion
//   - Lecture de la télémétrie (trame BT)
//   - Envoi des commandes joystick normalisées
//   - Arm/Disarm/EmergencyStop
//
// Format trame reçue (Arduino, 800ms):
//   P:128|A:0.5|D:10.2|R:45.0|C:270|M:FLIGHT
// ============================================================================

// Configuration du mappage joystick → commandes
class DroneCommandConfig {
  static const int minPwm = 50;
  static const int maxPwm = 255;
  static const int pwmCenter = 150;
  static const double rollSensitivity = 0.8;
  static const double pitchSensitivity = 0.8;
  static const double yawSensitivity = 0.7;
  static const double throttleSensitivity = 1.0;
  static const double deadzone = 0.05;
  static const int pollIntervalMs = 100;
}

/// Données de télémétrie du drone
class TelemetryData {
  final int power; // PWM 0-255
  final double acceleration; // m/s²
  final double distance; // m (par intégration accélération)
  final double rotation; // °/s (vitesse angulaire)
  final double heading; // ° (0-360, cap magnétique)
  final String mode; // "FLIGHT", "LAND", etc.
  final DateTime timestamp;

  TelemetryData({
    required this.power,
    required this.acceleration,
    required this.distance,
    required this.rotation,
    required this.heading,
    required this.mode,
    required this.timestamp,
  });

  @override
  String toString() =>
      'Telem(P:$power A:$acceleration D:$distance R:$rotation C:$heading M:$mode)';
}

/// Commandes normalisées à envoyer au drone
class DroneCommand {
  final double throttle; // [0, 1] (0=arrêté, 1=max)
  final double roll; // [-1, 1]
  final double pitch; // [-1, 1]
  final double yaw; // [-1, 1]

  DroneCommand({
    required this.throttle,
    required this.roll,
    required this.pitch,
    required this.yaw,
  });

  @override
  String toString() =>
      'Cmd(T:${throttle.toStringAsFixed(2)} R:${roll.toStringAsFixed(2)} P:${pitch.toStringAsFixed(2)} Y:${yaw.toStringAsFixed(2)})';
}

/// Information d'un appareil Bluetooth
class BluetoothDeviceInfo {
  final String name;
  final String address;

  BluetoothDeviceInfo({required this.name, required this.address});

  @override
  String toString() => '$name ($address)';
}

/// Service de communication avec le drone
class DroneLink {
  late final BluetoothService _btService;
  bool _isConnected = false;
  bool _isArmed = false;
  Timer? _pollTimer;
  StreamSubscription<String>? _btDataSubscription;

  final StreamController<TelemetryData> _telemetryController =
      StreamController<TelemetryData>.broadcast();

  Stream<TelemetryData> get onTelemetryUpdated => _telemetryController.stream;

  Function(bool)? onConnectionChanged;
  Function(bool)? onArmChanged;

  DroneLink() {
    _btService = BluetoothService();
    _btService.onConnectionStateChanged = _onBtConnectionChanged;
  }

  void _onBtConnectionChanged(bool connected) {
    _isConnected = connected;
    onConnectionChanged?.call(connected);

    if (connected) {
      _startPolling();
      _subscribeToBtData();
    } else {
      _stopPolling();
      _btDataSubscription?.cancel();
      _isArmed = false;
      onArmChanged?.call(false);
    }
  }

  void _subscribeToBtData() {
    _btDataSubscription?.cancel();
    _btDataSubscription = _btService.dataStream.listen(
      (data) {
        final telem = parseTelemetryFrame(data);
        if (telem != null) {
          _telemetryController.add(telem);
        }
      },
      onError: (e) {
        print('[DroneLink] Erreur stream BT: $e');
      },
    );
  }

  TelemetryData _generateMockTelemetry() {
    return TelemetryData(
      power: 128,
      acceleration: 0.5,
      distance: 10.2,
      rotation: 45.0,
      heading: 270.0,
      mode: 'FLIGHT',
      timestamp: DateTime.now(),
    );
  }

  Future<bool> connect({required String deviceAddress}) async {
    try {
      print('[DroneLink] Tentative connexion à $deviceAddress...');
      final result = await _btService.connect(deviceAddress: deviceAddress);

      if (result) {
        _isConnected = true;
        onConnectionChanged?.call(true);
        _startPolling();
        _subscribeToBtData();
        print('[DroneLink] ✓ Connecté au drone');
        return true;
      } else {
        _isConnected = false;
        onConnectionChanged?.call(false);
        print('[DroneLink] ✗ Erreur connexion');
        return false;
      }
    } catch (e) {
      print('[DroneLink] Erreur connexion: $e');
      _isConnected = false;
      onConnectionChanged?.call(false);
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      _stopPolling();
      _btDataSubscription?.cancel();
      await _btService.disconnect();
      _isConnected = false;
      _isArmed = false;
      onConnectionChanged?.call(false);
      onArmChanged?.call(false);
      print('[DroneLink] Déconnecté');
    } catch (e) {
      print('[DroneLink] Erreur déconnexion: $e');
    }
  }

  bool get isConnected => _isConnected;
  bool get isArmed => _isArmed;

  void _startPolling() {
    _pollTimer = Timer.periodic(
      Duration(milliseconds: DroneCommandConfig.pollIntervalMs),
      (_) => _pollTelemetry(),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _pollTelemetry() {
    // La télémétrie est maintenant lue directement du stream Bluetooth
    // via _subscribeToBtData() et parseTelemetryFrame()
    //
    // Ce timer existe pour compatibility avec le cycle d'événements,
    // mais la plupart des données viennent du stream BT.

    if (!_isConnected) {
      // En mode démo (pas connecté), générer mock data
      final telem = _generateMockTelemetry();
      _telemetryController.add(telem);
    }
  }

  /// Parse telemetry frame from Arduino
  /// Parse telemetry frame from Arduino
  /// Accepted formats:
  ///  - New Arduino telemetry line: "P:<power_percent>|A:<pitch_deg>|C:<heading>|H:<altitude>"
  ///  - Legacy frame: <...> (kept for compatibility)
  TelemetryData? parseTelemetryFrame(String frame) {
    try {
      final s = frame.trim();

      int power = 0;
      double acceleration = 0.0;
      double distance = 0.0;
      double rotation = 0.0; // we'll store pitch here for UI mapping
      double heading = 0.0;
      String mode = 'FLIGHT';

      // If it's a legacy angle-bracket frame, try to parse numbers
      if (s.startsWith('<') && s.endsWith('>')) {
        // legacy: <throttle,pitch,roll,yaw>
        final inner = s.substring(1, s.length - 1);
        final parts = inner.split(',');
        if (parts.isNotEmpty) {
          try {
            final t = int.parse(parts[0]);
            power = t;
          } catch (_) {}
        }
      } else if (s.contains('|')) {
        final parts = s.split('|');
        for (final part in parts) {
          final kv = part.split(':');
          if (kv.length != 2) continue;
          final key = kv[0].trim();
          final value = kv[1].trim();
          try {
            switch (key) {
              case 'P':
                power = int.parse(value);
                break;
              case 'A':
                // Arduino 'A' is pitch in degrees
                rotation = double.parse(value);
                break;
              case 'C':
                heading = double.parse(value);
                break;
              case 'H':
                distance = double.parse(value);
                break;
            }
          } catch (e) {
            print('[DroneLink] Error parsing $key:$value -> $e');
          }
        }
      } else {
        // Unknown format
        print('[DroneLink] Unknown telemetry format: $s');
        return null;
      }

      return TelemetryData(
        power: power,
        acceleration: acceleration,
        distance: distance,
        rotation: rotation,
        heading: heading,
        mode: mode,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      print('[DroneLink] Telemetry parse error: $e');
      return null;
    }
  }

  Future<void> sendCommand(DroneCommand cmd) async {
    if (!_isConnected) return;
    try {
      // Convertir les valeurs normalisées en PWM [1000-2000] pour Arduino
      // Throttle: [0,1] → PWM [1000,2000]
      int pwmThrottle = 1000 + (cmd.throttle * 1000).toInt();
      pwmThrottle = pwmThrottle.clamp(1000, 2000);

      // Pitch/Roll/Yaw: [-1,1] → PWM [1000,2000] avec center=1500
      int pwmPitch = 1500 + (cmd.pitch * 500).toInt();
      pwmPitch = pwmPitch.clamp(1000, 2000);

      int pwmRoll = 1500 + (cmd.roll * 500).toInt();
      pwmRoll = pwmRoll.clamp(1000, 2000);

      int pwmYaw = 1500 + (cmd.yaw * 500).toInt();
      pwmYaw = pwmYaw.clamp(1000, 2000);

      // Format Arduino: <THROTTLE,PITCH,ROLL,YAW>
      String frame = '<$pwmThrottle,$pwmPitch,$pwmRoll,$pwmYaw>\n';

      // Envoyer via Bluetooth
      final result = await _btService.sendData(frame);

      if (!result) {
        print('[DroneLink] Erreur: commande non envoyée');
      }
    } catch (e) {
      print('[DroneLink] Erreur envoi CMD: $e');
    }
  }

  Future<void> arm() async {
    if (!_isConnected || _isArmed) return;
    try {
      await _sendBtCommand('A');
      _isArmed = true;
      onArmChanged?.call(true);
      print('[DroneLink] MOTEURS ARMÉS');
    } catch (e) {
      print('[DroneLink] Erreur arm: $e');
    }
  }

  Future<void> disarm() async {
    if (!_isConnected || !_isArmed) return;
    try {
      await _sendBtCommand('D');
      _isArmed = false;
      onArmChanged?.call(false);
      print('[DroneLink] MOTEURS DÉSARMÉS');
    } catch (e) {
      print('[DroneLink] Erreur disarm: $e');
    }
  }

  Future<void> emergencyStop() async {
    if (!_isConnected) return;
    try {
      await _sendBtCommand('S');
      _isArmed = false;
      onArmChanged?.call(false);
      print('[DroneLink] ⚠️ COUPURE D\'URGENCE');
    } catch (e) {
      print('[DroneLink] Erreur emergency: $e');
    }
  }

  Future<void> autoLand() async {
    if (!_isConnected) return;
    try {
      await _sendBtCommand('LAND');
      print('[DroneLink] ATTERRISSAGE AUTOMATIQUE engagé');
    } catch (e) {
      print('[DroneLink] Erreur auto-land: $e');
    }
  }

  Future<void> abortLanding() async {
    if (!_isConnected) return;
    try {
      await _sendBtCommand('ABORT_LAND');
      print('[DroneLink] Atterrissage annulé');
    } catch (e) {
      print('[DroneLink] Erreur abort: $e');
    }
  }

  Future<void> _sendBtCommand(String command) async {
    if (!_isConnected) return;
    try {
      // Envoyer commande texte avec newline (backward-compatible)
      await _btService.sendData('$command\n');
    } catch (e) {
      print('[DroneLink] Erreur envoi: $e');
    }
  }

  /// Envoyer exactement un octet ASCII (raw) — utile pour HC-06 Arduino
  Future<bool> sendRawByte(String ch) async {
    if (!_isConnected) return false;
    try {
      final ok = await _btService.sendRawByte(ch);
      return ok;
    } catch (e) {
      print('[DroneLink] Erreur sendRawByte: $e');
      return false;
    }
  }

  // ========================================================================
  // Helpers pour la gestion Bluetooth
  // ========================================================================

  /// Obtenir la liste des appareils Bluetooth disponibles
  Future<List<BluetoothDeviceInfo>> getAvailableDevices() async {
    try {
      final devices = await _btService.getAvailableDevices();
      return devices
          .map(
            (d) => BluetoothDeviceInfo(
              name: d.name ?? 'Unknown',
              address: d.address ?? '',
            ),
          )
          .toList();
    } catch (e) {
      print('[DroneLink] Erreur lecture appareils: $e');
      return [];
    }
  }

  void dispose() {
    _stopPolling();
    _btDataSubscription?.cancel();
    _telemetryController.close();
    _btService.dispose();
  }
}

// Helpers
double applyDeadzoneAndSensitivity(
  double value,
  double deadzone,
  double sensitivity,
) {
  if (value.abs() < deadzone) return 0.0;
  final result = value * sensitivity;
  return result.clamp(-1.0, 1.0);
}

int throttleToPwm(double throttle) {
  final pwm =
      DroneCommandConfig.minPwm +
      (throttle * (DroneCommandConfig.maxPwm - DroneCommandConfig.minPwm));
  return pwm.toInt().clamp(
    DroneCommandConfig.minPwm,
    DroneCommandConfig.maxPwm,
  );
}
