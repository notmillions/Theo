import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'debug_terminal/app_log_singleton.dart';

// ============================================================================
// BluetoothService
//
// Encapsule la communication Bluetooth série avec le drone Arduino.
// Gère :
//   - Découverte des appareils Bluetooth
//   - Connexion/Déconnexion
//   - Envoi et réception de données
//   - Gestion des erreurs et reconnexion
// ============================================================================

class BluetoothService {
  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;

  BluetoothConnection? _connection;
  bool _isConnected = false;
  final _dataStreamController = StreamController<String>.broadcast();
  // Buffer persistant pour recomposer les trames reçues en paquets
  String _rxBuffer = '';

  Function(bool)? onConnectionStateChanged;

  Stream<String> get dataStream => _dataStreamController.stream;
  bool get isConnected => _isConnected;

  /// Ensure required Bluetooth permissions (Android)
  Future<bool> ensurePermissions() async {
    if (!Platform.isAndroid) return true;

    // Request modern Bluetooth permissions and legacy location (for discovery)
    final perms = <Permission>[];
    perms.add(Permission.bluetoothConnect);
    perms.add(Permission.bluetoothScan);
    perms.add(Permission.locationWhenInUse);

    final statuses = await perms.request();

    bool ok = statuses.values.every((s) => s.isGranted);
    if (!ok) {
      print('[BT-Service] Permissions Bluetooth non accordées');
      appLog.logError('Permissions Bluetooth non accordées');
    }
    return ok;
  }

  /// Obtenir la liste des appareils Bluetooth disponibles
  Future<List<BluetoothDevice>> getAvailableDevices() async {
    try {
      final ok = await ensurePermissions();
      if (!ok) return [];
      final devices = await _bluetooth.getBondedDevices();
      return devices.toList();
    } catch (e) {
      print('[BT-Service] Erreur obtention appareils: $e');
      return [];
    }
  }

  /// Connecter à un appareil Bluetooth par adresse
  Future<bool> connect({required String deviceAddress}) async {
    try {
      if (_isConnected) {
        print('[BT-Service] Déjà connecté');
        return true;
      }

      print('[BT-Service] Tentative connexion à $deviceAddress...');
      appLog.logInfo('Tentative connexion à $deviceAddress');

      final ok = await ensurePermissions();
      if (!ok) return false;

      // Use RFCOMM/SPP via address
      _connection = await BluetoothConnection.toAddress(deviceAddress);

      if (_connection != null && _connection!.isConnected) {
        _isConnected = true;
        onConnectionStateChanged?.call(true);
        _startListening();
        print('[BT-Service] ✓ Connecté avec succès');
        appLog.logInfo('Connecté');
        return true;
      } else {
        _isConnected = false;
        onConnectionStateChanged?.call(false);
        print('[BT-Service] ✗ Erreur: connexion échouée');
        appLog.logError('Connexion échouée');
        return false;
      }
    } catch (e) {
      _isConnected = false;
      onConnectionStateChanged?.call(false);
      print('[BT-Service] Exception connexion: $e');
      appLog.logError('Exception connexion: $e');
      return false;
    }
  }

  /// Déconnecter de l'appareil Bluetooth
  Future<bool> disconnect() async {
    try {
      if (_connection != null) {
        await _connection?.close();
        _connection = null;
      }
      _isConnected = false;
      onConnectionStateChanged?.call(false);
      print('[BT-Service] Déconnecté');
      appLog.logInfo('Déconnecté');
      return true;
    } catch (e) {
      print('[BT-Service] Erreur déconnexion: $e');
      appLog.logError('Erreur déconnexion: $e');
      return false;
    }
  }

  /// Envoyer une commande texte via Bluetooth
  Future<bool> sendData(String data) async {
    try {
      if (!_isConnected || _connection == null) {
        print('[BT-Service] Pas connecté, impossible d\'envoyer: $data');
        return false;
      }

      // Standardiser la trame : s'assurer d'un séparateur final (">" + '\n')
      if (!data.endsWith('\n')) {
        if (!data.endsWith('>')) {
          data = data + '>' + '\n';
        } else {
          data = data + '\n';
        }
      }

      // Convertir la chaîne en bytes UTF-8 et envoyer
      final bytes = Uint8List.fromList(utf8.encode(data));
      _connection!.output.add(bytes);
      await _connection!.output.allSent;

      print('[BT-Service] √ Envoyé: $data');
      appLog.logTx(data);
      return true;
    } catch (e) {
      print('[BT-Service] Erreur envoi: $e');
      _isConnected = false;
      onConnectionStateChanged?.call(false);
      return false;
    }
  }

  /// Envoyer un octet brut (exactement 1 caractère ASCII) sans modification
  /// Utilisé pour protocoles qui lisent char par char (ex: HC-06 Arduino)
  Future<bool> sendRawByte(String ch) async {
    try {
      if (!_isConnected || _connection == null) {
        print('[BT-Service] Pas connecté, impossible d\'envoyer raw: $ch');
        return false;
      }

      if (ch.isEmpty) return false;
      final char = ch[0]; // envoyer uniquement le premier caractère
      final bytes = Uint8List.fromList(utf8.encode(char));
      _connection!.output.add(bytes);
      await _connection!.output.allSent;

      print('[BT-Service] √ Envoyé raw: $char');
      appLog.logTx('RAW:$char');
      return true;
    } catch (e) {
      print('[BT-Service] Erreur envoi raw: $e');
      _isConnected = false;
      onConnectionStateChanged?.call(false);
      return false;
    }
  }

  /// Écouter les données reçues du Bluetooth
  void _startListening() {
    if (_connection == null) return;

    final decoder = Utf8Decoder(allowMalformed: true);

    _connection!.input!
        .listen(
          (Uint8List data) {
            try {
              // Décoder en tolérant les séquences malformées
              final chunk = decoder.convert(data);

              // Ajouter au buffer persistant
              _rxBuffer += chunk;

              // Anti-bloat : conserver uniquement la queue si le buffer devient trop grand
              if (_rxBuffer.length > 4096) {
                // Garder les 1024 derniers caractères pour tenter de conserver une trame partielle
                _rxBuffer = _rxBuffer.substring(_rxBuffer.length - 1024);
                print('[BT-Service] ⚠️ Buffer tronqué pour éviter bloat');
                appLog.logInfo('Buffer tronqué (anti-bloat)');
              }

              // Traiter deux formats attendus :
              // 1) Lignes terminées par '\n' (ex: Arduino P:..|A:..|C:..|H:..\n)
              // 2) Trames encadrées par <...> (ancien format/compat)
              while (true) {
                // Prioriser les lignes '\n' (Arduino telemetry)
                final nlIdx = _rxBuffer.indexOf('\n');
                if (nlIdx != -1) {
                  final line = _rxBuffer.substring(0, nlIdx);
                  _rxBuffer = _rxBuffer.substring(nlIdx + 1);
                  final cleanedLine = line.replaceAll('\r', '').trim();
                  if (cleanedLine.isNotEmpty) {
                    print('[BT-Service] ← Reçu (line): $cleanedLine');
                    appLog.logRx(cleanedLine);
                    _dataStreamController.add(cleanedLine);
                  }
                  continue; // re-check buffer
                }

                // Ensuite, traiter les trames <...>
                final endIdx = _rxBuffer.indexOf('>');
                if (endIdx == -1) break; // pas de trame complète disponible

                // Extraire jusqu'à la première '>' incluse
                final segment = _rxBuffer.substring(0, endIdx + 1);
                // Enlever le segment traité du buffer
                _rxBuffer = _rxBuffer.substring(endIdx + 1);

                // Nettoyer CR/LF
                final cleaned = segment
                    .replaceAll('\r', '')
                    .replaceAll('\n', '');

                // Extraire toutes les trames valides de la forme <...>
                final regExp = RegExp(r'<[^>]*>');
                final matches = regExp.allMatches(cleaned);
                for (final m in matches) {
                  final frame = m.group(0)!.trim();
                  if (frame.isNotEmpty) {
                    print('[BT-Service] ← Reçu (frame): $frame');
                    appLog.logRx(frame);
                    _dataStreamController.add(frame);
                  }
                }
                // Si aucun match trouvé (par ex. fragment sans '<'), on ignore ce segment
              }
            } catch (e) {
              print('[BT-Service] Erreur parsing données: $e');
            }
          },
          onDone: () {
            print('[BT-Service] ✗ Connexion fermée par l\'appareil');
            appLog.logError('Connexion fermée par l\'appareil');
            _isConnected = false;
            onConnectionStateChanged?.call(false);
          },
          onError: (e) {
            print('[BT-Service] Erreur sur le stream: $e');
            appLog.logError('Erreur stream: $e');
            _isConnected = false;
            onConnectionStateChanged?.call(false);
          },
        )
        .onError((error) {
          print('[BT-Service] Erreur listener: $error');
          _isConnected = false;
          onConnectionStateChanged?.call(false);
        });
  }

  /// Nettoyer les ressources
  void dispose() {
    _dataStreamController.close();
    _connection?.close();
    _connection = null;
  }
}
